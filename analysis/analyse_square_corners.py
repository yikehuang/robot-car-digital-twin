"""Frozen square V2 audit and PWM/encoder refit; no hardware or pose fitting."""
from pathlib import Path
import csv, hashlib, json, math
import numpy as np
from scipy.optimize import least_squares
from fit_lpath_model import read_source, prepare, predict_intervals

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'knowledge-base/square-corner-fix-20261112'
SOURCE=OUT/'source_square_v2.csv'
rows,quality=read_source(SOURCE,max_stage=8)
stages=[]; summaries=[]
for trial in sorted({r['trial'] for r in rows}):
    moving=[r for r in rows if r['trial']==trial and r['state']==1]
    terminal=[r for r in rows if r['trial']==trial and r['state'] in (2,3)]
    if not moving or not terminal:continue
    stop=terminal[0]
    summaries.append(dict(trial=trial,reason=stop['reason'],duration_ms=stop['time_ms']-moving[0]['time_ms'],
        odometry_closure_mm=math.hypot(stop['x_mm'],stop['y_mm']),
        heading_error_deg=math.degrees(math.atan2(math.sin(stop['theta_rad']),math.cos(stop['theta_rad'])))))
    for stage in sorted({r['stage'] for r in moving}):
        records=[r for r in moving if r['stage']==stage];a,b=records[0],records[-1]
        desired=-((stage+1)//2)*90
        stages.append(dict(trial=trial,stage=stage,type='turn' if stage%2 else 'straight',
            elapsed_start_ms=a['time_ms']-moving[0]['time_ms'],duration_ms=b['time_ms']-a['time_ms'],
            left_counts=b['left_count']-a['left_count'],right_counts=b['right_count']-a['right_count'],
            heading_change_deg=math.degrees(b['theta_rad']-a['theta_rad']),
            end_heading_deg=math.degrees(b['theta_rad']),target_heading_deg=desired,
            heading_error_deg=math.degrees(b['theta_rad'])-desired,
            end_x_mm=b['x_mm'],end_y_mm=b['y_mm'],last_reason=b['reason']))
with (OUT/'stage_audit.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=list(stages[0]));w.writeheader();w.writerows(stages)

train=(1,4);holdout=(5,);datasets={};profiles=[]
for trial in train+holdout:
    data,profile=prepare(rows,trial,turn_stages=(1,3,5,7))
    assert profile['first_stop_reason']=='complete'
    datasets[trial]=data;profiles.append(profile)
def predict_square(params,intervals):
    gl,gr,rev,tau,coast=params;rate=np.zeros(2);result=[]
    for dt,l,r,*_ in intervals:
        target=np.array([l*gl,r*(gr if r>=0 else rev)])
        times=np.where(target==0,coast,tau)
        decay=np.exp(-dt/times)
        result.append(target*dt+(rate-target)*times*(1-decay))
        rate=target+(rate-target)*decay
    return np.asarray(result)
def residual(params):
    return np.concatenate([(predict_square(params,datasets[t])-datasets[t][:,3:5]).ravel() for t in train])
fit=least_squares(residual,[0.01,0.011,0.011,30,15],bounds=([0.0001]*3+[1,1],[0.03]*3+[250,250]),loss='soft_l1',f_scale=2,max_nfev=500)
assert fit.success,fit.message
old=[0.01022189486,0.01176599982,0.01135989616,35.49228695]
gl,gr,rev,tau,coast=map(float,fit.x)
scores=[]
for trial,data in datasets.items():
    score=dict(trial=trial,role='fit' if trial in train else 'parameter_fit_holdout')
    score['old_interval_rmse_counts']=float(np.sqrt(np.mean((predict_intervals(old,data)-data[:,3:5])**2)))
    score['new_interval_rmse_counts']=float(np.sqrt(np.mean((predict_square(fit.x,data)-data[:,3:5])**2)))
    scores.append(score)
result=dict(source=str(SOURCE.relative_to(ROOT)),source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    quality=quality,run_summaries=summaries,train_trials=train,parameter_fit_holdout=holdout,
    excluded_trials={'2':'left_stalled','3':'first terminal left_stalled; later remote_stop records do not replace first stop'},
    parameters=dict(left_forward_gain=gl,right_forward_gain=gr,right_reverse_gain=rev,response_tau_ms=tau,coast_tau_ms=coast,left_reverse_gain=gl,left_reverse_status='unobserved; symmetry assumption'),
    interval_scores=scores,fit_windows=profiles,
    limitations=['Encoder-derived pose is not independent physical ground truth.',
      'Trial 5 was inspected during diagnosis and is not a blind prospective test.',
      'Effective gains fit sampled accepted PWM requests, not measured voltage or motor torque.',
      'Low-PWM nonlinear response and zero-command coast cannot be isolated precisely at 50 ms telemetry cadence.',
      'Only the plant is refitted; updated heading feedback requires new physical validation.'])
(OUT/'fit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
# Plant fit only. Keep the controller's existing feedforward separate to avoid
# silently changing the experiment while evaluating the motor-model revision.
(ROOT/'robot-programs/DigitalTwin_LPath/ModelCalibration.pde').write_text(f'''/** Square V2 encoder-response fit: train 1,4; parameter holdout 5.
 * See knowledge-base/square-corner-fix-20261112/fit.json. Not physical geometry calibration.
 */
class ModelCalibration_c {{
  final float wheelRadiusMm=16.10f, wheelSeparationMm=83.6f;
  final float leftForwardGain={gl:.10g}f, leftReverseGain={gl:.10g}f;
  final float rightForwardGain={gr:.10g}f, rightReverseGain={rev:.10g}f;
  final float responseTauMs={tau:.10g}f;
  final float coastTauMs={coast:.10g}f;
}}
''',encoding='utf-8')
print(json.dumps(dict(run_summaries=summaries,parameters=result['parameters'],scores=scores),indent=2))
