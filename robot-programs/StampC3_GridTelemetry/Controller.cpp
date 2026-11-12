#include "Controller.h"

#include <math.h>
#include <Preferences.h>
#include <esp_system.h>

static const char *LOG_HEADER =
    "trial,direction,stage,state,reason,time_ms,left_count,right_count,"
    "x_mm,y_mm,theta_rad,left_pwm,right_pwm\n";

void Controller_c::initialise(Robot_c &robot) {
  stop_retry_pending = !robot.setMotorPWM(0, 0);
  if (stop_retry_pending) { state = ERROR_STOPPED; reason = "initial_stop_failed"; }
  Preferences preferences;
  if (preferences.begin("lpathnet", true)) {
    String key = preferences.getString("ctrlkey", "");
    if (remoteControlSelfTest()) remote_control.configureKey(key.c_str());
    preferences.end();
  }
  Serial.printf("CONTROL_SELFTEST %s; PC_START_ONLY\n", remoteControlSelfTest() ? "PASS" : "FAIL");
}

const unsigned long Controller_c::UPDATE_INTERVAL_MS;
const unsigned long Controller_c::TELEMETRY_INTERVAL_MS;
constexpr float Controller_c::WHEEL_RADIUS_MM;
constexpr float Controller_c::ODOM_WHEEL_SEPARATION_MM;
constexpr float Controller_c::ENCODER_COUNTS_PER_REV;
constexpr float Controller_c::FIRST_LEG_MM;
constexpr float Controller_c::SECOND_LEG_MM;
constexpr float Controller_c::TURN_TARGET_SEPARATION_MM;
constexpr float Controller_c::QUARTER_TURN_RAD;
const int8_t Controller_c::TURN_DIRECTION;
const int16_t Controller_c::START_PWM;
const int16_t Controller_c::CRUISE_PWM;
const int16_t Controller_c::MAX_LAGGING_WHEEL_BOOST;
const unsigned long Controller_c::START_BOOST_MS;
const unsigned long Controller_c::NO_PROGRESS_TIMEOUT_MS;
const unsigned long Controller_c::STAGE_TIMEOUT_MS;
const unsigned long Controller_c::STAGE_SETTLE_MS;
const int32_t Controller_c::MAX_COUNT_GAP;

Controller_c::Controller_c()
    : update_timer(UPDATE_INTERVAL_MS),
      telemetry_timer(TELEMETRY_INTERVAL_MS),
      odometry(WHEEL_RADIUS_MM, ODOM_WHEEL_SEPARATION_MM,
               ENCODER_COUNTS_PER_REV),
      state(WAITING),
      reason("waiting"),
      trial_number(0),
      stage(0),
      stage_active(false),
      stage_start_ms(0),
      settle_start_ms(0),
      last_left_progress_ms(0),
      last_right_progress_ms(0),
      start_left_count(0),
      start_right_count(0),
      last_left_progress(0),
      last_right_progress(0),
      target_counts(0),
      left_pwm(0),
      right_pwm(0),
      post_stop_rows(0),
      stop_retry_pending(false),
      button_armed(false),
      telemetry_client_was_connected(false) {}

