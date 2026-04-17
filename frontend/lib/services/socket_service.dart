import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/app_config.dart';

/// Callback type for incoming messages
typedef MessageCallback = void Function(Map<String, dynamic> message);

/// SocketService
/// -------------
/// Manages the WebSocket connection to the backend.
///
/// Features:
///  - Auto-reconnect with exponential backoff
///  - Server clock synchronization (PING/PONG)
///  - Queues messages while disconnected
///  - Notifies listeners on connection state changes
class SocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Assigned by server on connect
  String? _userId;
  String? get userId => _userId;

  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _syncTimer;

  // Clock sync: difference between server clock and local clock (ms)
  // adjustedServerTime = DateTime.now().ms + _clockOffset
  int _clockOffset = 0;
  int get clockOffset => _clockOffset;

  // Message listener
  MessageCallback? _onMessage;
  VoidCallback? _onConnected;
  VoidCallback? _onDisconnected;

  // Pending messages while disconnected
  final List<Map<String, dynamic>> _pendingQueue = [];

  void init({
    required MessageCallback onMessage,
    VoidCallback? onConnected,
    VoidCallback? onDisconnected,
  }) {
    _onMessage = onMessage;
    _onConnected = onConnected;
    _onDisconnected = onDisconnected;
    _connect();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConfig.backendWsUrl));
      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      // Handle connection confirmation
      if (type == WsMessageType.connected) {
        _isConnected = true;
        _reconnectAttempts = 0;
        _userId = msg['userId'] as String?;

        // Sync clock immediately on connect
        _syncClock();

        // Start periodic clock sync
        _pingTimer = Timer.periodic(
          const Duration(seconds: 10),
          (_) => _syncClock(),
        );

        // Flush pending messages
        for (final pending in _pendingQueue) {
          send(pending);
        }
        _pendingQueue.clear();

        _onConnected?.call();
      }

      // Handle PONG: compute clock offset
      if (type == WsMessageType.pong) {
        final clientTime = msg['clientTime'] as int;
        final serverTime = msg['serverTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        // Round-trip time
        final rtt = now - clientTime;
        // Estimate: server was at serverTime when it sent the PONG,
        // which is approximately rtt/2 ago from now.
        // clockOffset = serverTime + rtt/2 - now
        _clockOffset = serverTime + (rtt ~/ 2) - now;
      }

      _onMessage?.call(msg);
    } catch (_) {
      // Malformed message — ignore
    }
  }

  void _onError(Object error) {
    _handleDisconnect();
  }

  void _onDone() {
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _syncTimer?.cancel();
    _subscription?.cancel();
    _onDisconnected?.call();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConfig.wsMaxReconnectAttempts) return;

    final delay = Duration(
      milliseconds: AppConfig.wsReconnectDelayMs * (1 << _reconnectAttempts.clamp(0, 4)),
    );
    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  /// Send a message. If not connected, queue it for when we reconnect.
  void send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    } else {
      // Queue critical messages only (don't queue chat while disconnected)
      final type = message['type'] as String?;
      if (type != 'CHAT_MESSAGE') {
        _pendingQueue.add(message);
      }
    }
  }

  /// Perform a clock synchronization ping.
  void _syncClock() {
    send({'type': 'PING', 'clientTime': DateTime.now().millisecondsSinceEpoch});
  }

  /// Get the current estimated server time in milliseconds.
  int get serverNow => DateTime.now().millisecondsSinceEpoch + _clockOffset;

  void dispose() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _syncTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close(status.goingAway);
  }
}

// Needed for VoidCallback type without importing Flutter
typedef VoidCallback = void Function();