#ifndef LPATH_REMOTE_CONTROL_H
#define LPATH_REMOTE_CONTROL_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>

// Pure command gate: no hardware, networking, clock reads or motor side effects.
// Keeping it independent permits the on-device self-test to exercise exactly
// the production authentication, replay and watchdog policy without moving wheels.
class RemoteControl_c {
 public:
  enum Action { Rejected, Authenticated, Heartbeat, Start, Stop };
  static const uint32_t LEASE_MS = 1500;
  static bool isHex(const char *value, size_t length) {
    if (!value || strlen(value) != length) return false;
    for (size_t i = 0; i < length; ++i)
      if (!((value[i] >= '0' && value[i] <= '9') ||
            (value[i] >= 'a' && value[i] <= 'f') ||
            (value[i] >= 'A' && value[i] <= 'F'))) return false;
    return true;
  }
  bool configureKey(const char *value) {
    authenticated = false;
    key[0] = 0;
    if (!isHex(value, 32)) return false;
    memcpy(key, value, 33); return true;
  }
  void beginSession(const char *value) {
    authenticated = false; lastSequence = 0; lastControlMs = 0;
    nonce[0] = 0;
    if (isHex(value, 16)) memcpy(nonce, value, 17);
  }
  bool configured() const { return key[0] != 0; }
  bool ready() const { return authenticated; }
  const char *session() const { return nonce; }
  uint32_t sequence() const { return lastSequence; }
  bool fresh(uint32_t now) const {
    return authenticated && uint32_t(now - lastControlMs) <= LEASE_MS;
  }
  Action consume(const char *line, uint32_t now, bool running) {
    if (!line || strlen(line) >= 128 || !configured() || !nonce[0]) return Rejected;
    char parts[128]; strcpy(parts, line);
    char *tokens[4] = {nullptr, nullptr, nullptr, nullptr};
    size_t count = 0;
    char *p = parts;
    while (*p) {
      if (count == 4 || *p == ' ') return Rejected;
      tokens[count++] = p;
      while (*p && *p != ' ') ++p;
      if (*p) { *p++ = 0; if (!*p) return Rejected; }
    }
    if (count != 3 || strcmp(tokens[1], nonce) != 0) return Rejected;
    if (strcmp(tokens[0], "AUTH") == 0) {
      if (running || !isHex(tokens[2], 32)) return Rejected;
      unsigned difference = 0;
      for (size_t i = 0; i < 32; ++i) difference |= unsigned(key[i] ^ tokens[2][i]);
      if (difference) return Rejected;
      if (!authenticated) lastSequence = 0;
      authenticated = true; lastControlMs = now;
      return Authenticated;
    }
    if (!authenticated) return Rejected;
    uint32_t sequence = 0;
    if (!*tokens[2]) return Rejected;
    for (const char *digit = tokens[2]; *digit; ++digit) {
      if (*digit < '0' || *digit > '9') return Rejected;
      const uint32_t value = uint32_t(*digit - '0');
      if (sequence > (UINT32_MAX - value) / 10) return Rejected;
      sequence = sequence * 10 + value;
    }
    if (sequence <= lastSequence) return Rejected;
    Action action = Rejected;
    if (strcmp(tokens[0], "STOP") == 0) action = Stop;
    else if (strcmp(tokens[0], "HEARTBEAT") == 0) {
      // An expired moving run must stop rather than be resurrected by a late packet.
      if (running && !fresh(now)) return Rejected;
      action = Heartbeat;
    } else if (strcmp(tokens[0], "START") == 0 && !running && fresh(now)) action = Start;
    if (action == Rejected) return action;
    lastSequence = sequence; lastControlMs = now;
    return action;
  }
 private:
  char key[33] = {};
  char nonce[17] = {};
  bool authenticated = false;
  uint32_t lastSequence = 0;
  uint32_t lastControlMs = 0;
};

// Discard an entire oversized frame until newline, never parse its suffix.
class RemoteLine_c {
 public:
  bool push(char ch) {
    if (ch == '\r') return false;
    if (ch == '\n') {
      bool valid = !overflow && used > 0;
      text[used] = 0; used = 0; overflow = false;
      return valid;
    }
    if (static_cast<unsigned char>(ch) < 32 || used >= sizeof(text) - 1) overflow = true;
    if (!overflow) text[used++] = ch;
    return false;
  }
  const char *line() const { return text; }
  void reset() { used = 0; overflow = false; text[0] = 0; }
 private:
  char text[128] = {};
  size_t used = 0;
  bool overflow = false;
};

inline bool remoteControlSelfTest() {
  RemoteControl_c gate;
  const char *key = "0123456789abcdef0123456789abcdef";
  const char *nonce = "0123456789abcdef";
  if (gate.configureKey("") || gate.ready()) return false;
  if (!gate.configureKey(key)) return false;
  gate.beginSession(nonce);
  if (gate.consume("START 0123456789abcdef 1", 10, false) != RemoteControl_c::Rejected) return false;
  if (gate.consume("AUTH 0123456789abcdef 00000000000000000000000000000000", 10, false) != RemoteControl_c::Rejected) return false;
  if (gate.consume("AUTH 0123456789abcdef 0123456789abcdef0123456789abcdef", 10, false) != RemoteControl_c::Authenticated) return false;
  if (gate.consume("START 0123456789abcdef 1", 11, false) != RemoteControl_c::Start) return false;
  if (gate.consume("START 0123456789abcdef 1", 12, false) != RemoteControl_c::Rejected) return false;
  if (gate.consume("START 0123456789abcdef 2", 13, true) != RemoteControl_c::Rejected) return false;
  if (gate.consume("HEARTBEAT 0123456789abcdef 2", 200, true) != RemoteControl_c::Heartbeat) return false;
  if (gate.consume("HEARTBEAT 0123456789abcdef 3", 1701, true) != RemoteControl_c::Rejected || gate.fresh(1701)) return false;
  if (gate.consume("STOP 0123456789abcdef 3", 1702, true) != RemoteControl_c::Stop) return false;
  if (gate.consume("HEARTBEAT 0123456789abcdef 4294967296", 1703, false) != RemoteControl_c::Rejected) return false;
  if (gate.consume("START 0123456789abcdef 4 extra", 1703, false) != RemoteControl_c::Rejected) return false;
  gate.beginSession("fedcba9876543210");
  if (gate.ready() || gate.consume("START 0123456789abcdef 4", 1704, false) != RemoteControl_c::Rejected) return false;
  gate.beginSession(nonce);
  if (gate.consume("AUTH 0123456789abcdef 0123456789abcdef0123456789abcdef", UINT32_MAX - 100, false) != RemoteControl_c::Authenticated) return false;
  if (!gate.fresh(100) || gate.fresh(1600)) return false;
  RemoteLine_c buffer;
  for (int i = 0; i < 200; ++i) buffer.push('x');
  if (buffer.push('\n')) return false;
  const char *good = "STOP 0123456789abcdef 1\n";
  bool gotLine = false;
  for (const char *p = good; *p; ++p) if (buffer.push(*p)) gotLine = true;
  return gotLine && strcmp(buffer.line(), "STOP 0123456789abcdef 1") == 0;
}
#endif
