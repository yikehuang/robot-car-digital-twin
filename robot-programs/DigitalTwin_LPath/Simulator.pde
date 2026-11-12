/**
 * @brief Owns the standalone application: timing, robot model, view, and TCP.
 * @details World positions use millimetres, with +x forward/right and +y
 * upward. Rendering may run at a variable frame rate; model/controller
 * updates use a fixed 10 ms interval.
 */
class Simulator {
  /** @brief Number of milliseconds visible in each telemetry graph. */
  final int graphWindowMs = 5000;
  final int graphSamplePeriodMs = 20;
  // Mirrors the physical robot's 10 ms update interval.
  final int simulationUpdateIntervalMs = 10;
  final int maximumCatchUpSteps = 10;
  /** @brief Default StampC3 access-point address for live comparison. */
  String tcpHost = "square-teammate.local";
  final boolean demoOnly=Boolean.getBoolean("square.demo");
  final int tcpPort = 80;
  final int tcpRetryPeriodMs = 2000;
  final int tcpConnectTimeoutMs = 250;
  final int tcpFreshnessTimeoutMs = 2000;
  final float minimumZoom = 0.25;
  final float maximumZoom = 4.0;
  final int SANDBOX = 0, LIVE_COMPARISON = 1;

  /** @brief Surface-image centre in world coordinates, in mm. */
  final float surfaceOffsetX;
  final float surfaceOffsetY;

  PImage surfaceImage;
  // Cache only the currently visible part of the 1 px/mm map. This avoids
  // redrawing the complete source image at 1:1 scale.
  PImage surfaceViewportCache;
  int surfaceCacheX = -1;
  int surfaceCacheY = -1;
  int surfaceCacheWidth = 0;
  int surfaceCacheHeight = 0;
  PApplet applet;
  /** @brief Robot-only Digital Twin model; the surface image is its environment. */
  RobotSimulation_c robot;
  Controller_c controller;
  LiveSession_c liveSession;
  TimeSeriesGraph motorGraph;
  TimeSeriesGraph positionErrorGraph;
  TimeSeriesGraph encoderGraph;

  boolean showTelemetry = true;
  boolean trackRobot = false;
  int simulatorMode = LIVE_COMPARISON;
  boolean liveArmed = false;
  boolean liveRunning = false;
  PrintWriter benchmarkLog = null;
  String benchmarkLogPath = "";
  TCPTelemetry_c ghost = new TCPTelemetry_c();
  boolean fitView=true;
  float zoom = 1.0;
  float viewCentreX = 0.0;
  float viewCentreY = 0.0;

  int lastGraphSampleMs = 0;
  int lastSimulationUpdateMs = 0;
  int simulationAccumulatorMs = 0;
  int lastTcpAttemptMs = -tcpRetryPeriodMs;

  Client telemetryClient;
  TCPTelemetry_c tcpTelemetry = new TCPTelemetry_c();
  String tcpStatus = "TCP: not connected";
  RemoteControlClient_c remoteControl;
  int lastControlHeartbeatMs = -200;
  boolean remoteStartPending = false;
  int remoteStartRequestedAtMs = 0;
  String remoteMessage = "Click START REAL ROBOT when the test area is ready";
  int tcpConnectedAtMs = -1;
  int lastTcpFrameAtMs = -1;
  String lastTcpLine = "";
  volatile boolean tcpAttemptInProgress = false;
  volatile boolean tcpAttemptFailed = false;
  volatile Socket pendingTcpSocket = null;
  volatile String pendingTcpHost = "";

