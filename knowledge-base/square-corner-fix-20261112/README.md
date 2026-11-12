# Square corner diagnosis and V3 revision — 12 November 2026

The request was to explain the large visible discrepancy near the lower-left corner, particularly after the second right turn, and improve both the real controller and digital twin.

## Observed evidence

source_square_v2.csv is a frozen byte copy of the active V2 log, containing 16,745 valid records with no clock resets. Its SHA-256 and interval quality checks are in fit.json. Original log files remain unchanged. Trials 1,4,5 completed; trials 2,3 first stopped with left_stalled. Trial 3 later received remote_stop; that later reason does not replace the initial failure. A stall flag does not identify whether the cause was contact, load, power, hardware or some other restriction.

For the most recent completed run (trial 5):

| Observation | Encoder-derived result |
|---|---:|
| First right turn | 88.23 degrees |
| Second right turn | 88.23 degrees |
| Third right turn | 88.43 degrees |
| Fourth right turn | 88.43 degrees |
| Heading after turn two | -177.44 degrees, target -180 |
| Lower-left corner | (3.077, -209.020) mm, target (0,-200) |
| Lower-left corner position discrepancy | 9.53 mm |
| Final closure discrepancy | 10.49 mm |
| Final heading discrepancy | +3.58 degrees |
| Start to first terminal record | 10.030 s |

These are wheel-odometry results, not externally measured motion. Turn changes are measured from the first through last received RUNNING record of that stage, including its settling samples; telemetry cadence limits exact boundary precision. Full stage records are in stage_audit.csv. The 2.56-degree heading discrepancy after corner two can produce about 8.9 mm lateral displacement over the next 200 mm, consistent in scale with the observed corner error. It is an explanatory estimate, not identification of motor torque or wheel geometry.

The large blue/orange separation is a different metric. On trial 5, the original model had time-aligned position RMSE 58.06 mm and maximum same-time separation 143.10 mm. Its independent route finished in 9.010 s, ahead of the real run. Equal device-clock time therefore does not imply equal route phase. This was prediction error, not evidence of queued animation or Wi-Fi latency. Network delay remains a separate unmeasured factor.

## Motor-model revision, evaluated separately

The original motor response came from an L route at a different command distribution. Square data showed lower effective left-wheel response and different driven/zero-command behaviour. The updated model fits three directional gains, a driven response time and a zero-command decay time using PWM-to-encoder increments only. The fitting objective does not use position, heading or endpoint error.

Trials 1 and 4 were used for fitting; trial 5 was excluded from parameter fitting. Trial 5 was inspected during diagnosis, so this is not a blind prospective validation. Failed trials 2 and 3 are excluded from healthy fitting and remain diagnostic evidence. Input treatment (stage-entry command reconstruction, same-tick collapse, midpoint approximation for nonzero commands and sampled zero edges) is explicit in analysis/fit_lpath_model.py and analysis/analyse_square_corners.py. Geometry is unchanged and is not inferred from derived pose.

| Effective parameter | Value |
|---|---:|
| Left forward gain | 0.00867624 counts/ms/PWM |
| Right forward gain | 0.01119120 counts/ms/PWM |
| Right reverse gain | 0.01068616 counts/ms/PWM |
| Driven response time | 77.32 ms |
| Zero-command response time | 10.48 ms |

These are effective sampled-response parameters, not isolated physical motor inertia, voltage or torque measurements. Left reverse remains an unobserved symmetry assumption. Fifty-millisecond telemetry cannot precisely locate each command transition or independently resolve true coasting dynamics; nonlinear friction, slip, geometry and battery effects are not separately identified.

To isolate model changes from control changes, SquareReplayEvaluation was run against the actual compiled **unchanged V2 controller** with the original and refitted plants:

| Trial 5 metric relative to odometry | Old plant | Refitted plant |
|---|---:|---:|
| Time-aligned position RMSE | 58.06 mm | 9.15 mm |
| Maximum same-time separation | 143.10 mm | 19.82 mm |
| Stopping-frame endpoint discrepancy | 17.30 mm | 19.36 mm |
| Stopping-frame heading discrepancy | -6.49 degrees | +7.55 degrees |
| Independent model completion time | 9.010 s | 9.850 s |

The refit improves the path/phase prediction but does not improve endpoint/heading agreement in that comparison. All metrics, including failed trials, are retained in old_plant_metrics.csv, refitted_plant_metrics.csv and their traces. Do not present the RMSE improvement as a physical V3 path result. A temporary check of the refitted plant with the old controller exposed poor synthetic closure; the old turn-stopping rule was then revised rather than relaxing the final test limits.

## Controller V3 changes

1. All headings are referenced to the run start. Clockwise corner goals are -90,-180,-270,-360 degrees relative to that heading; an earlier corner discrepancy is not accepted as the baseline for the next corner.
2. Straight sections use heading feedback to that side's target. They stop on average wheel travel (centre distance), rather than independently forcing both wheels to equal their local targets, which would restore an already incorrect starting heading.
3. Turns stop on the current cumulative odometry heading with a predicted coasting allowance, rather than solely on separate local count thresholds. Both wheels share the stop boundary.
4. Feedforward uses the square-data directional gains. The coast allowance uses the new effective zero-command response estimate rather than treating acceleration and braking as the same response. PWM bounds, feedback limits and stop/watchdog protections remain in place.

Firmware WheelSpeedControl.h/Controller.cpp and desktop SquareWheelControl.pde/LPathController.pde mirror these rules. The model still computes its own controller commands and pose. Orange telemetry is preserved; no measured trace is straightened or snapped to the target. It is heading control based on encoder odometry, not external localisation or lateral-position control.

Handshake SQUARE_REMOTE_V3 rejects older L/V2 control versions. Only SquareV3_ logs are restored in V3. Wi-Fi priority, access-point configuration and stored pairing are retained. Old V2 source and flashed binary are backed up in knowledge-base/firmware-backups/20261112_before_square_corner_fix; the local private key is not distributed.

## Validation boundary

The complete generated desktop Java compiled and the square motion, live-session and authentication suites passed. The installed native Processing CLI still has a library-discovery limitation; the entire freshly generated Java was compiled explicitly with core/net jars, not reported as a successful native CLI build.

Synthetic tests include left response factors 0.85/1/1.15, stall stopping, all eight stages, PWM limits, no automatic start, wrong-version rejection and safe history restoration. A separate +5-degree disturbance after corner two verifies that subsequent heading targets remain tied to the run start. Synthetic closure for that intervention is 1.26 mm, with final heading discrepancy -0.84 degrees. These are model tests, not hardware measurements.

Hardware compile/upload, read-only idle checks and non-start TCP integration are recorded in verification.json. No real START is sent during deployment. New V3 square runs with fixed parameters and an external distance/heading reference are still required. The software cannot infer or remove physical wheel slip or unequal rolling radii from encoder agreement alone.

Reproduce the frozen-data fit with `python analysis/analyse_square_corners.py` (NumPy/SciPy required). This regenerates ModelCalibration.pde; controller feedforward/coasting constants are separately frozen in the two controller implementations. Reproduce V2 replay using the backed-up V2 controller with the corresponding old/refitted plant, not the current V3 controller. Build/launch V3 using analysis/build_square_twin.ps1 and analysis/start_square_twin.ps1.
