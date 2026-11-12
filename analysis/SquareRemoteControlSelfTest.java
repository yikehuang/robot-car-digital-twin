public class SquareRemoteControlSelfTest {
  static void require(boolean value, String message) {
    if (!value) throw new AssertionError(message);
  }
  public static void main(String[] args) {
    DigitalTwin_LPath app=new DigitalTwin_LPath();
    String key="0123456789abcdef0123456789abcdef";
    DigitalTwin_LPath.RemoteControlClient_c missing=app.new RemoteControlClient_c("");
    require(!missing.configured() && missing.packet("START")==null,"Unpaired client could issue start");
    DigitalTwin_LPath.RemoteControlClient_c client=app.new RemoteControlClient_c(key);
    require(client.packet("START")==null,"Opening client issued/allowed start before handshake");
    require(client.receive("CTRL HELLO 0123456789abcdef LPATH_REMOTE_V1")==null && !client.ready,"Old L-path firmware accepted by square client");
    require(client.receive("CTRL HELLO 0123456789abcdef SQUARE_REMOTE_V2")==null && !client.ready,"Old square firmware accepted by V3 client");
    String auth=client.receive("CTRL HELLO 0123456789abcdef SQUARE_REMOTE_V3");
    require(auth.equals("AUTH 0123456789abcdef "+key+"\n"),"Handshake contract mismatch");
    require(!client.ready && client.packet("START")==null,"HELLO alone armed motion");
    client.receive("CTRL READY fedcba9876543210");
    require(!client.ready,"Old/wrong session READY accepted");
    client.receive("CTRL READY 0123456789abcdef");
    require(client.ready,"Authenticated READY missing");
    require(client.packet("HEARTBEAT").equals("HEARTBEAT 0123456789abcdef 1\n"),"Heartbeat serialization");
    require(client.packet("START").equals("START 0123456789abcdef 2\n"),"Explicit start serialization");
    client.receive("CTRL READY 0123456789abcdef");
    require(client.packet("STOP").equals("STOP 0123456789abcdef 3\n"),"Repeated READY reset sequence");
    require(client.packet("FORWARD")==null,"Unspecified motor command accepted");
    client.receive("CTRL HELLO fedcba9876543210 SQUARE_REMOTE_V3");
    require(!client.ready && client.sequence==0 && client.packet("START")==null,"New session auto-start risk");
    client.receive("CTRL READY 0123456789abcdef");
    require(!client.ready,"Previous connection READY accepted");
    client.receive("CTRL READY fedcba9876543210");
    client.sequence=4294967295L;
    require(client.packet("HEARTBEAT")==null && !client.ready,"Sequence wrap was not fail-closed");
    client.disconnect();
    require(!client.ready && client.packet("START")==null,"Disconnect retained start readiness");
    System.out.println("PASS: pairing, handshake, no automatic start, wrong-session rejection, ordered commands, repeated READY, reconnect, sequence exhaustion.");
    System.out.println("Pure client software test: no real network or motor commands were sent.");
  }
}