  /**
   * @brief Creates the supplied baseline Digital Twin application.
   * @param appletIn Parent Processing application used for networking.
   * @param surfaceOffsetXIn Surface-image x offset in world millimetres.
   * @param surfaceOffsetYIn Surface-image y offset in world millimetres.
   */
  Simulator(PApplet appletIn, float surfaceOffsetXIn, float surfaceOffsetYIn) {
    applet = appletIn;
    if(demoOnly){simulatorMode=SANDBOX;tcpStatus="OFFLINE DEMO: network disabled";remoteMessage="Model prediction only; no physical robot connected";}
    java.io.File controlFile=new java.io.File(applet.sketchPath("robot-control.key"));
    String controlKey="";
    if (controlFile.isFile()) {
      String[] keyLines=applet.loadStrings(controlFile);
      if (keyLines!=null && keyLines.length>0) controlKey=keyLines[0];
    }
    remoteControl=new RemoteControlClient_c(controlKey);
    java.io.File hostFile = new java.io.File(applet.sketchPath("robot-host.txt"));
    if (hostFile.isFile()) {
      String[] hosts = applet.loadStrings(hostFile);
      if (hosts != null && hosts.length > 0 && trim(hosts[0]).matches("[A-Za-z0-9.-]{1,253}")) {
        tcpHost = trim(hosts[0]);
      }
    }
    surfaceOffsetX = surfaceOffsetXIn;
    surfaceOffsetY = surfaceOffsetYIn;
    ellipseMode(RADIUS);
    strokeJoin(ROUND);
    surfaceImage = loadSurfaceImage();
    ModelCalibration_c calibration=new ModelCalibration_c();
    robot = new RobotSimulation_c(calibration.wheelRadiusMm,calibration.wheelSeparationMm,surfaceImage,
      surfaceOffsetX, surfaceOffsetY);
    controller = new Controller_c();
    liveSession=new LiveSession_c(robot,controller);
    robot.resetForRun(0, 0, 0, 0, 0);
    // Live mode waits for an observed explicit PC start. Opening the
    // application must not look like a physical robot has already started.
    controller.setSignal(simulatorMode == SANDBOX ? 1 : 0);
    lastSimulationUpdateMs = millis();

    motorGraph = new TimeSeriesGraph("Motor PWM", graphWindowMs, true);
    motorGraph.addSeries("Sim L", color(220, 70, 70));
    motorGraph.addSeries("Sim R", color(70, 100, 220));
    motorGraph.addSeries("TCP L", color(145, 60, 190));
    motorGraph.addSeries("TCP R", color(20, 150, 150));
    positionErrorGraph = new TimeSeriesGraph("Model - robot odometry (mm)", graphWindowMs, true);
    positionErrorGraph.addSeries("dx",color(55,100,210));
    positionErrorGraph.addSeries("dy",color(200,90,45));
    encoderGraph = new TimeSeriesGraph("Encoder counts", graphWindowMs, false);
    encoderGraph.addSeries("Sim L", color(220, 70, 70));
    encoderGraph.addSeries("Sim R", color(70, 100, 220));
    encoderGraph.addSeries("TCP L", color(145, 60, 190));
    encoderGraph.addSeries("TCP R", color(20, 150, 150));

    if(!demoOnly && liveSession.restoreLastRun(new java.io.File(applet.sketchPath("logs")))) {
      ghost=liveSession.displayed.copy();
      remoteMessage="Last recorded attempt loaded; live robot remains stopped";
    }

  }

  /** @brief Updates TCP, advances fixed-step model time, and records graphs. */
  void update() {
    if(!demoOnly) updateTcpConnection();
    updateRobotModel();
    if (remoteStartPending && millis()-remoteStartRequestedAtMs>2000) {
      requestRealStop();
      remoteMessage="No running confirmation; stop requested. Check robot state below.";
    }

    if (trackRobot) {
      viewCentreX = simulatorMode==LIVE_COMPARISON && ghost.timestampMs>=0 ? ghost.x : robot.odometry.pose.x;
      viewCentreY = simulatorMode==LIVE_COMPARISON && ghost.timestampMs>=0 ? ghost.y : robot.odometry.pose.y;
    }
    recordTelemetry();
  }

  /**
   * @brief Accumulates elapsed wall-clock time into fixed model updates.
   * @note Long pauses are capped to prevent an unbounded catch-up simulation.
   */
  void updateRobotModel() {
    if (simulatorMode==LIVE_COMPARISON) {
      liveSession.advance();
      liveRunning=liveSession.running;
      liveArmed=liveSession.armed;
      return;
    }
    int now = millis();
    int elapsedMs = now - lastSimulationUpdateMs;
    lastSimulationUpdateMs = now;

    // Do not try to replay an unbounded amount of time after a breakpoint or
    // long application pause.
    elapsedMs = min(elapsedMs, simulationUpdateIntervalMs * maximumCatchUpSteps);
    simulationAccumulatorMs += elapsedMs;

    int steps = 0;
    while (simulationAccumulatorMs >= simulationUpdateIntervalMs
      && steps < maximumCatchUpSteps) {
      robot.advanceTime(simulationUpdateIntervalMs);
      controller.update(robot);
      robot.updatePhysics(simulationUpdateIntervalMs);
      liveSession.appendModel(false);
      simulationAccumulatorMs -= simulationUpdateIntervalMs;
      steps++;
    }
  }

  /** @brief Renders the surface, simulated robot, optional ghost, and UI. */
  void draw() {

    background(245,247,250);
    if (fitView) fitRouteView();

    pushMatrix();
    translate(navigationWidth()/2.0,navigationCentreY());
    scale(zoom, -zoom);
    translate(-viewCentreX, -viewCentreY);
    drawCoordinateGrid();
    drawTargetRoute();
    drawRunTrace(liveSession.modelTrace,color(45,100,205),2.3);
    if (simulatorMode==SANDBOX || liveSession.hasRun) drawModelPose();
    if (simulatorMode==LIVE_COMPARISON) drawRunTrace(liveSession.robotTrace,color(225,110,25),3.5);
    if (simulatorMode == LIVE_COMPARISON && ghost.timestampMs >= 0) drawGhost();

    popMatrix();

    drawStatus();
    drawPathLegend();
    if (showTelemetry) drawTelemetryPanel();
  }

