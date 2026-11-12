/** One point in a displayed run; positions are mm, heading is radians. */
class TracePoint_c {
  final float x,y,theta;
  final long timeMs;
  TracePoint_c(float xIn,float yIn,float heading,long stamp) {
    x=xIn; y=yIn; theta=heading; timeMs=stamp;
  }
}

/**
 * Device-clock comparison. Never sends a hardware command and never copies a
 * measured pose into the independent model after initial run alignment.
 */
class LiveSession_c {
  final RobotSimulation_c model;
  final Controller_c controller;
  final int STEP_MS=10, MAX_CATCHUP_STEPS=1000, MAX_TRACE_POINTS=6000;
  TCPTelemetry_c latest=new TCPTelemetry_c();
  TCPTelemetry_c displayed=new TCPTelemetry_c();
  ArrayList<TracePoint_c> robotTrace=new ArrayList<TracePoint_c>();
  ArrayList<TracePoint_c> modelTrace=new ArrayList<TracePoint_c>();
  boolean armed=false, running=false, frozen=false, hasRun=false;
  boolean partialRun=false, timingGap=false;
  int trial=-1;
  long previousStamp=-1, startStamp=-1, targetElapsedMs=0, stopElapsedMs=-1;
  float startX=0,startY=0,startTheta=0;
  int turnDirection=-1;
  String stopReason="";

  LiveSession_c(RobotSimulation_c modelIn,Controller_c controllerIn) {
    model=modelIn; controller=controllerIn;
  }
  void freezeModel() {
    controller.setSignal(0);
    model.freezeMotion();
    running=false; frozen=true;
  }
  void pause() {
    if(running && stopReason.length()==0) stopReason="data paused";
    freezeModel(); armed=false;
  }
  void clear() {
    freezeModel();
    armed=false; frozen=false; hasRun=false; partialRun=false; timingGap=false;
    trial=-1; previousStamp=-1; startStamp=-1; targetElapsedMs=0; stopElapsedMs=-1;
    startX=0;startY=0;startTheta=0;turnDirection=-1;stopReason="";
    latest=new TCPTelemetry_c(); displayed=new TCPTelemetry_c();
    robotTrace.clear(); modelTrace.clear();
    model.simulationMillis=0; model.resetForRun(0,0,0,0,0);
  }
  void append(ArrayList<TracePoint_c> trace,float x,float y,float theta,long time,boolean force) {
    if (!force && trace.size()>0) {
      TracePoint_c last=trace.get(trace.size()-1);
      float dx=x-last.x,dy=y-last.y;
      if (dx*dx+dy*dy<0.25 && time-last.timeMs<100) return;
    }
    if (trace.size()>=MAX_TRACE_POINTS) trace.remove(0);
    trace.add(new TracePoint_c(x,y,theta,time));
  }
  void appendModel(boolean force) {
    append(modelTrace,model.odometry.pose.x,model.odometry.pose.y,
      model.odometry.pose.theta,model.getMillis(),force);
  }
  void start(TCPTelemetry_c sample) {
    hasRun=true; running=true; frozen=false; partialRun=false;
    startStamp=sample.timestampMs; targetElapsedMs=0;
    startX=sample.x;startY=sample.y;startTheta=sample.theta;
    turnDirection=sample.turnDirection;
    model.simulationMillis=0;
    model.resetForRun(sample.x,sample.y,sample.theta,sample.encoderLeft,sample.encoderRight);
    controller.reset(); controller.setSignal(1);
    appendModel(true);
  }
  void accept(TCPTelemetry_c sample) {
    boolean wasArmed=armed;
    boolean reboot=previousStamp>=0 && sample.timestampMs<previousStamp;
    boolean newTrial=sample.trial>=0 && trial>=0 && sample.trial!=trial;
    if (reboot || newTrial) {
      clear();
      armed=wasArmed && !reboot;
    }
    latest=sample.copy(); previousStamp=sample.timestampMs; trial=sample.trial;
    boolean sourceRunning=sample.robotState==1 || (sample.robotState<0 && sample.signal==1);
    if (sourceRunning) {
      if (!hasRun && armed) start(sample);
      else if (!hasRun) partialRun=true; // Connecting mid-run must not invent its missing start.
      displayed=sample.copy();
      append(robotTrace,sample.x,sample.y,sample.theta,sample.timestampMs,false);
      if (running && !frozen) targetElapsedMs=Math.max(0,sample.timestampMs-startStamp);
    } else {
      if (hasRun && stopElapsedMs<0 && startStamp>=0) {
        targetElapsedMs=Math.max(0,sample.timestampMs-startStamp);
        if(!frozen) advance(); // Never animate beyond the measured stop boundary.
        stopElapsedMs=targetElapsedMs; stopReason=sample.reason;
        displayed=sample.copy();
        append(robotTrace,sample.x,sample.y,sample.theta,sample.timestampMs,true);
        appendModel(true); freezeModel();
      } else if (!hasRun || sample.robotState==2 || sample.robotState==3) {
        displayed=sample.copy();
        if (hasRun) append(robotTrace,sample.x,sample.y,sample.theta,sample.timestampMs,false);
      }
      armed=sample.robotState==0 || (sample.robotState<0 && sample.signal==0);
    }
  }
  void advance() {
    if (!running || frozen) return;
    int steps=0;
    while (model.getMillis()+STEP_MS<=targetElapsedMs && steps<MAX_CATCHUP_STEPS) {
      model.advanceTime(STEP_MS);
      controller.update(model);
      model.updatePhysics(STEP_MS);
      appendModel(false); steps++;
    }
    timingGap=targetElapsedMs-model.getMillis()>=STEP_MS;
  }
  float[][] targetPoints() {
    float[][] points=new float[5][2]; points[0][0]=startX;points[0][1]=startY;
    for(int i=0;i<4;i++) {
      float heading=startTheta+i*turnDirection*(float)(Math.PI/2);
      points[i+1][0]=points[i][0]+controller.FIRST_LEG_MM*(float)Math.cos(heading);
      points[i+1][1]=points[i][1]+controller.FIRST_LEG_MM*(float)Math.sin(heading);
    }
    return points;
  }

