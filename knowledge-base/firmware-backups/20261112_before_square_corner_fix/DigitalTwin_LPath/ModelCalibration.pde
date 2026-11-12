/** Encoder-response fit from trials 1,3; trial 4 excluded from parameter fitting.
 * Geometry matches firmware odometry units, not an independent physical measurement.
 * Left reverse was unobserved and assumes the forward gain. See knowledge-base/model-calibration-20261112/fit.json.
 */
class ModelCalibration_c {
  final float wheelRadiusMm=16.10f, wheelSeparationMm=83.6f;
  final float leftForwardGain=0.01022189486f;
  final float leftReverseGain=0.01022189486f;
  final float rightForwardGain=0.01176599982f;
  final float rightReverseGain=0.01135989616f;
  final float responseTauMs=35.49228695f;
}