  float navigationWidth(){return showTelemetry?width-telemetryPanelWidth():width;}
  float navigationTop(){return uiMargin()+max(18,16*uiScale())*9+22;}
  float navigationBottom(){return height-82;}
  float navigationCentreY(){return (navigationTop()+navigationBottom())/2;}
  void fitRouteView() {
    float[][] points=liveSession.targetPoints();
    float minX=points[0][0],maxX=minX,minY=points[0][1],maxY=minY;
    for(float[] point:points){minX=min(minX,point[0]);maxX=max(maxX,point[0]);minY=min(minY,point[1]);maxY=max(maxY,point[1]);}
    viewCentreX=(minX+maxX)/2;viewCentreY=(minY+maxY)/2;
    zoom=constrain(0.9*min(navigationWidth()/(maxX-minX+150),
      max(120,navigationBottom()-navigationTop())/(maxY-minY+150)),minimumZoom,maximumZoom);
  }
  void drawCoordinateGrid() {
    float halfWidth=navigationWidth()/(2*zoom);
    float halfHeight=max(120,navigationBottom()-navigationTop())/(2*zoom);
    float left=viewCentreX-halfWidth,right=viewCentreX+halfWidth;
    float bottom=viewCentreY-halfHeight,top=viewCentreY+halfHeight;
    pushStyle();stroke(222,227,234);strokeWeight(1/zoom);
    for(float x=floor(left/50)*50;x<=right;x+=50)line(x,bottom,x,top);
    for(float y=floor(bottom/50)*50;y<=top;y+=50)line(left,y,right,y);
    stroke(170,181,194);strokeWeight(1.3/zoom);
    line(left,0,right,0);line(0,bottom,0,top);popStyle();
  }
  void worldLabel(String label,float x,float y,int ink) {
    pushStyle();pushMatrix();translate(x,y);scale(1,-1);
    fill(ink);noStroke();textSize(11/zoom);textAlign(LEFT,BASELINE);text(label,0,0);
    popMatrix();popStyle();
  }
  void dashedSegment(float x0,float y0,float x1,float y1) {
    float length=dist(x0,y0,x1,y1);
    if(length==0)return;
    for(float offset=0;offset<length;offset+=12) {
      float a=offset/length,b=min(offset+7,length)/length;
      line(lerp(x0,x1,a),lerp(y0,y1,a),lerp(x0,x1,b),lerp(y0,y1,b));
    }
  }
  void drawTargetRoute() {
    float[][] points=liveSession.targetPoints();
    pushStyle();stroke(86,102,122);strokeWeight(2/zoom);noFill();
    for(int i=0;i<points.length-1;i++)dashedSegment(points[i][0],points[i][1],points[i+1][0],points[i+1][1]);
    fill(86,102,122);ellipse(points[0][0],points[0][1],3/zoom,3/zoom);
    noFill();ellipse(points[4][0],points[4][1],7/zoom,7/zoom);
    worldLabel("START / FINISH ("+nf(points[0][0],0,0)+", "+nf(points[0][1],0,0)+")",points[0][0]-10,points[0][1]+60,color(65,80,100));
    worldLabel(nf(controller.FIRST_LEG_MM,0,0)+" mm",(points[0][0]+points[1][0])/2-22,(points[0][1]+points[1][1])/2+12,color(65,80,100));
    worldLabel("90 deg",points[1][0]+10,points[1][1]+12,color(65,80,100));
    worldLabel(nf(controller.SECOND_LEG_MM,0,0)+" mm",(points[1][0]+points[2][0])/2+12,(points[1][1]+points[2][1])/2,color(65,80,100));
    worldLabel("4 sides x 200 mm | 4 right turns",points[3][0]-20,points[3][1]-25,color(65,80,100));
    popStyle();
  }
  void drawRunTrace(ArrayList<TracePoint_c> trace,int ink,float weight) {
    if(trace.size()<2)return;
    pushStyle();noFill();stroke(ink);strokeWeight(weight/zoom);strokeCap(ROUND);
    beginShape();for(TracePoint_c point:trace)vertex(point.x,point.y);endShape();popStyle();
  }
  void drawModelPose() {
    pushStyle();pushMatrix();translate(robot.odometry.pose.x,robot.odometry.pose.y);rotate(robot.odometry.pose.theta);
    stroke(45,100,205,160);strokeWeight(2/zoom);fill(70,120,220,35);
    ellipse(0,0,50,50);line(0,0,42,0);popMatrix();popStyle();
  }
  void drawPathLegend() {
    pushStyle();rectMode(CORNER);noStroke();fill(250,252,254,245);
    rect(0,height-80,navigationWidth(),80);
    textSize(11*uiScale());textAlign(LEFT,BASELINE);
    String[] names={"Target square","Robot odometry","Fitted model"};
    int[] inks={color(86,102,122),color(225,110,25),color(45,100,205)};
    for(int i=0;i<3;i++) {
      float x=uiMargin()+i*navigationWidth()/3;
      stroke(inks[i]);strokeWeight(3);line(x,height-61,x+20,height-61);
      noStroke();fill(inks[i]);text(names[i],x+26,height-57);
    }
    fill(55,70,90);
    String note="Grid: 50 mm | Square: 4 x 200 mm, 4 x 90 deg right turn";
    if(liveSession.hasRun)note="Trial "+liveSession.trial+" | robot time "+nf(liveSession.targetElapsedMs/1000.0,0,2)
      +" s | model time "+nf(robot.getMillis()/1000.0,0,2)+" s"+(liveSession.frozen?" | frozen: "+liveSession.stopReason:"");
    text(note,uiMargin(),height-34);
    fill(100,110,125);text("Orange uses wheel odometry; it is not independent position ground truth.",uiMargin(),height-13);
    popStyle();
  }

