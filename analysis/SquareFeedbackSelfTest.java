import processing.core.PImage;
import java.util.*;

/** Production square controller under encoder/model scenarios. No hardware I/O. */
public class SquareFeedbackSelfTest {
  static void require(boolean value,String message){if(!value)throw new AssertionError(message);}
  static class Plant extends DigitalTwin_LPath.RobotSimulation_c {
    final float leftFactor,rightFactor;
    Plant(DigitalTwin_LPath app,float l,float r){app.super(16.1f,83.6f,new PImage(4,4),0,0);leftFactor=l;rightFactor=r;}
    @Override public void updatePhysics(int dt){
      motors.update(odometry.mmPerEncoderCount,dt);
      odometry.update(motors.left.stepDistanceMm*leftFactor,motors.right.stepDistanceMm*rightFactor,wheelSeparationMm);
    }
  }
  public static void main(String[] args){
    DigitalTwin_LPath app=new DigitalTwin_LPath();
    for(float factor:new float[]{1f,0.85f,1.15f}){
      Plant robot=new Plant(app,factor,1);
      DigitalTwin_LPath.Controller_c controller=app.new Controller_c();
      robot.resetForRun(0,0,0,0,0);controller.setSignal(1);
      boolean[] seen=new boolean[8];int turns=0;float maxStraightGap=0;
      for(int i=0;i<20000 && controller.state==controller.RUNNING;i++){
        robot.advanceTime(10);controller.update(robot);
        if(controller.stage<8){seen[controller.stage]=true;
          if(controller.stage%2==0 && controller.active){
            maxStraightGap=Math.max(maxStraightGap,Math.abs((controller.leftCount(robot)-controller.startLeft)-(controller.rightCount(robot)-controller.startRight)));
          }
        }
        require(Math.abs(robot.motors.left.pwm)<=85 && Math.abs(robot.motors.right.pwm)<=85,"PWM limit");
        robot.updatePhysics(10);
      }
      for(boolean stage:seen)require(stage,"Missing square side/turn");
      require(controller.state==controller.COMPLETE && controller.stage==8,"Square failed: "+controller.reason);
      require(robot.motors.left.pwm==0 && robot.motors.right.pwm==0,"Final stop missing");
      float position=(float)Math.hypot(robot.odometry.pose.x,robot.odometry.pose.y);
      double heading=Math.toDegrees(Math.atan2(Math.sin(robot.odometry.pose.theta),Math.cos(robot.odometry.pose.theta)));
      require(position<15 && Math.abs(heading)<10,"Synthetic closure error too large");
      require(maxStraightGap<15,"Feedback did not balance straight wheel travel");
      System.out.printf(Locale.ROOT,"Synthetic left gain factor %.2f: closure %.3f mm, heading %.3f deg, max straight wheel gap %.1f counts, duration %d ms%n",factor,position,heading,maxStraightGap,robot.getMillis());
    }
    Plant stalled=new Plant(app,0,1);DigitalTwin_LPath.Controller_c c=app.new Controller_c();
    stalled.resetForRun(0,0,0,0,0);c.setSignal(1);
    for(int i=0;i<200 && c.state==c.RUNNING;i++){stalled.advanceTime(10);c.update(stalled);stalled.updatePhysics(10);}
    require(c.state==c.ERROR_STOPPED && stalled.motors.left.pwm==0 && stalled.motors.right.pwm==0,"Stalled wheel not stopped");
    // A heading disturbance after corner two must not become the baseline for
    // all remaining corners. This is an explicit synthetic intervention.
    Plant disturbed=new Plant(app,1,1);DigitalTwin_LPath.Controller_c d=app.new Controller_c();
    disturbed.resetForRun(0,0,0,0,0);d.setSignal(1);boolean injected=false;
    for(int i=0;i<5000 && d.state==d.RUNNING;i++){
      disturbed.advanceTime(10);d.update(disturbed);
      if(d.stage==3 && !d.active && !injected){disturbed.odometry.pose.theta+=(float)Math.toRadians(5);injected=true;}
      if(d.started && d.stage<8){
        double desired=-Math.PI/2*(d.stage%2==0?d.stage/2:(d.stage+1)/2);
        require(Math.abs(d.stageHeadingTarget-desired)<1e-5,"Corner target inherited a previous error");
      }
      disturbed.updatePhysics(10);
    }
    double disturbedHeading=Math.toDegrees(Math.atan2(Math.sin(disturbed.odometry.pose.theta),Math.cos(disturbed.odometry.pose.theta)));
    require(injected && d.state==d.COMPLETE && Math.abs(disturbedHeading)<2,"Run-referenced heading correction failed");
    System.out.printf(Locale.ROOT,"Synthetic +5 degree disturbance after corner 2: closure %.3f mm, final heading %.3f deg%n",Math.hypot(disturbed.odometry.pose.x,disturbed.odometry.pose.y),disturbedHeading);
    DigitalTwin_LPath.LiveSession_c live=app.new LiveSession_c(stalled,app.new Controller_c());
    float[][] square=live.targetPoints();require(square.length==5,"Target not square");
    require(Math.hypot(square[4][0],square[4][1])<0.001,"Target not closed");
    require(square[2][1]<-199,"Square turn direction");
    System.out.println("PASS: 8 stages, four sides/four turns, bounded PWM, final stop, asymmetric synthetic response, stalled wheel stop and square target. Synthetic results are not physical validation.");
  }
}