void Controller_c::update(Robot_c &robot, RobotWifiAP_c &server) {
  const unsigned long now = robot.getMillis();
  if (!update_timer.isReady(now)) return;
  update_timer.resetTimer(now);
  const bool connected = server.clientConnected();
  const bool new_session = connected && remote_generation != server.clientGeneration();
  if (state == RUNNING && (!connected || new_session)) {
    stopPath(robot, "control_disconnected", ERROR_STOPPED);
  }
  if (new_session) {
    remote_generation = server.clientGeneration();
    char nonce[17];
    snprintf(nonce, sizeof(nonce), "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
    remote_control.beginSession(nonce);
    remote_line.reset(); last_hello_ms = now - 1000;
    server.printf("%s", LOG_HEADER);
  }
  if (connected && now - last_hello_ms >= 1000) {
    if (remote_control.ready()) server.printf("CTRL READY %s\n", remote_control.session());
    else if (remote_control.configured()) server.printf("CTRL HELLO %s SQUARE_REMOTE_V3\n", remote_control.session());
    else server.printf("CTRL LOCKED key_not_configured\n");
    last_hello_ms = now;
  }
  telemetry_client_was_connected = connected;
  bool remote_start = false;
  bool remote_stop = false;
  // Bound command processing to protect the 10 ms controller loop.
  for (unsigned budget = 0; connected && budget < 256 && server.available(); ++budget) {
    int byte = server.read();
    if (byte < 0 || !remote_line.push(static_cast<char>(byte))) continue;
    RemoteControl_c::Action action = remote_control.consume(remote_line.line(), now, state == RUNNING);
    if (action == RemoteControl_c::Authenticated) server.printf("CTRL READY %s\n", remote_control.session());
    else if (action == RemoteControl_c::Start) remote_start = true;
    else if (action == RemoteControl_c::Stop) remote_stop = true;
    else if (action == RemoteControl_c::Rejected && strncmp(remote_line.line(), "AUTH ", 5) == 0)
      server.printf("CTRL DENIED %s\n", remote_control.session());
  }
  if (remote_stop) {
    stopPath(robot, "remote_stop", ERROR_STOPPED);
    remote_start = false; // STOP wins over START received in the same iteration.
    server.printf("CTRL STOPPED %s\n", remote_control.session());
  } else if (state == RUNNING && !remote_control.fresh(now)) {
    stopPath(robot, "control_timeout", ERROR_STOPPED);
  }

  // Release between presses. A second press during a run cancels the path.
  const bool button_down = digitalRead(3) == LOW;
  if (!button_down) button_armed = true;
  bool button_event = false;
  if (button_down && button_armed && robot.isButtonPressed()) {
    button_armed = false;
    button_event = true;
  }

  // Never permit a new run until a failed zero-PWM command succeeds.
  if (stop_retry_pending && robot.setMotorPWM(0, 0)) {
    stop_retry_pending = false;
    left_pwm = 0;
    right_pwm = 0;
  }

  const bool encoder_ok = robot.getEncoders();
  // USB-only diagnosis stays independent of encoder success and never sends
  // a motion request. Avoid a blocking UART write in the control loop.
  if (Serial && Serial.availableForWrite() >= 96 &&
      ((state != RUNNING && now - last_diagnostic_ms >= 1000) ||
       last_diagnostic_button != (button_down ? 0 : 1) || button_event)) {
    Serial.printf("DIAG gpio3=%d armed=%d event=%d enc_ok=%d state=%u retry=%d\n",
                  button_down ? 0 : 1, button_armed, button_event, encoder_ok,
                  static_cast<unsigned>(state), stop_retry_pending);
    last_diagnostic_ms = now;
    last_diagnostic_button = button_down ? 0 : 1;
  }
  if (encoder_ok && trial_number > 0) {
    odometry.update(robot.getLeftEncoderCount(), robot.getRightEncoderCount());
  }

  if (state == RUNNING) {
    if (button_event) {
      stopPath(robot, "user_cancelled", ERROR_STOPPED);
    } else if (!encoder_ok) {
      stopPath(robot, "encoder_read_failed", ERROR_STOPPED);
    } else if (!stage_active) {
      if (now - settle_start_ms >= STAGE_SETTLE_MS) {
        ++stage;
        if (stage >= MOTION_STAGE_COUNT) {
          stopPath(robot, "complete", COMPLETE);
        } else if (!startStage(robot, server, now)) {
          stopPath(robot, "stage_start_failed", ERROR_STOPPED);
        }
      }
    } else {
      updateStage(robot, now);
    }
  } else if (remote_start && !remote_stop && server.clientConnected() &&
             remote_control.ready() && remote_control.fresh(now) && encoder_ok && !stop_retry_pending &&
             post_stop_rows == 0) {
    if (startPath(robot, server, now)) server.printf("CTRL RUNNING %s %u\n", remote_control.session(), trial_number);
  } else if (remote_start) {
    server.printf("CTRL REJECT %s not_ready\n", remote_control.session());
  }

  grid_telemetry.update(robot,server,now,encoder_ok,trial_number,stage,
      static_cast<unsigned>(state),left_pwm,right_pwm);
  if (encoder_ok && telemetry_timer.isReady(now)) {
    telemetry_timer.resetTimer(now);
    logSnapshot(robot, server, now);
    if (state != RUNNING && post_stop_rows > 0) {
      if (--post_stop_rows == 0 && !stop_retry_pending) {
        state = WAITING;
        reason = "waiting";
      }
    }
  }
}

bool Controller_c::startPath(
    Robot_c &robot, RobotWifiAP_c &server, unsigned long now) {
  // A direct PWM command also cancels any lingering middleware motion helper.
  if (!robot.setMotorPWM(0, 0)) {
    state = ERROR_STOPPED;
    reason = "initial_stop_failed";
    stop_retry_pending = true;
    post_stop_rows = 20;
    return false;
  }
  left_pwm = 0;
  right_pwm = 0;

  ++trial_number;
  stage = 0;
  state = RUNNING;
  reason = "straight";
  post_stop_rows = 0;
  odometry.reset();
  odometry.update(robot.getLeftEncoderCount(), robot.getRightEncoderCount());
  run_heading = odometry.pose.theta;

  if (Serial) Serial.print(LOG_HEADER);
  server.printf("%s", LOG_HEADER);

  if (!server.clientConnected()) {
    stopPath(robot, "control_disconnected", ERROR_STOPPED);
    return false;
  }

  if (!startStage(robot, server, now)) {
    stopPath(robot, "stage_start_failed", ERROR_STOPPED);
    return false;
  }
  return true;
}

bool Controller_c::startStage(
    Robot_c &robot, RobotWifiAP_c &server, unsigned long now) {
  const bool straight = (stage % 2) == 0;
  stage_heading_target = run_heading + TURN_DIRECTION * QUARTER_TURN_RAD *
      (straight ? stage/2 : (stage+1)/2);
  stage_start_ms = now;
  last_left_progress_ms = now;
  last_right_progress_ms = now;
  start_left_count = robot.getLeftEncoderCount();
  start_right_count = robot.getRightEncoderCount();
  last_left_progress = 0;
  last_right_progress = 0;
  previous_left_progress = previous_right_progress = 0;
  last_wheel_update_ms = now;
  left_braking = right_braking = false;
  wheel_control.reset();
  target_counts = straight
      ? static_cast<int32_t>(lroundf(
            FIRST_LEG_MM * ENCODER_COUNTS_PER_REV /
            (2.0f * PI * WHEEL_RADIUS_MM)))
      : static_cast<int32_t>(lroundf(
            (fmaxf(0.0f, TURN_DIRECTION*(stage_heading_target-odometry.pose.theta)) * TURN_TARGET_SEPARATION_MM * 0.5f) *
            ENCODER_COUNTS_PER_REV / (2.0f * PI * WHEEL_RADIUS_MM)));
  reason = straight ? "straight" : "turn";
  stage_active = true;

  // Preserve a stationary count/pose sample for every segment boundary.
  logSnapshot(robot, server, now);
  const int8_t left_sign = straight ? 1 : -TURN_DIRECTION;
  const int8_t right_sign = straight ? 1 : TURN_DIRECTION;
  return commandMotors(robot, left_sign * START_PWM,
                       right_sign * START_PWM);
}

void Controller_c::updateStage(Robot_c &robot, unsigned long now) {
  const int32_t left = leftProgress(robot);
  const int32_t right = rightProgress(robot);
  const float dt=(float)(now-last_wheel_update_ms);
  if (dt > 0) wheel_control.observe(left-previous_left_progress,right-previous_right_progress,dt);
  last_wheel_update_ms=now; previous_left_progress=left; previous_right_progress=right;
  if (left > last_left_progress) {
    last_left_progress = left;
    last_left_progress_ms = now;
  }
  if (right > last_right_progress) {
    last_right_progress = right;
    last_right_progress_ms = now;
  }

  if (now - stage_start_ms >= STAGE_TIMEOUT_MS) {
    stopPath(robot, "stage_timeout", ERROR_STOPPED);
    return;
  }
  if (left < -3 || right < -3) {
    stopPath(robot, "encoder_direction_error", ERROR_STOPPED);
    return;
  }
  if (now - stage_start_ms >= 600 && (left < 3 || right < 3)) {
    stopPath(robot, left < 3 ? "left_no_start" : "right_no_start",
               ERROR_STOPPED);
    return;
  }
  if ((!left_braking && left < target_counts &&
       now - last_left_progress_ms >= NO_PROGRESS_TIMEOUT_MS) ||
      (!right_braking && right < target_counts &&
       now - last_right_progress_ms >= NO_PROGRESS_TIMEOUT_MS)) {
    stopPath(robot, left < target_counts &&
                       now - last_left_progress_ms >= NO_PROGRESS_TIMEOUT_MS
                          ? "left_stalled" : "right_stalled",
               ERROR_STOPPED);
    return;
  }

  const int32_t gap = right - left;
  if (gap > MAX_COUNT_GAP || gap < -MAX_COUNT_GAP) {
    stopPath(robot, "count_gap_too_large", ERROR_STOPPED);
    return;
  }
  const bool straight = (stage % 2) == 0;
  const float mm_per_count = 2.0f*PI*WHEEL_RADIUS_MM/ENCODER_COUNTS_PER_REV;
  const float rate_sum = fmaxf(0.0f,wheel_control.rate_left+wheel_control.rate_right);
  // Use one shared stop boundary: centre distance on straights, absolute
  // run-referenced heading on turns. Previous corner errors cannot accumulate
  // merely because the next stage resets its local count baseline.
  const bool reached = straight
      ? target_counts-(left+right)*0.5f <= wheel_control.brakeCounts(rate_sum*0.5f)
      : TURN_DIRECTION*(stage_heading_target-odometry.pose.theta) <=
          rate_sum*mm_per_count/ODOM_WHEEL_SEPARATION_MM*wheel_control.coastMs();
  if (reached) left_braking=right_braking=true;
  if (left_braking && right_braking) {
    if (!commandMotors(robot, 0, 0)) {
      stopPath(robot, "stage_stop_failed", ERROR_STOPPED);
    } else {
      stage_active = false;
      settle_start_ms = now;
      reason = "settling";
    }
    return;
  }

  const int8_t left_sign = straight ? 1 : -TURN_DIRECTION;
  const int8_t right_sign = straight ? 1 : TURN_DIRECTION;
  int16_t left_magnitude=0, right_magnitude=0;
  wheel_control.commands(left,right,target_counts,dt>0?dt:10.0f,!straight,
      left_sign<0,right_sign<0,left_braking,right_braking,odometry.pose.theta-stage_heading_target,left_magnitude,right_magnitude);
  // Break static friction only at the start; rate feedback takes over promptly.
  if (now-stage_start_ms < 80) {
    if(!left_braking && left<3) left_magnitude=START_PWM;
    if(!right_braking && right<3) right_magnitude=START_PWM;
  }
  if (!commandMotors(robot, left_sign * left_magnitude,
                     right_sign * right_magnitude)) {
    stopPath(robot, "motor_command_failed", ERROR_STOPPED);
  }
}

void Controller_c::stopPath(
    Robot_c &robot, const char *stop_reason, TestState stop_state) {
  const bool stopped = robot.setMotorPWM(0, 0);
  state = stopped ? stop_state : ERROR_STOPPED;
  reason = stopped ? stop_reason : "motor_stop_failed";
  stop_retry_pending = !stopped;
  stage_active = false;
  stage = MOTION_STAGE_COUNT;
  if (stopped) {
    left_pwm = 0;
    right_pwm = 0;
  }
  post_stop_rows = 20;
}

bool Controller_c::commandMotors(
    Robot_c &robot, int16_t left, int16_t right) {
  if (left == left_pwm && right == right_pwm) return true;
  if (!robot.setMotorPWM(left, right)) return false;
  left_pwm = left;
  right_pwm = right;
  return true;
}

int32_t Controller_c::leftProgress(const Robot_c &robot) const {
  const int8_t sign = (stage % 2) == 0 ? 1 : -TURN_DIRECTION;
  return sign * (robot.encoders.count[0] - start_left_count);
}

int32_t Controller_c::rightProgress(const Robot_c &robot) const {
  const int8_t sign = (stage % 2) == 0 ? 1 : TURN_DIRECTION;
  return sign * (robot.encoders.count[1] - start_right_count);
}

void Controller_c::logSnapshot(
    Robot_c &robot, RobotWifiAP_c &server, unsigned long now) {
  const char *direction = TURN_DIRECTION < 0 ? "CW" : "CCW";
  const char *format =
      "%u,%s,%u,%u,%s,%lu,%ld,%ld,%.3f,%.3f,%.5f,%d,%d\n";
  const long raw_left = (long)robot.getLeftEncoderCount();
  const long raw_right = (long)robot.getRightEncoderCount();
  if (Serial) {
    Serial.printf(format, trial_number, direction, stage,
                  static_cast<unsigned>(state), reason, now,
                  raw_left, raw_right, odometry.pose.x, odometry.pose.y,
                  odometry.pose.theta, left_pwm, right_pwm);
  }
  server.printf(format, trial_number, direction, stage,
                static_cast<unsigned>(state), reason, now,
                raw_left, raw_right, odometry.pose.x, odometry.pose.y,
                odometry.pose.theta, left_pwm, right_pwm);
}