  void updateSurfaceViewportCache() {
    // Convert the visible world rectangle to source-image pixels. The image
    // is centred on the configured offset, and its y axis is opposite the
    // world y axis.
    float halfViewWidth = width / (2.0 * zoom);
    float halfViewHeight = height / (2.0 * zoom);
    int visibleX0 = floor(surfaceImage.width / 2.0
      + viewCentreX - surfaceOffsetX - halfViewWidth);
    int visibleX1 = ceil(surfaceImage.width / 2.0
      + viewCentreX - surfaceOffsetX + halfViewWidth);
    int visibleY0 = floor(surfaceImage.height / 2.0
      - viewCentreY + surfaceOffsetY - halfViewHeight);
    int visibleY1 = ceil(surfaceImage.height / 2.0
      - viewCentreY + surfaceOffsetY + halfViewHeight);

    visibleX0 = constrain(visibleX0, 0, surfaceImage.width);
    visibleX1 = constrain(visibleX1, 0, surfaceImage.width);
    visibleY0 = constrain(visibleY0, 0, surfaceImage.height);
    visibleY1 = constrain(visibleY1, 0, surfaceImage.height);
    if (visibleX1 <= visibleX0 || visibleY1 <= visibleY0) {
      surfaceViewportCache = null;
      return;
    }

    boolean cacheContainsView = surfaceViewportCache != null
      && visibleX0 >= surfaceCacheX
      && visibleY0 >= surfaceCacheY
      && visibleX1 <= surfaceCacheX + surfaceCacheWidth
      && visibleY1 <= surfaceCacheY + surfaceCacheHeight;
    if (cacheContainsView) return;

    // The margin lets the robot move or the view pan a little before a new
    // crop is made. It keeps cache creation out of the normal draw path.
    int cacheMargin = ceil(constrain(max(halfViewWidth, halfViewHeight) * 0.15,
      40, 250));
    surfaceCacheX = max(0, visibleX0 - cacheMargin);
    surfaceCacheY = max(0, visibleY0 - cacheMargin);
    int cacheRight = min(surfaceImage.width, visibleX1 + cacheMargin);
    int cacheBottom = min(surfaceImage.height, visibleY1 + cacheMargin);
    surfaceCacheWidth = cacheRight - surfaceCacheX;
    surfaceCacheHeight = cacheBottom - surfaceCacheY;
    surfaceViewportCache = surfaceImage.get(surfaceCacheX, surfaceCacheY,
      surfaceCacheWidth, surfaceCacheHeight);
  }

  void drawSurfaceViewportCache() {
    if (surfaceViewportCache == null) return;

    float worldX = surfaceOffsetX + surfaceCacheX + surfaceCacheWidth / 2.0
      - surfaceImage.width / 2.0;
    float worldY = surfaceOffsetY + surfaceImage.height / 2.0
      - (surfaceCacheY + surfaceCacheHeight / 2.0);
    image(surfaceViewportCache, worldX, worldY);
  }

  void drawGhost() {
    float alpha = robotDataFresh()?235:110;
    pushStyle(); pushMatrix();
    translate(ghost.x, ghost.y); rotate(ghost.theta);
    fill(235, 125, 35, alpha); stroke(180, 70, 15, alpha);
    strokeWeight(2/zoom);ellipse(0, 0, 45, 45);line(0,0,40,0);
    fill(180,70,15,alpha);noStroke();triangle(44,0,32,6,32,-6);
    popMatrix(); popStyle();
  }

