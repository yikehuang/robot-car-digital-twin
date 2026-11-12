import java.io.BufferedReader;
import java.io.IOException;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import processing.core.PImage;

/** Offline comparison of square benchmark telemetry with an independent twin.
 * Adapted from the supplied DigitalTwin_OfflineEvaluation handoff (credits Yanxin Luo).
 * The original handoff and SHA-256 provenance are in acknowledgements/.
 */
public class SquareReplayEvaluation {
  private static final int STEP_MS = 10;
  // The V3 controller allows up to 30 s of motion plus settling per stage.
  private static final long MODEL_LIMIT_MS = 300_000;

  private final DigitalTwin_LPath app = new DigitalTwin_LPath();
  private final DigitalTwin_LPath.ModelCalibration_c calibration = app.new ModelCalibration_c();
  private final DigitalTwin_LPath.RobotSimulation_c model = app.new RobotSimulation_c(
      calibration.wheelRadiusMm, calibration.wheelSeparationMm, new PImage(4, 4), 0, 0);
  private final DigitalTwin_LPath.Controller_c controller = app.new Controller_c();

  public static void main(String[] args) throws Exception {
    // Preserve existing three-argument historical replay commands.
    if (args.length == 3) {
      LegacySquareReplayEvaluation.main(args);
      return;
    }
    if (args.length != 2) {
      throw new IllegalArgumentException("Usage: SquareReplayEvaluation <telemetry.csv> <output-directory>");
    }
    new SquareReplayEvaluation().evaluate(Path.of(args[0]), Path.of(args[1]));
  }

  private void evaluate(Path input, Path output) throws IOException {
    Files.createDirectories(output);
    try (BufferedReader reader = Files.newBufferedReader(input, StandardCharsets.UTF_8);
         PrintWriter metrics = new PrintWriter(output.resolve("square_metrics.csv").toFile(), "UTF-8");
         PrintWriter trace = new PrintWriter(output.resolve("square_trace.csv").toFile(), "UTF-8")) {
      metrics.println("run,trial,robot_stop_reason,robot_stop_ms,position_rmse_mm,"
          + "position_gap_at_robot_stop_mm,twin_stop_reason,twin_stop_ms,"
          + "completion_time_delta_ms,completion_endpoint_gap_mm,completion_heading_delta_deg");
      trace.println("run,trial,robot_elapsed_ms,twin_pose_ms,odom_x_mm,odom_y_mm,"
          + "twin_x_mm,twin_y_mm,odom_theta_rad,twin_theta_rad,twin_stage");
      boolean armed = false;
      long previousStamp = -1;
      long startStamp = -1;
      int trial = -1;
      int run = 0;
      int runningSamples = 0;
      double squaredError = 0;
      String line;
      while ((line = reader.readLine()) != null) {
        DigitalTwin_LPath.TCPTelemetry_c sample = app.new TCPTelemetry_c();
        if (!sample.parse(line, 0) || sample.trial < 0) continue;
        if (sample.timestampMs < previousStamp) {
          startStamp = -1;
          armed = false;
        }
        previousStamp = sample.timestampMs;
        if (sample.trial != trial) startStamp = -1;
        trial = sample.trial;

        if (sample.robotState == 0) {
          startStamp = -1;
          armed = true;
          continue;
        }
        if (sample.robotState == 1 && startStamp < 0) {
          if (!armed) continue;
          armed = false;
          if (sample.turnDirection != controller.TURN_DIRECTION) continue;
          startStamp = sample.timestampMs;
          run++;
          runningSamples = 0;
          squaredError = 0;
          model.simulationMillis = 0;
          model.resetForRun(sample.x, sample.y, sample.theta, sample.encoderLeft, sample.encoderRight);
          controller.reset();
          controller.setSignal(1);
        }
        if (startStamp < 0) continue;

        long elapsedMs = sample.timestampMs - startStamp;
        advanceTo(elapsedMs);
        trace.printf(Locale.ROOT, "%d,%d,%d,%d,%.3f,%.3f,%.3f,%.3f,%.7f,%.7f,%d%n",
            run, trial, elapsedMs, model.getMillis(), sample.x, sample.y,
            model.odometry.pose.x, model.odometry.pose.y, sample.theta,
            model.odometry.pose.theta, controller.stage);
        double positionGap = positionGap(sample);
        if (sample.robotState == 1) {
          runningSamples++;
          squaredError += positionGap * positionGap;
          continue;
        }

        // Record the same-time gap before advancing past the robot's stop.
        advanceTo(MODEL_LIMIT_MS);
        String twinReason = controller.state == controller.RUNNING ? "evaluation_timeout" : controller.reason;
        metrics.printf(Locale.ROOT, "%d,%d,%s,%d,%.4f,%.4f,%s,%d",
            run, trial, sample.reason, elapsedMs, Math.sqrt(squaredError / runningSamples),
            positionGap, twinReason, model.getMillis());
        if (sample.robotState == 2 && controller.state == controller.COMPLETE) {
          double headingDelta = model.odometry.pose.theta - sample.theta;
          double wrappedDegrees = Math.toDegrees(Math.atan2(Math.sin(headingDelta), Math.cos(headingDelta)));
          metrics.printf(Locale.ROOT, ",%d,%.4f,%.4f%n",
              model.getMillis() - elapsedMs, positionGap(sample), wrappedDegrees);
        } else {
          metrics.println(",,,");
        }
        startStamp = -1;
      }
      if (metrics.checkError() || trace.checkError()) throw new IOException("Could not write evaluation CSVs.");
    }
  }

  private void advanceTo(long elapsedMs) {
    long limit = Math.min(elapsedMs, MODEL_LIMIT_MS);
    while (controller.state == controller.RUNNING && model.getMillis() + STEP_MS <= limit) {
      model.advanceTime(STEP_MS);
      controller.update(model);
      model.updatePhysics(STEP_MS);
    }
  }

  private double positionGap(DigitalTwin_LPath.TCPTelemetry_c sample) {
    return Math.hypot(model.odometry.pose.x - sample.x, model.odometry.pose.y - sample.y);
  }
}
