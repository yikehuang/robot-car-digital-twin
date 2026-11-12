/**
 * @brief Effective PWM-to-encoder response fitted on recorded trials 1 and 3.
 * @note Gains are in encoder counts/ms/PWM. Geometry is a separate assumption.
 */
class MotorsModel_c {
  final float maximumWheelSpeedMmPerMs = 0.25;
  boolean fitted=true;
  ModelCalibration_c calibration=new ModelCalibration_c();
  MotorModel_c left = new MotorModel_c();
  MotorModel_c right = new MotorModel_c();

  /** @brief Stores requested left and right PWM values after limiting them. */
  void setPWM(float leftPwm, float rightPwm) {
    left.setPWM(leftPwm);
    right.setPWM(rightPwm);
  }

  void reset() {left.reset();right.reset();}
  /** Integrates a first-order response exactly over one constant-command step. */
  void update(float mmPerCount,int dtMs) {
    if(fitted) {
      left.updateFitted(calibration.leftForwardGain,calibration.leftReverseGain,calibration.responseTauMs,calibration.coastTauMs,mmPerCount,dtMs);
      right.updateFitted(calibration.rightForwardGain,calibration.rightReverseGain,calibration.responseTauMs,calibration.coastTauMs,mmPerCount,dtMs);
    } else {
      left.updateBaseline(maximumWheelSpeedMmPerMs,dtMs);
      right.updateBaseline(maximumWheelSpeedMmPerMs,dtMs);
    }
  }
}

/** @brief Ideal response model for one motor. */
class MotorModel_c {
  float pwm = 0;
  float speedMmPerMs = 0;
  float encoderRateCountsPerMs = 0;
  float stepDistanceMm = 0;
  void reset(){pwm=0;speedMmPerMs=0;encoderRateCountsPerMs=0;stepDistanceMm=0;}

  /** @brief Limits and stores a requested PWM value in [-200, +200]. */
  void setPWM(float value) { pwm = constrain(value, -200, 200); }

  /** @brief Maps the requested PWM linearly to wheel speed.
   * @param maximumSpeed Maximum wheel speed in mm/ms.
   */
  void updateBaseline(float maximumSpeed,int dtMs) {
    speedMmPerMs = map(pwm, -200, 200, -maximumSpeed, maximumSpeed);
    stepDistanceMm=speedMmPerMs*dtMs;
  }
  void updateFitted(float forwardGain,float reverseGain,float driveTauMs,float coastTauMs,float mmPerCount,int dtMs) {
    float tauMs=pwm==0?coastTauMs:driveTauMs;
    float target=pwm*(pwm>=0?forwardGain:reverseGain);
    float decay=(float)Math.exp(-dtMs/tauMs);
    float deltaCounts=target*dtMs+(encoderRateCountsPerMs-target)*tauMs*(1-decay);
    encoderRateCountsPerMs=target+(encoderRateCountsPerMs-target)*decay;
    speedMmPerMs=encoderRateCountsPerMs*mmPerCount;
    stepDistanceMm=deltaCounts*mmPerCount;
  }
}
