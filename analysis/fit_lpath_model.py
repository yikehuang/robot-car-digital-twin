"""Fit a small motor-response model to recorded PWM/encoder intervals.

Fits trials 1 and 3 only. Trial 4 is reserved for parameter-fit validation;
trial 2's reported right_stalled failure is preserved but excluded from the
healthy-motor fit. No physical geometry is inferred from derived odometry.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from scipy.optimize import least_squares

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'robot-programs/DigitalTwin_LPath/logs/LPath_20261112_141319_4658.csv'
OUT = ROOT / 'knowledge-base/model-calibration-20261112'
TRAIN = (1, 3)
HOLDOUT = (4,)


def read_source(path, max_stage=3):
    rows, invalid, resets = [], 0, 0
    previous = None
    with path.open(encoding='utf-8-sig', newline='') as stream:
        for raw in csv.DictReader(stream):
            try:
                row = {name: int(raw[name]) for name in
                       ('trial', 'stage', 'state', 'time_ms', 'left_count', 'right_count', 'left_pwm', 'right_pwm')}
                row.update({name: float(raw[name]) for name in ('x_mm', 'y_mm', 'theta_rad')})
                row['reason'], row['direction'] = raw['reason'], raw['direction']
                assert row['state'] in range(4) and row['stage'] in range(max_stage+1)
                assert row['direction'] in ('CW', 'CCW')
                assert row['time_ms'] >= 0 and all(math.isfinite(row[k]) for k in ('x_mm', 'y_mm', 'theta_rad'))
                assert abs(row['left_pwm']) <= 200 and abs(row['right_pwm']) <= 200
            except (TypeError, ValueError, KeyError, AssertionError):
                invalid += 1
                continue
            if previous is not None and row['time_ms'] < previous:
                resets += 1
            previous = row['time_ms']
            rows.append(row)
    if invalid or resets:
        raise ValueError(f'Inspect source before fitting: invalid={invalid}, clock resets={resets}')
    return rows, {'raw_rows': len(rows), 'invalid_rows': invalid, 'clock_resets': resets}


def prepare(rows, trial, turn_stages=(1,)):
    records = [r for r in rows if r['trial'] == trial]
    moving = [r for r in records if r['state'] == 1]
    stopped = [r for r in records if r['state'] in (2, 3)]
    if not moving or not stopped:
        raise ValueError(f'Trial {trial} has no complete observed moving/stopping window')
    start, end = moving[0]['time_ms'], stopped[0]['time_ms']
    records = [r for r in records if start <= r['time_ms'] <= end + 150]
    collapsed, collisions, conflicts = [], 0, 0
    observables = ('left_count', 'right_count', 'x_mm', 'y_mm', 'theta_rad')
    for row in records:
        if collapsed and row['time_ms'] == collapsed[-1]['time_ms']:
            collisions += 1
            if any(row[k] != collapsed[-1][k] for k in observables):
                conflicts += 1
            # Controller emits before/after-command records at the same tick.
            # Keep the last command for the following interval; no encoder data
            # are averaged, fabricated or written back to the source CSV.
            collapsed[-1] = row
        else:
            collapsed.append(row)
    if conflicts:
        raise ValueError(f'Trial {trial}: conflicting same-timestamp observations')
    seen = set()
    for row in collapsed:
        stage = row['stage']
        row['stage_start'] = row['state'] == 1 and stage not in seen
        if row['state'] == 1:
            seen.add(stage)
    intervals = []
    reconstructed = 0
    for a, b in zip(collapsed, collapsed[1:]):
        dt = b['time_ms'] - a['time_ms']
        if dt <= 0 or dt > 200:
            raise ValueError(f'Trial {trial}: unsupported interval {dt} ms')
        commands = []
        for side in ('left', 'right'):
            pwm = float(a[side + '_pwm'])
            if a['stage_start'] and pwm == 0:
                sign = -1 if a['stage'] in turn_stages and side == 'right' else 1
                if a['direction'] == 'CCW' and a['stage'] in turn_stages:
                    sign *= -1
                pwm = 60.0 * sign
                reconstructed += 1
            nxt = b[side + '_pwm']
            if pwm * nxt > 0 and a['stage'] == b['stage'] and b['state'] == 1:
                pwm = (pwm + nxt) / 2
            commands.append(pwm)
        intervals.append((dt, *commands, b['left_count'] - a['left_count'], b['right_count'] - a['right_count']))
    return np.asarray(intervals, dtype=float), {
        'trial': trial, 'rows_in_window': len(records), 'unique_time_rows': len(collapsed),
        'same_tick_records_collapsed': collisions, 'same_tick_observation_conflicts': conflicts,
        'first_stop_reason': stopped[0]['reason'], 'run_duration_ms': end - start,
        'min_interval_ms': min(x[0] for x in intervals), 'max_interval_ms': max(x[0] for x in intervals),
        'stage_start_pwm_values_reconstructed_from_controller_code': reconstructed,
        'positive_left_samples': int(sum(x[1] > 0 for x in intervals)),
        'negative_left_samples': int(sum(x[1] < 0 for x in intervals)),
        'positive_right_samples': int(sum(x[2] > 0 for x in intervals)),
        'negative_right_samples': int(sum(x[2] < 0 for x in intervals)),
    }


def predict_intervals(parameters, intervals):
    gl, gr, gr_reverse, tau = parameters
    rate = np.zeros(2)
    result = []
    for dt, left, right, *_ in intervals:
        target = np.array([left * gl, right * (gr if right >= 0 else gr_reverse)])
        decay = math.exp(-dt / tau)
        delta = target * dt + (rate - target) * tau * (1 - decay)
        rate = target + (rate - target) * decay
        result.append(delta)
    return np.array(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write-config', action='store_true')
    args = parser.parse_args()
    rows, quality = read_source(SOURCE)
    datasets, profile = {}, []
    for trial in (1, 2, 3, 4):
        datasets[trial], info = prepare(rows, trial)
        profile.append(info)
    for trial in TRAIN:
        if next(p for p in profile if p['trial'] == trial)['first_stop_reason'] != 'complete':
            raise ValueError('Unhealthy trial selected for motor fitting')
    def residual(parameters):
        return np.concatenate([(predict_intervals(parameters, datasets[t]) - datasets[t][:, 3:5]).ravel() for t in TRAIN])
    fit = least_squares(residual, [0.009, 0.009, 0.009, 30.0],
                        bounds=([0.0001, 0.0001, 0.0001, 1.0], [0.03, 0.03, 0.03, 250.0]),
                        loss='soft_l1', f_scale=2.0, max_nfev=500)
    if not fit.success:
        raise RuntimeError(fit.message)
    gl, gr, reverse, tau = map(float, fit.x)
    parameters = dict(left_forward_counts_per_ms_per_pwm=gl,
                      right_forward_counts_per_ms_per_pwm=gr,
                      right_reverse_counts_per_ms_per_pwm=reverse,
                      response_tau_ms=tau,
                      left_reverse_counts_per_ms_per_pwm=gl,
                      left_reverse_status='unobserved; tied to left forward as a symmetry assumption')
    scores = []
    for trial, intervals in datasets.items():
        error = predict_intervals(fit.x, intervals) - intervals[:, 3:5]
        scores.append(dict(trial=trial, role='fit' if trial in TRAIN else 'fit_holdout' if trial in HOLDOUT else 'failure_diagnostic',
                           interval_encoder_rmse_counts=float(np.sqrt(np.mean(error**2)))))
    quality['trials'] = profile
    report = dict(source=str(SOURCE.relative_to(ROOT)), source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                  train_trials=TRAIN, parameter_fit_holdout=HOLDOUT, excluded_fit_trials={2:'reported right_stalled'},
                  parameters=parameters, geometry_alignment=dict(wheel_radius_mm=16.10, wheel_separation_mm=83.6,
                  encoder_counts_per_revolution=358.3, status='same units/convention as firmware odometry; not physical measurements'),
                  quality=quality, interval_scores=scores, fit_objective='robust PWM-to-encoder interval residuals; no pose/endpoint fitting',
                  caveats=['Only two healthy fitting runs and one parameter-fit holdout.',
                           'Trial 4 was inspected during earlier UI work; it is not a blind prospective test.',
                           'Recorded PWM is a sampled accepted request, not measured motor voltage.',
                           'Mid-interval PWM is approximated from adjacent samples; time constant is an effective sampled response.',
                           'Physical wheel radius/separation cannot be independently identified from encoder-derived pose.',
                           'Left reverse, anticlockwise routes, other batteries, surfaces and loads remain unvalidated.'])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'fit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    if args.write_config:
        source = f'''/** Encoder-response fit from trials 1,3; trial 4 excluded from parameter fitting.
 * Geometry matches firmware odometry units, not an independent physical measurement.
 * Left reverse was unobserved and assumes the forward gain. See knowledge-base/model-calibration-20261112/fit.json.
 */
class ModelCalibration_c {{
  final float wheelRadiusMm=16.10f, wheelSeparationMm=83.6f;
  final float leftForwardGain={gl:.10g}f;
  final float leftReverseGain={gl:.10g}f;
  final float rightForwardGain={gr:.10g}f;
  final float rightReverseGain={reverse:.10g}f;
  final float responseTauMs={tau:.10g}f;
}}
'''
        (ROOT / 'robot-programs/DigitalTwin_LPath/ModelCalibration.pde').write_text(source, encoding='utf-8')
    print(json.dumps(dict(parameters=parameters, interval_scores=scores, quality=profile), indent=2))


if __name__ == '__main__':
    main()
