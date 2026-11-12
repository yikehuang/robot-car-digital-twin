/** Mirrors firmware WheelSpeedControl.h; rates in counts/ms. */
class SquareWheelControl_c {
  float rateLeft=0,rateRight=0,integralLeft=0,integralRight=0;
  void reset(){rateLeft=rateRight=integralLeft=integralRight=0;}
  float limit(float x,float lo,float hi){return Math.max(lo,Math.min(x,hi));}
  void observe(int dl,int dr,float dt){
    float alpha=dt/(40.0f+dt);
    rateLeft+=alpha*(dl/dt-rateLeft);rateRight+=alpha*(dr/dt-rateRight);
  }
  float brakeCounts(float rate){return Math.max(2.0f,rate*35.5f);}
  float[] wheel(float target,float rate,float gain,float dt,float integral){
    float error=target-rate,candidate=limit(integral+error*dt,-250.0f,250.0f);
    float raw=target/gain+22.0f*error+0.035f*candidate;
    if((raw>=40 && raw<=85) || (raw>85 && error<0) || (raw<40 && error>0))integral=candidate;
    return new float[]{Math.round(limit(target/gain+22.0f*error+0.035f*integral,40,85)),integral};
  }
  int[] commands(int left,int right,int target,float dt,boolean turning,boolean rightReverse,boolean brakeLeft,boolean brakeRight){
    float remaining=Math.max(0.0f,(float)(target-Math.max(left,right)));
    float base=limit(remaining*0.008f,0.24f,turning?0.46f:0.56f);
    float correction=limit((right-left)*0.008f,-0.16f,0.16f);
    float[] l=wheel(limit(base+correction,0.12f,0.75f),rateLeft,0.01022189486f,dt,integralLeft);
    float[] r=wheel(limit(base-correction,0.12f,0.75f),rateRight,rightReverse?0.01135989616f:0.01176599982f,dt,integralRight);
    if(!brakeLeft)integralLeft=l[1];if(!brakeRight)integralRight=r[1];
    return new int[]{brakeLeft?0:(int)l[0],brakeRight?0:(int)r[0]};
  }
}