  /**
   * @brief Handles the documented keyboard controls.
   * @param pressedKey Character key reported by Processing.
   * @param pressedKeyCode Processing key code for arrow-key panning.
   */
  void handleKey(char pressedKey, int pressedKeyCode) {
    if (pressedKey == ' ' || pressedKey == ESC) { requestRealStop(); return; }
    if (pressedKey == 'g' || pressedKey == 'G') { showTelemetry = !showTelemetry; fitView=true; }
    if (pressedKey == 't' || pressedKey == 'T') { trackRobot = !trackRobot; fitView=false; }
    if (pressedKey == 'f' || pressedKey == 'F') { fitView=true;trackRobot=false; }
    if ((pressedKey == 'm' || pressedKey == 'M') && !demoOnly && !liveRunning && !remoteStartPending) {
      requestRealStop(); toggleMode();
    }
    if (pressedKey == '+' || pressedKey == '=') { zoom = min(maximumZoom, zoom * 1.2);fitView=false; }
    if (pressedKey == '-') { zoom = max(minimumZoom, zoom / 1.2);fitView=false; }

    if (pressedKey == CODED) {
      // Arrow-key panning intentionally disables tracking so the requested
      // view remains visible after the key press.
      float panStepMm = 50.0 / zoom;
      if (pressedKeyCode == LEFT) panBy(-panStepMm, 0);
      if (pressedKeyCode == RIGHT) panBy(panStepMm, 0);
      if (pressedKeyCode == UP) panBy(0, panStepMm);
      if (pressedKeyCode == DOWN) panBy(0, -panStepMm);
    }
  }

  /** @brief Switches between standalone sandbox and live-comparison modes. */
  void toggleMode() {
    simulatorMode = simulatorMode == SANDBOX ? LIVE_COMPARISON : SANDBOX;
    resetLiveSession();
    liveSession.clear();fitView=true;
    if (simulatorMode == SANDBOX) controller.setSignal(1);
  }

  void panBy(float deltaX, float deltaY) {
    fitView=false;
    trackRobot = false;
    viewCentreX += deltaX;
    viewCentreY += deltaY;
  }

  void drawStatus() {
    int margin = uiMargin();
    int contentWidth = statusWidth();
    float lineHeight = max(18, 16 * uiScale());

    pushStyle();
    rectMode(CORNER);
    noStroke();
    fill(255, 255, 255, 205);
    rect(margin - 6, margin - 6, contentWidth + 12, lineHeight * 9 + 12, 5);
    fill(30);
    textSize(max(12, 13 * uiScale()));
    text(simulatorMode==LIVE_COMPARISON
      ? "Robot odometry: "+nf(ghost.x,0,1)+", "+nf(ghost.y,0,1)+" mm; "+nf(degrees(ghost.theta),0,1)+" deg"
      : "Sandbox model: "+nf(robot.odometry.pose.x,0,1)+", "+nf(robot.odometry.pose.y,0,1)+" mm",
      margin, margin + lineHeight, contentWidth, lineHeight);
    text("+/-: zoom   Arrows: pan   T: tracking "
      + (trackRobot ? "on" : "off") + "   G: graphs   F: fit   M: mode   SPACE: stop",
      margin, margin + lineHeight * 2, contentWidth, lineHeight);
    text(tcpStatus, margin, margin + lineHeight * 3, contentWidth, lineHeight);
    text(liveStatus(), margin, margin + lineHeight * 4, contentWidth, lineHeight);
    text(demoOnly?"Offline model demonstration; hardware control disabled":"Robot: "+robotStateText()+"   |   "+remoteControl.status,
      margin, margin+lineHeight*5,contentWidth,lineHeight);
    float buttonY=margin+lineHeight*6.25;
    float buttonW=controlButtonWidth(), buttonH=controlButtonHeight();
    fill(canStartRealRobot()?color(24,130,76):color(135));
    rect(margin,buttonY,buttonW,buttonH,5);
    fill(190,35,40);
    rect(margin+buttonW+12,buttonY,buttonW,buttonH,5);
    fill(255); textAlign(CENTER,CENTER);
    text(demoOnly?"OFFLINE DEMO":"START REAL ROBOT",margin+buttonW/2,buttonY+buttonH/2);
    text("STOP",margin+buttonW+12+buttonW/2,buttonY+buttonH/2);
    textAlign(LEFT,BASELINE); fill(30);
    text(remoteMessage,margin,margin+lineHeight*8.5,contentWidth,lineHeight);
    popStyle();
  }

