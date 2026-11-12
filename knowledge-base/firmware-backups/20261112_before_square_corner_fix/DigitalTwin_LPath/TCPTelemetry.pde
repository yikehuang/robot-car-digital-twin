/**
 * @brief One timestamped CSV telemetry record received from the StampC3.
 * @details The expected record has 14 comma-separated fields in the order
 * timestamp, pose, requested PWM, encoders, five surface readings, and signal.
 */
class TCPTelemetry_c {
  long timestampMs = -1;
  float x, y, theta;
  float pwmLeft, pwmRight;
  float encoderLeft, encoderRight;
  float[] sensorReadings = new float[5];
  int signal = 0;
  int trial = -1;
  int robotState = -1;
  int turnDirection = -1;
  String reason = "unknown";
  boolean hasSurfaceReadings = true;
  int receivedAtMs = -1;

  /**
   * @brief Parses and stores one complete CSV telemetry record.
   * @param line Input line without an assumed trailing newline.
   * @param arrivalMs Local Processing time at receipt, in ms.
   * @return True only when all 14 fields are present and numeric.
   */
  boolean parse(String line, int arrivalMs) {
    String[] fields = split(line, ',');
    // Benchmark frames contain no surface samples: do not invent zero readings.
    if (fields.length == 13) {
      if (!fields[1].equals("CW") && !fields[1].equals("CCW")) return false;
      int[] numeric = {0,2,3,5,6,7,8,9,10,11,12};
      for (int i : numeric) {
        float v=parseFloat(trim(fields[i]));
        if (Float.isNaN(v) || Float.isInfinite(v)) return false;
      }
      try {
        int newTrial=Integer.parseInt(trim(fields[0]));
        int state=Integer.parseInt(trim(fields[3]));
        long stamp=Long.parseLong(trim(fields[5]));
        if (state<0 || state>3 || newTrial<0 || stamp<0) return false;
        trial=newTrial; timestampMs=stamp; robotState=state; reason=fields[4];
        turnDirection=fields[1].equals("CW")?-1:1;
        encoderLeft=parseFloat(fields[6]); encoderRight=parseFloat(fields[7]);
        x=parseFloat(fields[8]); y=parseFloat(fields[9]); theta=parseFloat(fields[10]);
        pwmLeft=parseFloat(fields[11]); pwmRight=parseFloat(fields[12]);
        signal=state==1 ? 1 : 0;
        hasSurfaceReadings=false;
        receivedAtMs=arrivalMs;
        return true;
      } catch (NumberFormatException error) { return false; }
    }
    if (fields.length != 14) return false;
    float[] values = new float[14];
    for (int i = 0; i < fields.length; i++) {
      values[i] = parseFloat(trim(fields[i]));
      if (Float.isNaN(values[i])) return false;
    }
    timestampMs = (long)values[0];
    trial=-1;
    robotState=-1; reason="legacy";
    hasSurfaceReadings=true;
    x = values[1]; y = values[2]; theta = values[3];
    pwmLeft = values[4]; pwmRight = values[5];
    encoderLeft = values[6]; encoderRight = values[7];
    for (int i = 0; i < 5; i++) sensorReadings[i] = values[8 + i];
    signal = (int)values[13];
    receivedAtMs = arrivalMs;
    return true;
  }

  /** @return True if this sample arrived less than 100 ms ago. */
  boolean isRecent(int nowMs) { return receivedAtMs >= 0 && nowMs - receivedAtMs < 100; }

  /** @return An independent copy suitable for a buffered live comparison. */
  TCPTelemetry_c copy() {
    TCPTelemetry_c result = new TCPTelemetry_c();
    result.timestampMs = timestampMs; result.x = x; result.y = y; result.theta = theta;
    result.pwmLeft = pwmLeft; result.pwmRight = pwmRight;
    result.encoderLeft = encoderLeft; result.encoderRight = encoderRight;
    for (int i = 0; i < 5; i++) result.sensorReadings[i] = sensorReadings[i];
    result.signal = signal; result.receivedAtMs = receivedAtMs;
    result.trial = trial; result.hasSurfaceReadings = hasSurfaceReadings;
    result.robotState=robotState; result.reason=reason;
    result.turnDirection=turnDirection;
    return result;
  }
}
