/** Square V2 encoder-response fit: train 1,4; parameter holdout 5.
 * See knowledge-base/square-corner-fix-20261112/fit.json. Not physical geometry calibration.
 */
class ModelCalibration_c {
  final float wheelRadiusMm=16.10f, wheelSeparationMm=83.6f;
  final float leftForwardGain=0.008676238904f, leftReverseGain=0.008676238904f;
  final float rightForwardGain=0.01119120295f, rightReverseGain=0.01068616236f;
  final float responseTauMs=77.32465247f;
  final float coastTauMs=10.47762097f;
}
