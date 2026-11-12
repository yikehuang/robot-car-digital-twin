#ifndef WHEEL_SPEED_CONTROL_H
#define WHEEL_SPEED_CONTROL_H

#include <math.h>
#include <stdint.h>

// Counts/ms and PWM units. Gains are inherited from the healthy CW encoder fit;
// feedback, not the fitted gains alone, compensates a changed wheel response.
// Identical arithmetic is used in the desktop SquareWheelControl_c.
class WheelSpeedControl_c {
 public:
  float rate_left = 0, rate_right = 0;
  float integral_left = 0, integral_right = 0;
  void reset() { rate_left=rate_right=integral_left=integral_right=0; }
  static float limit(float x,float lo,float hi) { return x<lo?lo:x>hi?hi:x; }
  void observe(int32_t dl,int32_t dr,float dt) {
    const float alpha=dt/(40.0f+dt);
    rate_left+=alpha*(dl/dt-rate_left);
    rate_right+=alpha*(dr/dt-rate_right);
  }
  static float coastMs() { return 10.47762097f; }
  static float brakeCounts(float rate) { return fmaxf(1.0f,rate*coastMs()); }
  void commands(int32_t left,int32_t right,int32_t target,float dt,bool turning,
                bool leftReverse,bool rightReverse,bool brakeLeft,bool brakeRight,float headingError,
                int16_t &l,int16_t &r) {
    const float remaining=fmaxf(0.0f,(float)(target-(left>right?left:right)));
    const float base=limit(remaining*0.008f,0.24f,turning?0.46f:0.56f);
    // Straight sections hold a run-referenced heading rather than forcing equal
    // counts relative to an already misaligned segment start.
    const float correction=limit(turning?(right-left)*0.008f:headingError*2.4f,-0.16f,0.16f);
    const float targetLeft=limit(base+correction,0.12f,0.75f);
    const float targetRight=limit(base-correction,0.12f,0.75f);
    const float gl=0.008676238904f; // left reverse remains an unmeasured assumption
    const float gr=rightReverse?0.01068616236f:0.01119120295f;
    l=brakeLeft?0:wheel(targetLeft,rate_left,gl,dt,integral_left);
    r=brakeRight?0:wheel(targetRight,rate_right,gr,dt,integral_right);
  }
 private:
  static int16_t wheel(float target,float rate,float gain,float dt,float &integral) {
    const float error=target-rate;
    const float candidate=limit(integral+error*dt,-250.0f,250.0f);
    const float raw=target/gain+22.0f*error+0.035f*candidate;
    // Conditional integration prevents winding further into PWM saturation.
    if ((raw>=40 && raw<=85) || (raw>85 && error<0) || (raw<40 && error>0)) integral=candidate;
    // A conservative moving-PWM floor avoids requesting very weak drive near
    // the endpoint; measured rate is still used to predict coasting distance.
    return (int16_t)lroundf(limit(target/gain+22.0f*error+0.035f*integral,40,85));
  }
};
#endif
