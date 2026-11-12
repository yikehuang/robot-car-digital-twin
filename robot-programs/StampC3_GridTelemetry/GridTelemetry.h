#ifndef GRID_TELEMETRY_H
#define GRID_TELEMETRY_H
#include "Robot.h"
#include "RobotWifiAP.h"

// Extra read-only observations. No motor commands or estimated map poses.
class GridTelemetry_c {
 public:
  void update(Robot_c &robot,RobotWifiAP_c &server,unsigned long now,bool enc_ok,
              unsigned trial,unsigned stage,unsigned state,int left_pwm,int right_pwm) {
    if(now-last_ms<20) return;
    last_ms=now;
    const unsigned long begin_us=micros();
    const bool sensor_ok=robot.getSurfaceSensors();
    const unsigned long read_us=micros()-begin_us;
    const bool changed=sensor_ok && (!seen_stamp || robot.surface.timestamp_us!=last_stamp);
    if(sensor_ok){last_stamp=robot.surface.timestamp_us;seen_stamp=true;}
    char values[40];
    if(sensor_ok)snprintf(values,sizeof(values),"%u,%u,%u,%u,%u",
      robot.surface.reading[0],robot.surface.reading[1],robot.surface.reading[2],robot.surface.reading[3],robot.surface.reading[4]);
    else strcpy(values,"NA,NA,NA,NA,NA");
    char frame[224];
    const int n=snprintf(frame,sizeof(frame),
      "GRID1,%lu,%lu,%u,%ld,%ld,%u,%lu,%u,%s,%u,%u,%u,%d,%d,%lu\n",
      (unsigned long)++sequence,(unsigned long)robot.getMillis(),enc_ok?1:0,
      (long)robot.getLeftEncoderCount(),(long)robot.getRightEncoderCount(),sensor_ok?1:0,
      sensor_ok?(unsigned long)robot.surface.timestamp_us:0UL,changed?1:0,values,
      trial,stage,state,left_pwm,right_pwm,read_us);
    if(n<=0 || n>=(int)sizeof(frame))return;
    // Drop the entire USB observation if the transmit buffer is busy; sequence
    // gaps expose losses. Never block the controller or splice partial lines.
    if(Serial && Serial.availableForWrite()>=n)Serial.write((const uint8_t*)frame,n);
    server.printf("%s",frame);
  }
 private:
  unsigned long last_ms=0;
  uint32_t sequence=0,last_stamp=0;
  bool seen_stamp=false;
};
#endif