  float controlButtonWidth() { return min(220*uiScale(),(statusWidth()-12)/2.0); }
  float controlButtonHeight() { return 32*uiScale(); }
  boolean robotDataFresh() { return lastTcpFrameAtMs>=0 && millis()-lastTcpFrameAtMs<=500; }
  boolean canStartRealRobot() {
    return simulatorMode==LIVE_COMPARISON && telemetryClient!=null && remoteControl.ready
      && robotDataFresh() && tcpTelemetry.robotState==0 && liveArmed && !liveRunning && !remoteStartPending;
  }
  String robotStateText() {
    if (!robotDataFresh()) return "no fresh data";
    String[] names={"WAITING","RUNNING","COMPLETE","STOPPED / ERROR"};
    int value=tcpTelemetry.robotState;
    return (value>=0 && value<4 ? names[value] : "legacy firmware")+" / "+tcpTelemetry.reason;
  }
  void handleMouse(int x,int y) {
    float buttonY=uiMargin()+max(18,16*uiScale())*6.25;
    if (y<buttonY || y>buttonY+controlButtonHeight()) return;
    float buttonW=controlButtonWidth();
    if (x>=uiMargin()+buttonW+12 && x<=uiMargin()+buttonW*2+12) requestRealStop();
    else if (x>=uiMargin() && x<=uiMargin()+buttonW && canStartRealRobot()) {
      // Arm a pending request only after the deliberate GUI click, never on reconnect.
      if (sendControl(remoteControl.packet("HEARTBEAT")) && sendControl(remoteControl.packet("START"))) {
        remoteStartPending=true; remoteStartRequestedAtMs=millis();
        remoteMessage="Start sent; waiting for the robot's RUNNING confirmation";
      }
    }
  }
  boolean sendControl(String packet) {
    if (packet==null || telemetryClient==null || !telemetryClient.active()) return false;
    try { telemetryClient.write(packet); return true; }
    catch (Exception error) {
      telemetryClient.stop(); telemetryClient=null; remoteControl.disconnect();
      remoteStartPending=false; resetLiveSession(); return false;
    }
  }
  void requestRealStop() {
    sendControl(remoteControl.packet("STOP"));
    remoteStartPending=false;
    controller.setSignal(0); robot.setMotorPWM(0,0); liveRunning=false;
    liveSession.freezeModel();
    if(liveSession.hasRun && liveSession.stopElapsedMs<0)liveSession.stopReason="stop requested";
    remoteMessage="Stop requested; confirm the robot reports STOPPED or WAITING";
  }
  void shutdown() {
    requestRealStop();
    if (telemetryClient!=null) { telemetryClient.stop(); telemetryClient=null; }
    if (benchmarkLog!=null) { benchmarkLog.flush(); benchmarkLog.close(); }
  }

  String liveStatus() {
    if (simulatorMode == SANDBOX) return "Mode: Sandbox";
    if (telemetryClient == null) return "Mode: Live comparison — Offline";
    if (liveSession.frozen && liveSession.hasRun) return "Mode: Live — comparison frozen / "+liveSession.stopReason;
    if(liveSession.partialRun)return "Mode: Live — connected mid-run; model alignment unavailable";
    if (!liveArmed) return "Mode: Live comparison — Awaiting fresh idle data";
    if (!liveRunning) return "Mode: Live comparison — Armed";
    return "Mode: Live — robot-clock sync; orange = robot odometry";
  }

  /** @brief Adds current simulation and, when recent, TCP values to graphs. */
  void recordTelemetry() {
    int now = millis();
    if (now - lastGraphSampleMs < graphSamplePeriodMs) return;
    lastGraphSampleMs = now;
    if (tcpTelemetry.isRecent(now)) {
    motorGraph.addSample(now, new float[] {robot.motors.left.pwm, robot.motors.right.pwm,
        tcpTelemetry.pwmLeft, tcpTelemetry.pwmRight});
      if(liveSession.hasRun) positionErrorGraph.addSample(now,new float[]{
        robot.odometry.pose.x-ghost.x,robot.odometry.pose.y-ghost.y});
      encoderGraph.addSample(now, new float[] {robot.odometry.encoders.left,
        robot.odometry.encoders.right, tcpTelemetry.encoderLeft, tcpTelemetry.encoderRight});
    } else {
      motorGraph.addSample(now, new float[] {
        robot.motors.left.pwm, robot.motors.right.pwm
      });
      encoderGraph.addSample(now, new float[] {
        robot.odometry.encoders.left, robot.odometry.encoders.right
      });
    }
  }

  float[] combine(float[] first, float[] second) {
    float[] combined = new float[first.length + second.length];
    for (int i = 0; i < first.length; i++) combined[i] = first[i];
    for (int i = 0; i < second.length; i++) combined[first.length + i] = second[i];
    return combined;
  }

