/** Builds authenticated commands; no network access or automatic start. */
class RemoteControlClient_c {
  final String key;
  String nonce = "";
  boolean ready = false;
  long sequence = 0;
  String status = "Waiting for control handshake";
  RemoteControlClient_c(String suppliedKey) {
    key = suppliedKey != null && suppliedKey.trim().matches("[0-9a-fA-F]{32}")
      ? suppliedKey.trim().toLowerCase(java.util.Locale.ROOT) : "";
    if (key.length() == 0) status = "Control key not paired";
  }
  boolean configured() { return key.length() == 32; }
  void disconnect() { ready=false; nonce=""; sequence=0; status="Waiting for control handshake"; }
  String receive(String line) {
    String[] fields=line.split(" ", -1);
    if (fields.length == 4 && fields[0].equals("CTRL") && fields[1].equals("HELLO")
        && fields[2].matches("[0-9a-f]{16}") && fields[3].equals("SQUARE_REMOTE_V2")) {
      if (!configured()) { status="Control key not paired"; return null; }
      if (!nonce.equals(fields[2])) { nonce=fields[2]; ready=false; sequence=0; }
      if (!ready) { status="Authenticating robot control"; return "AUTH "+nonce+" "+key+"\n"; }
    } else if (fields.length == 3 && fields[0].equals("CTRL") && fields[1].equals("READY")
        && fields[2].equals(nonce) && configured() && nonce.length()==16) {
      ready=true; status="Remote control ready";
    } else if (fields.length >= 2 && fields[0].equals("CTRL") && fields[1].equals("LOCKED")) {
      ready=false; status="Robot control key not provisioned";
    } else if (fields.length == 3 && fields[0].equals("CTRL") && fields[1].equals("DENIED")
        && fields[2].equals(nonce)) {
      ready=false; status="Control key mismatch; pair over USB";
    }
    return null;
  }
  String packet(String verb) {
    if (!ready || (!verb.equals("START") && !verb.equals("STOP") && !verb.equals("HEARTBEAT"))) return null;
    if (sequence >= 4294967295L) { disconnect(); return null; }
    return verb+" "+nonce+" "+(++sequence)+"\n";
  }
}
