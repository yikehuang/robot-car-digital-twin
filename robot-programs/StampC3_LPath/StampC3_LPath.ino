#include <Wire.h>
#include "RobotSharedConfig.h"

#include "RobotWifiAP.h"
#include "NetworkSettings.h"

/** @brief WiFi access-point and TCP server used for optional telemetry. */
RobotWifiAP_c server(ROBOT_AP_SSID, ROBOT_AP_PASSWORD, 80);
NetworkSettings_c networkSettings(server, ROBOT_AP_PASSWORD);

#include "Robot.h"
#include "RobotIMU.h"
#include "Controller.h"


/** @brief Hardware-facing interface to the Pololu robot. */
Robot_c robot;
/** @brief Direct interface to the 3Pi+ accelerometer, gyro, and magnetometer. */
RobotIMU_c imu;
/** @brief Group square-path controller; encoder feedback, no printed-line feedback. */
Controller_c controller;


/** @brief Initialises serial, WiFi, IMU, and the group L-path controller. */
void setup() {

  Serial.begin(115200);
  Serial.println("SQUARE_HEADING_20261112_V3 stages=8 side_mm=200 pc_start_only");
  if (!server.begin()) Serial.println("Warning: WiFi AP start failed");
  else { Serial.print("LPath WiFi ready at "); Serial.println(server.ip()); }

  robot.initialise();
  controller.initialise(robot);
  networkSettings.begin();
//  robot.initialise("team name");


  // Robot_c starts the shared I2C bus before RobotIMU_c uses it. IMU readings
  // come directly from the sensor ICs and do not pass through the middleware.
  if (!imu.initialise() ) {
    Serial.println("Warning: LSM6DS33 IMU was not detected.");
    robot.setLED( 90, 50, 0, 100 ); // orange warning
  }

}


/** @brief Maintains telemetry transport and runs the controller repeatedly. */
void loop() {
  // Accept or maintain the optional Processing telemetry connection. The
  // controller continues to run even when no client is connected.
  server.update();

  
  // Run an iteration of the robot controller code.
  // Develop controller routines in Controller.cpp; edit parameters in Controller.h.
  controller.update(robot, server);
  networkSettings.update(controller.canConfigureNetwork());

}