  void drawTelemetryPanel() {
    int margin = uiMargin();
    int panelWidth = telemetryPanelWidth();
    int panelX = width - panelWidth;
    int graphWidth = panelWidth - 2 * margin;
    float titleHeight = max(28, 24 * uiScale());
    float graphGap = margin;
    float graphHeight = (height - titleHeight - margin * 4 - graphGap * 2) / 3.0;

    // The panel deliberately fills the available height. This keeps graph
    // backgrounds attached to their plots after a resize, including when the
    // window is made smaller than its normal working size.
    graphHeight = max(1, graphHeight);
    float graphY = titleHeight + margin;
    pushStyle();
    rectMode(CORNER);
    noStroke();
    fill(248, 248, 248, 235);
    rect(panelX, 0, panelWidth, height);
    fill(30);
    textSize(max(12, 13 * uiScale()));
    text("Telemetry (press G to hide)", panelX + margin, titleHeight - margin / 2.0);
    motorGraph.draw(panelX + margin, graphY, graphWidth, graphHeight);
    graphY += graphHeight + graphGap;
    positionErrorGraph.draw(panelX + margin, graphY, graphWidth, graphHeight);
    graphY += graphHeight + graphGap;
    encoderGraph.draw(panelX + margin, graphY, graphWidth, graphHeight);
    popStyle();
  }

  float uiScale() {
    return constrain(min(width / 1000.0, height / 800.0), 0.85, 1.5);
  }

  int uiMargin() {
    return max(10, round(12 * uiScale()));
  }

  int telemetryPanelWidth() {
    int availableWidth = max(180, width - 2 * uiMargin());
    int preferredWidth = round(width * 0.32);
    return min(max(260, preferredWidth), availableWidth);
  }

  int statusWidth() {
    int availableRight = showTelemetry ? width - telemetryPanelWidth() : width;
    return max(1, availableRight - 2 * uiMargin());
  }

  color sensorColour(int index) {
    color[] colours = {color(160, 60, 60), color(210, 120, 50),
      color(80, 150, 80), color(60, 120, 190), color(140, 70, 170)};
    return colours[index];
  }

  color tcpSensorColour(int index) {
    color[] colours = {color(225, 110, 110), color(245, 180, 70),
      color(105, 190, 105), color(80, 160, 230), color(185, 100, 210)};
    return colours[index];
  }

  /**
   * @brief Loads surface.png or creates the supplied A3 circular-line fallback.
   * @return A 1 pixel/mm surface image positioned using the configured offset.
   */
  PImage loadSurfaceImage() {
    PImage image = loadImage("surface.png");
    if (image != null && image.width > 0 && image.height > 0) return image;

    // A3 landscape is 420 x 297 mm. At 1 px/mm this generated test surface
    // has the same physical dimensions as the printed student sheet.
    image = createImage(420, 297, RGB);
    image.loadPixels();
    float circleRadius = 125.0;
    float lineWidth = 19.0;
    for (int py = 0; py < image.height; py++) {
      for (int px = 0; px < image.width; px++) {
        float dx = px - image.width / 2.0;
        float dy = py - image.height / 2.0;
        float distanceFromCentre = sqrt(dx * dx + dy * dy);
        boolean onLine = abs(distanceFromCentre - circleRadius) <= lineWidth / 2.0;
        image.pixels[py * image.width + px] = onLine ? color(0) : color(255);
      }
    }
    image.updatePixels();
    return image;
  }

  /** @brief Maintains the TCP connection and consumes bounded CSV input. */
  void updateTcpConnection() {
    int now = millis();
    if (telemetryClient != null && !telemetryClient.active()) {
      telemetryClient.stop();
      telemetryClient = null;
      remoteControl.disconnect(); remoteStartPending=false;
      tcpStatus = "TCP: disconnected; retrying";
      resetLiveSession();
    }

    if (pendingTcpSocket != null) {
      Socket connectedSocket = pendingTcpSocket;
      pendingTcpSocket = null;
      tcpAttemptInProgress = false;
      try {
        telemetryClient = new Client(applet, connectedSocket);
        tcpConnectedAtMs = now;
        lastTcpFrameAtMs = -1;
        remoteControl.disconnect(); remoteStartPending=false;
        tcpStatus = "TCP: socket open; awaiting robot data from " + pendingTcpHost;
      }
      catch (Exception error) {
        telemetryClient = null;
        tcpStatus = "TCP: unavailable; retrying";
        closeSocket(connectedSocket);
      }
    }

    if (tcpAttemptFailed) {
      tcpAttemptFailed = false;
      tcpAttemptInProgress = false;
      tcpStatus = "TCP: unavailable; retrying";
    }

    if (telemetryClient == null && !tcpAttemptInProgress
      && now - lastTcpAttemptMs >= tcpRetryPeriodMs) {
      beginTcpConnectionAttempt();
    }

    int linesRead = 0;
    while (telemetryClient != null && telemetryClient.available() > 0 && linesRead < 20) {
      String line = telemetryClient.readStringUntil('\n');
      if (line == null) break;
      lastTcpLine = trim(line);
      if (lastTcpLine.startsWith("CTRL ")) {
        String response=remoteControl.receive(lastTcpLine);
        if (response!=null) sendControl(response);
        if (lastTcpLine.startsWith("CTRL REJECT ")) {
          remoteStartPending=false; remoteMessage="Robot rejected start: "+lastTcpLine;
        } else if (lastTcpLine.startsWith("CTRL STOPPED ")) {
          remoteStartPending=false; remoteMessage="Robot acknowledged STOP";
        }
        linesRead++; continue;
      }
      if (tcpTelemetry.parse(lastTcpLine, now)) {
        lastTcpFrameAtMs = now;
        tcpStatus = "TCP: receiving robot data from " + pendingTcpHost + ":" + tcpPort;
        if (tcpTelemetry.trial >= 0) saveBenchmarkLine(lastTcpLine);
        handleTcpSample(tcpTelemetry);
      }
      linesRead++;
    }
    if (simulatorMode==LIVE_COMPARISON && remoteControl.ready && robotDataFresh()
        && now-lastControlHeartbeatMs>=200) {
      lastControlHeartbeatMs=now;
      sendControl(remoteControl.packet("HEARTBEAT"));
    }
    // An established TCP socket does not prove that the robot is sending data.
    // Disarm on a stalled feed and reconnect instead of showing a false-ready UI.
    int lastActivity = lastTcpFrameAtMs >= 0 ? lastTcpFrameAtMs : tcpConnectedAtMs;
    if (telemetryClient != null && lastActivity >= 0 && now - lastActivity > tcpFreshnessTimeoutMs) {
      telemetryClient.stop();
      telemetryClient = null;
      remoteControl.disconnect(); remoteStartPending=false;
      tcpStatus = "TCP: no fresh robot data; reconnecting";
      lastTcpAttemptMs = now;
      resetLiveSession();
    }
  }

