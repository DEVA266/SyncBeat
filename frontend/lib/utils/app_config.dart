/// App-wide constants.
/// Update BACKEND_URL to your deployed server address.
class AppConfig {
  AppConfig._();

  /// WebSocket server URL.
  /// For local development: ws://10.0.2.2:3000 (Android emulator)
  /// For physical device on same WiFi: ws://YOUR_LOCAL_IP:3000
  /// For production: wss://your-deployed-server.com
  static const String backendWsUrl = 'ws://localhost:3000';

  /// HTTP server URL (same host, different scheme)
  static const String backendHttpUrl = 'http://10.0.2.2:3000';

  /// YouTube Data API v3 key (for video search).
  /// Get one at: https://console.developers.google.com
  /// Leave empty to disable search (manual video ID input only).
  static const String youtubeApiKey = '';

  /// WebSocket reconnection settings
  static const int wsReconnectDelayMs = 2000;
  static const int wsMaxReconnectAttempts = 10;

  /// Sync tolerance: if client is within this many seconds of server,
  /// don't seek (avoids jarring micro-seeks).
  static const double syncToleranceSeconds = 0.5;

  /// How often to auto-request a sync state (seconds)
  static const int periodicSyncIntervalSeconds = 30;
}

/// WebSocket message types — mirrors backend constants
class WsMessageType {
  WsMessageType._();
  static const String connected = 'CONNECTED';
  static const String pong = 'PONG';
  static const String roomCreated = 'ROOM_CREATED';
  static const String roomJoined = 'ROOM_JOINED';
  static const String roomError = 'ROOM_ERROR';
  static const String memberJoined = 'MEMBER_JOINED';
  static const String memberLeft = 'MEMBER_LEFT';
  static const String syncPlay = 'SYNC_PLAY';
  static const String syncPause = 'SYNC_PAUSE';
  static const String syncSeek = 'SYNC_SEEK';
  static const String syncLoad = 'SYNC_LOAD';
  static const String syncState = 'SYNC_STATE';
  static const String chatMessage = 'CHAT_MESSAGE';
  static const String hostAdded = 'HOST_ADDED';
  static const String hostRemoved = 'HOST_REMOVED';
  static const String error = 'ERROR';
}