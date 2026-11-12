import processing.core.PImage;
import java.io.*;
import java.util.*;

/** Device-clock/display tests: no sockets, serial ports or real motor commands. */
public class SquareLiveSessionSelfTest {
  static void require(boolean pass,String message){if(!pass)throw new AssertionError(message);}
  static DigitalTwin_LPath.TCPTelemetry_c frame(DigitalTwin_LPath app,int trial,int state,long stamp,float x,float y){
    DigitalTwin_LPath.TCPTelemetry_c s=app.new TCPTelemetry_c();
    String reason=state==1?"straight":state==2?"complete":state==3?"right_stalled":"waiting";
    require(s.parse(trial+",CW,0,"+state+","+reason+","+stamp+",0,0,"+x+","+y+",0,0,0",0),"Frame parse");
    return s;
  }
  static DigitalTwin_LPath.LiveSession_c session(DigitalTwin_LPath app){
    DigitalTwin_LPath.ModelCalibration_c p=app.new ModelCalibration_c();
    return app.new LiveSession_c(app.new RobotSimulation_c(p.wheelRadiusMm,p.wheelSeparationMm,new PImage(4,4),0,0),app.new Controller_c());
  }
  static void assertFrozen(DigitalTwin_LPath.LiveSession_c run){
    float x=run.model.odometry.pose.x,y=run.model.odometry.pose.y;
    long time=run.model.getMillis();
    for(int i=0;i<1000;i++)run.advance();
    require(run.model.getMillis()==time && run.model.odometry.pose.x==x && run.model.odometry.pose.y==y,"Model moved after real stop");
    require(run.model.motors.left.pwm==0 && run.model.motors.right.pwm==0
      && run.model.motors.left.speedMmPerMs==0 && run.model.motors.right.speedMmPerMs==0,"Frozen motor state nonzero");
  }
  public static void main(String[] args)throws Exception{
    DigitalTwin_LPath app=new DigitalTwin_LPath();
    DigitalTwin_LPath.LiveSession_c run=session(app);
    run.accept(frame(app,0,0,1000,0,0));
    run.accept(frame(app,1,1,1100,0,0));
    run.accept(frame(app,1,1,1120,10,0));run.advance();
    require(run.model.getMillis()==20 && run.displayed.x==10,"Device clock or immediate real pose wrong");
    for(int i=0;i<1000;i++)run.advance();
    require(run.model.getMillis()==20,"Model extrapolated without new device data");
    run.accept(frame(app,1,2,1200,50,-20));
    require(run.frozen && !run.running && run.stopElapsedMs==100 && run.model.getMillis()==100,"Completion time alignment");
    require(run.displayed.x==50 && run.displayed.y==-20,"Final robot pose delayed or lost");
    require(Math.abs(run.model.odometry.pose.x-50)>1,"Measured pose copied into independent model");
    assertFrozen(run);
    run.accept(frame(app,1,0,9000,999,999));run.advance();
    require(run.displayed.x==50 && run.model.getMillis()==100,"Post-run idle caused drifting display");
    run.accept(frame(app,2,1,9100,0,0));
    require(run.robotTrace.size()==1 && run.modelTrace.size()==1 && run.running,"New trial did not reset paths");
    run.accept(frame(app,2,3,9200,15,0));
    require(run.frozen && run.stopReason.equals("right_stalled"),"Error stop not synchronized");assertFrozen(run);
    run.clear();run.accept(frame(app,5,1,15000,100,0));run.advance();
    require(run.partialRun && !run.hasRun && run.model.getMillis()==0,"Mid-run reconnect invented model alignment");
    run.clear();float[][] points=run.targetPoints();
    require(Math.abs(points[1][0]-200)<0.01 && Math.abs(points[2][0]-200)<0.01 && Math.abs(points[2][1]+200)<0.01,"Clockwise target geometry");
    require(points.length==5 && Math.hypot(points[4][0],points[4][1])<0.001,"Square target closure");
    run.turnDirection=1;points=run.targetPoints();require(Math.abs(points[2][1]-200)<0.01,"Counterclockwise target geometry");
    System.out.println("PASS: device-clock pacing, immediate odometry display, stop freeze, independent model, idle hold, new-trial paths, error stop, reconnect, target geometry.");
    java.nio.file.Path history=java.nio.file.Files.createTempDirectory("square-history-contract-");
    java.nio.file.Path v2=history.resolve("Square_old.csv"),v3=history.resolve("SquareV3_new.csv");
    try {
      String sample="0,CW,0,0,waiting,1000,0,0,0,0,0,0,0\n1,CW,0,1,straight,1100,0,0,0,0,0,60,60\n1,CW,8,2,complete,1200,0,0,0,0,0,0,0\n";
      java.nio.file.Files.write(v2,sample.getBytes(java.nio.charset.StandardCharsets.UTF_8));
      require(!session(app).restoreLastRun(history.toFile()),"Old V2 history replayed under V3 controller");
      java.nio.file.Files.write(v3,sample.getBytes(java.nio.charset.StandardCharsets.UTF_8));
      DigitalTwin_LPath.LiveSession_c restored=session(app);
      require(restored.restoreLastRun(history.toFile()) && restored.frozen && !restored.armed,"V3 history did not restore safely");
    } finally {
      java.nio.file.Files.deleteIfExists(v2);java.nio.file.Files.deleteIfExists(v3);java.nio.file.Files.delete(history);
    }
    if(args.length>0){
      DigitalTwin_LPath.LiveSession_c replay=session(app);
      Set<Integer> seen=new LinkedHashSet<>();Set<Integer> stopped=new LinkedHashSet<>();
      try(BufferedReader reader=new BufferedReader(new FileReader(args[0]))){
        String line;
        while((line=reader.readLine())!=null){
          DigitalTwin_LPath.TCPTelemetry_c sample=app.new TCPTelemetry_c();
          if(!sample.parse(line,0))continue;
          replay.accept(sample);replay.advance();
          if(sample.robotState==1)seen.add(sample.trial);
          if((sample.robotState==2 || sample.robotState==3) && replay.hasRun){
            assertFrozen(replay);require(replay.displayed.x==sample.x && replay.displayed.y==sample.y,"Recorded final odometry differs");
            require(replay.model.getMillis()<=replay.stopElapsedMs && replay.stopElapsedMs-replay.model.getMillis()<10,"Recorded run time alignment exceeds one tick");
            if(stopped.add(sample.trial))System.out.println("Recorded trial "+sample.trial+": robot="+replay.stopElapsedMs+" ms, model="+replay.model.getMillis()+" ms, stopped="+sample.reason);
          }
        }
      }
      require(seen.size()>0 && stopped.containsAll(seen),"Recorded moving trials not all covered by stop assertions");
      DigitalTwin_LPath.LiveSession_c restored=session(app);
      require(restored.restoreLastRun(new File(args[0]).getParentFile()),"Historical trajectory restore failed");
      require(restored.hasRun && restored.frozen && !restored.armed,"Restored history armed hardware start");assertFrozen(restored);
      System.out.println("PASS: recorded-data replay for "+stopped.size()+" stopped trials; history restore is read-only and frozen.");
    }
  }
}