  /**
   * @brief Uses a parsed physical-robot record for graphing and live alignment.
   * @param sample Newly received StampC3 telemetry record.
   */
  void handleTcpSample(TCPTelemetry_c sample) {
    if (sample.robotState==1) {
      remoteStartPending=false;
      remoteMessage="Real robot RUNNING: "+sample.reason;
    } else if (sample.robotState==2 || sample.robotState==3) {
      remoteStartPending=false;
      remoteMessage="Real robot "+(sample.robotState==2 ? "COMPLETE: " : "STOPPED: ")+sample.reason;
    }
    if (simulatorMode != LIVE_COMPARISON) return;
    int oldTrial=liveSession.trial;
    liveSession.accept(sample);
    ghost=liveSession.displayed.copy();
    liveArmed=liveSession.armed;liveRunning=liveSession.running;
    if(oldTrial!=liveSession.trial && sample.robotState==1) fitView=true;
  }

  void saveBenchmarkLine(String line) {
    if (benchmarkLog == null) {
      String stamp=year()+""+nf(month(),2)+nf(day(),2)+"_"+nf(hour(),2)+nf(minute(),2)+nf(second(),2)+"_"+millis();
      benchmarkLogPath=sketchPath("logs/SquareV3_"+stamp+".csv");
      benchmarkLog=createWriter(benchmarkLogPath);
      benchmarkLog.println("trial,direction,stage,state,reason,time_ms,left_count,right_count,x_mm,y_mm,theta_rad,left_pwm,right_pwm");
      println("Robot-reported benchmark log: "+benchmarkLogPath);
    }
    benchmarkLog.println(line);
    benchmarkLog.flush();
  }

  /** @brief Clears buffered TCP state and disarms the live-comparison run. */
  void resetLiveSession() {
    liveSession.pause();
    liveArmed = false;
    liveRunning = false;
    if (simulatorMode == LIVE_COMPARISON) controller.reset();
    if (simulatorMode == LIVE_COMPARISON) robot.setMotorPWM(0,0);
  }

  /** @brief Starts a short asynchronous connection attempt to the StampC3. */
  void beginTcpConnectionAttempt() {
    lastTcpAttemptMs = millis();
    tcpAttemptInProgress = true;
    tcpStatus = "TCP: connecting to " + tcpHost + ":" + tcpPort;
    new Thread(new Runnable() {
      public void run() {
        connectTcpInBackground();
      }
    }).start();
  }

  void connectTcpInBackground() {
    // mDNS follows the robot between upstream networks where supported.
    // An optional numeric robot-host.txt overrides it; AP access is a fallback.
    String[] candidates = {tcpHost, "square-teammate.local", "192.168.4.1"};
    for (int i = 0; i < candidates.length; i++) {
      boolean duplicate = false;
      for (int j = 0; j < i; j++) if (candidates[i].equals(candidates[j])) duplicate = true;
      if (duplicate) continue;
      Socket socket = new Socket();
      try {
        socket.connect(new InetSocketAddress(candidates[i], tcpPort), tcpConnectTimeoutMs);
        pendingTcpHost = candidates[i];
        pendingTcpSocket = socket;
        return;
      } catch (Exception error) { closeSocket(socket); }
    }
    tcpAttemptFailed = true;
  }

  void closeSocket(Socket socket) {
    try {
      socket.close();
    }
    catch (Exception ignored) {
    }
  }
}