  /** Restore the latest stopped attempt, including failures, without hardware commands. */
  boolean restoreLastRun(java.io.File directory) {
    java.io.File[] files=directory.listFiles(new java.io.FilenameFilter(){
      public boolean accept(java.io.File parent,String name){return name.startsWith("SquareV3_") && name.endsWith(".csv");}
    });
    if(files==null) return false;
    java.util.Arrays.sort(files,new java.util.Comparator<java.io.File>(){
      public int compare(java.io.File a,java.io.File b){return Long.compare(b.lastModified(),a.lastModified());}
    });
    for(int candidate=0;candidate<Math.min(5,files.length);candidate++) {
      if(files[candidate].length()>64L*1024*1024) continue;
      ArrayList<TCPTelemetry_c> current=new ArrayList<TCPTelemetry_c>();
      ArrayList<TCPTelemetry_c> lastStopped=null;
      TCPTelemetry_c idle=null;
      int currentTrial=-1;long previous=-1;
      try(java.io.BufferedReader reader=new java.io.BufferedReader(new java.io.FileReader(files[candidate]))) {
        String line;int lines=0;
        while((line=reader.readLine())!=null && lines++<1000000) {
          TCPTelemetry_c sample=new TCPTelemetry_c();
          if(!sample.parse(line,0) || sample.trial<0) continue;
          if(previous>=0 && sample.timestampMs<previous){current.clear();currentTrial=-1;idle=null;}
          previous=sample.timestampMs;
          if(sample.robotState==0) idle=sample.copy();
          else if(sample.robotState==1) {
            if(sample.trial!=currentTrial) {
              current=new ArrayList<TCPTelemetry_c>();currentTrial=sample.trial;
              if(idle!=null)current.add(idle.copy());
            }
            current.add(sample.copy());
          } else if((sample.robotState==2 || sample.robotState==3) && sample.trial==currentTrial && current.size()>0) {
            current.add(sample.copy());
            lastStopped=new ArrayList<TCPTelemetry_c>(current);
          }
        }
      } catch(java.io.IOException error){continue;}
      if(lastStopped!=null) {
        clear();
        for(TCPTelemetry_c sample:lastStopped){accept(sample);advance();}
        armed=false; // Only a fresh live idle packet can enable the GUI start button.
        return true;
      }
    }
    return false;
  }
}
