#ifndef CONTROLLER_H
#define CONTROLLER_H

#include "Robot.h"
#include "RobotWifiAP.h"
#include "TaskTimer.h"
#include "OdometryModel.h"
#include "RemoteControl.h"
#include "WheelSpeedControl.h"

/** Four 200 mm sides and four clockwise quarter-turns; explicit paired PC start. */
class Controller_c {
 public:
  static const unsigned long UPDATE_INTERVAL_MS = 10;
  static const unsigned long TELEMETRY_INTERVAL_MS = 50;

  // Freeze the local model at the values established before this benchmark.
  static constexpr float WHEEL_RADIUS_MM = 16.10f;
  static constexpr float ODOM_WHEEL_SEPARATION_MM = 83.6f;
  static constexpr float ENCODER_COUNTS_PER_REV = 358.3f;

  // The stopping target is separate from the odometry model, as in the turn test.
  static constexpr float FIRST_LEG_MM = 200.0f;
  static constexpr float SECOND_LEG_MM = 200.0f;
  static constexpr float TURN_TARGET_SEPARATION_MM = ODOM_WHEEL_SEPARATION_MM;
  static const uint8_t MOTION_STAGE_COUNT = 8;
  static constexpr float QUARTER_TURN_RAD = 1.57079633f;
  static const int8_t TURN_DIRECTION = -1;  // -1 clockwise; +1 anticlockwise.
  static_assert(TURN_DIRECTION == -1 || TURN_DIRECTION == 1,
                "TURN_DIRECTION must be -1 or +1");

  // Maximum command remains bounded; measured encoder rates close the loop.
  static const int16_t START_PWM = 60;
  static const int16_t CRUISE_PWM = 55;
  static const int16_t MAX_LAGGING_WHEEL_BOOST = 20;
  static const unsigned long START_BOOST_MS = 180;
  static const unsigned long NO_PROGRESS_TIMEOUT_MS = 800;
  static const unsigned long STAGE_TIMEOUT_MS = 30000;
  static const unsigned long STAGE_SETTLE_MS = 250;
  static const int32_t MAX_COUNT_GAP = 160;

  Controller_c();
  void initialise(Robot_c &robot);
  void update(Robot_c &robot, RobotWifiAP_c &server);
  bool canConfigureNetwork() const {
    return state != RUNNING && !stop_retry_pending && left_pwm == 0 && right_pwm == 0;
  }

 private:
  enum TestState : uint8_t {
    WAITING = 0,
    RUNNING = 1,
    COMPLETE = 2,
    ERROR_STOPPED = 3
  };

  TaskTimer_c update_timer;
  TaskTimer_c telemetry_timer;
  OdometryModel_c odometry;
  TestState state;
  const char *reason;
  uint16_t trial_number;
  uint8_t stage;  // 0,2,4,6: sides; 1,3,5,7: turns; 8: ended.
  WheelSpeedControl_c wheel_control;
  unsigned long last_wheel_update_ms = 0;
  int32_t previous_left_progress = 0, previous_right_progress = 0;
  bool left_braking = false, right_braking = false;
  float run_heading = 0, stage_heading_target = 0;
  bool stage_active;
  unsigned long stage_start_ms;
  unsigned long settle_start_ms;
  unsigned long last_left_progress_ms;
  unsigned long last_right_progress_ms;
  int32_t start_left_count;
  int32_t start_right_count;
  int32_t last_left_progress;
  int32_t last_right_progress;
  int32_t target_counts;
  int16_t left_pwm;
  int16_t right_pwm;
  uint8_t post_stop_rows;
  bool stop_retry_pending;
  bool button_armed;
  bool telemetry_client_was_connected;
  unsigned long last_diagnostic_ms = 0;
  int last_diagnostic_button = -1;
  RemoteControl_c remote_control;
  RemoteLine_c remote_line;
  uint32_t remote_generation = 0;
  unsigned long last_hello_ms = 0;

  bool startPath(Robot_c &robot, RobotWifiAP_c &server, unsigned long now);
  bool startStage(Robot_c &robot, RobotWifiAP_c &server, unsigned long now);
  void updateStage(Robot_c &robot, unsigned long now);
  void stopPath(Robot_c &robot, const char *stop_reason, TestState stop_state);
  bool commandMotors(Robot_c &robot, int16_t left, int16_t right);
  int32_t leftProgress(const Robot_c &robot) const;
  int32_t rightProgress(const Robot_c &robot) const;
  void logSnapshot(Robot_c &robot, RobotWifiAP_c &server, unsigned long now);
};

#endif
