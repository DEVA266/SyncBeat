/**
 * TimeManager
 * -----------
 * Provides a reliable server timestamp for synchronization.
 *
 * All playback events include `serverTime` so clients can compute:
 *   adjustedPosition = sentPosition + (clientNow - serverTime) / 1000
 *
 * This corrects for network latency: if the PLAY event took 100ms
 * to arrive, the client starts 0.1s ahead to stay in sync.
 */

class TimeManager {
  /**
   * Get current server time in milliseconds.
   * Using performance.now() + process.hrtime() would be more precise,
   * but Date.now() is sufficient for audio sync (sub-second accuracy).
   */
  now() {
    return Date.now();
  }

  /**
   * Build a time-sync response for clients to calibrate their clocks.
   * The client sends a ping with clientTime, server echoes back,
   * and the client can compute: clockDrift = (serverTime - clientTime) - (rtt / 2)
   */
  buildPingResponse(clientTime) {
    return {
      clientTime,          // echoed back so client knows RTT
      serverTime: this.now(), // authoritative server timestamp
    };
  }
}

module.exports = new TimeManager(); // singleton