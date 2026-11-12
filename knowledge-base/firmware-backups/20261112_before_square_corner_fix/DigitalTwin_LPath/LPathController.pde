/** Independent square-path feedback; never commands real hardware. */
class Controller_c {
  final float FIRST_LEG_MM=200.0f, SECOND_LEG_MM=200.0f;
  final float ASSUMED_RADIUS_MM=16.10f, TURN_TARGET_SEPARATION_MM=83.6f, COUNTS_PER_REV=358.3f;
  final int MOTION_STAGE_COUNT=8, TURN_DIRECTION=-1;
  final int WAITING=0, RUNNING=1, COMPLETE=2, ERROR_STOPPED=3;
  int signal=0, state=WAITING, stage=0, target=0;
  long lastUpdateMs=0, stageStart=0, settleStart=0, lastLeftTime=0, lastRightTime=0, lastWheelTime=0;
  int startLeft=0, startRight=0, lastLeft=0, lastRight=0, previousLeft=0, previousRight=0;
  boolean active=false, started=false, leftBraking=false, rightBraking=false;
  String reason="waiting";
  SquareWheelControl_c wheels=new SquareWheelControl_c();
  void reset() {
    signal=0; state=WAITING; stage=0; active=false; started=false;
    leftBraking=rightBraking=false; wheels.reset(); lastUpdateMs=0; reason="waiting";
  }
  int getSignal() { return signal; }
  void setSignal(int requested) {
    if(requested==0) { reset(); return; }
    if(signal==0) { signal=1; state=RUNNING; started=false; }
  }
  void stop(RobotSimulation_c robot, String why, int result) {
    robot.setMotorPWM(0,0); state=result; reason=why; active=false; stage=MOTION_STAGE_COUNT;
  }
  int leftCount(RobotSimulation_c robot) { return Math.round(robot.odometry.encoders.left); }
  int rightCount(RobotSimulation_c robot) { return Math.round(robot.odometry.encoders.right); }
  void beginStage(RobotSimulation_c robot, long now) {
    stageStart=now; lastLeftTime=lastRightTime=lastWheelTime=now;
    startLeft=leftCount(robot); startRight=rightCount(robot); lastLeft=lastRight=previousLeft=previousRight=0;
    wheels.reset(); leftBraking=rightBraking=false;
    float distance=stage%2==1 ? (float)(Math.PI/2.0)*TURN_TARGET_SEPARATION_MM/2.0f : FIRST_LEG_MM;
    target=Math.round(distance*COUNTS_PER_REV/(2.0f*(float)Math.PI*ASSUMED_RADIUS_MM));
    active=true; reason=stage%2==1 ? "turn" : "straight";
    command(robot,60,60);
  }
  void command(RobotSimulation_c robot, int left, int right) {
    robot.setMotorPWM(left*(stage%2==1 ? -TURN_DIRECTION : 1),right*(stage%2==1 ? TURN_DIRECTION : 1));
  }
  void update(RobotSimulation_c robot) {
    long now=robot.getMillis();
    if(now-lastUpdateMs<10) return;
    lastUpdateMs=now;
    if(signal==0 || state!=RUNNING) { robot.setMotorPWM(0,0); return; }
    if(!started) { started=true; stage=0; beginStage(robot,now); return; }
    if(!active) {
      if(now-settleStart>=250) {
        stage++;
        if(stage>=MOTION_STAGE_COUNT) stop(robot,"complete",COMPLETE);
        else beginStage(robot,now);
      }
      return;
    }
    int left=(leftCount(robot)-startLeft)*(stage%2==1 ? -TURN_DIRECTION : 1);
    int right=(rightCount(robot)-startRight)*(stage%2==1 ? TURN_DIRECTION : 1);
    float dt=(float)(now-lastWheelTime);
    wheels.observe(left-previousLeft,right-previousRight,dt);
    previousLeft=left;previousRight=right;lastWheelTime=now;
    if(left>lastLeft) { lastLeft=left; lastLeftTime=now; }
    if(right>lastRight) { lastRight=right; lastRightTime=now; }
    if(now-stageStart>=30000) { stop(robot,"stage_timeout",ERROR_STOPPED); return; }
    if(left< -3 || right< -3) { stop(robot,"encoder_direction_error",ERROR_STOPPED); return; }
    if(now-stageStart>=600 && (left<3 || right<3)) { stop(robot,"no_start",ERROR_STOPPED); return; }
    if((!leftBraking && left<target && now-lastLeftTime>=800) || (!rightBraking && right<target && now-lastRightTime>=800)) {
      stop(robot,"stalled",ERROR_STOPPED); return;
    }
    if(Math.abs(right-left)>160) { stop(robot,"count_gap_too_large",ERROR_STOPPED); return; }
    if(left>=target-wheels.brakeCounts(wheels.rateLeft)) leftBraking=true;
    if(right>=target-wheels.brakeCounts(wheels.rateRight)) rightBraking=true;
    if(leftBraking && rightBraking) {
      robot.setMotorPWM(0,0); active=false; settleStart=now; reason="settling"; return;
    }
    int[] pwm=wheels.commands(left,right,target,dt,stage%2==1,stage%2==1 && TURN_DIRECTION<0,leftBraking,rightBraking);
    if(now-stageStart<80) { if(!leftBraking && left<3)pwm[0]=60; if(!rightBraking && right<3)pwm[1]=60; }
    command(robot,pwm[0],pwm[1]);
  }
}
