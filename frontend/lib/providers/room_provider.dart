// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbeat/models/message_model.dart';
import 'package:syncbeat/models/playback_state_model.dart';
import 'package:syncbeat/models/user_model.dart';
import 'package:uuid/uuid.dart';
import '../models/room_model.dart';
import '../services/socket_service.dart';
import '../services/youtube_service.dart';
import '../utils/app_config.dart';

/// ConnectionState for UI feedback
enum RoomConnectionState {
  disconnected,
  connecting,
  connected,
  inRoom,
  error,
}

/// RoomProvider
/// ------------
/// Central state manager for the entire app.
/// Handles:
///  - WebSocket lifecycle
///  - Room join/create
///  - Member list updates
///  - Chat messages
///  - Playback state sync
///
/// Sync algorithm (CRITICAL SECTION):
///  When a SYNC_PLAY event arrives, the client computes:
///    networkDelay = (clientNow - serverTime) in seconds
///    adjustedPosition = sentPosition + networkDelay
///  Then seeks the player to adjustedPosition.
///  This corrects for the time the event was in transit.
class RoomProvider extends ChangeNotifier {
  final SocketService _socket = SocketService();
  final YouTubeService _ytService = YouTubeService();

  RoomConnectionState _connectionState = RoomConnectionState.disconnected;
  RoomConnectionState get connectionState => _connectionState;

  String? _myUserId;
  String? get myUserId => _myUserId;

  String? _myDisplayName;
  String? get myDisplayName => _myDisplayName;

  RoomModel? _room;
  RoomModel? get room => _room;
  bool get isInRoom => _room != null;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Callback to notify the player widget to apply a sync event
  // (position in seconds, shouldPlay)
  void Function(double position, bool shouldPlay)? onSyncEvent;

  // Callback when a new video is loaded
  void Function(String videoId)? onVideoLoaded;

  // YouTube search results
  List<YouTubeSearchResult> _searchResults = [];
  List<YouTubeSearchResult> get searchResults => _searchResults;
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  /// Initialize — load saved userId and connect to WebSocket
  Future<void> initialize() async {
    _connectionState = RoomConnectionState.connecting;
    notifyListeners();

    // Persist userId so reconnects reuse the same ID
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getString('userId') ?? const Uuid().v4();
    await prefs.setString('userId', _myUserId!);

    _socket.init(
      onMessage: _handleMessage,
      onConnected: () {
        _connectionState = RoomConnectionState.connected;
        notifyListeners();
      },
      onDisconnected: () {
        if (_connectionState == RoomConnectionState.inRoom) {
          // Stay in "inRoom" state so UI shows reconnecting overlay
        } else {
          _connectionState = RoomConnectionState.disconnected;
        }
        notifyListeners();
      },
    );
  }

  // ─── Room Actions ──────────────────────────────────────────────────────────

  void createRoom(String displayName) {
    _myDisplayName = displayName.trim();
    _errorMessage = null;
    _socket.send({'type': 'CREATE_ROOM', 'displayName': _myDisplayName});
    notifyListeners();
  }

  void joinRoom(String roomId, String displayName) {
    _myDisplayName = displayName.trim();
    _errorMessage = null;
    _socket.send({
      'type': 'JOIN_ROOM',
      'roomId': roomId.trim().toUpperCase(),
      'displayName': _myDisplayName,
    });
    notifyListeners();
  }

  void leaveRoom() {
    _room = null;
    _connectionState = RoomConnectionState.connected;
    notifyListeners();
  }

  // ─── Playback Control (host only) ─────────────────────────────────────────

  void sendPlay(double currentPosition) {
    _socket.send({'type': 'PLAY', 'position': currentPosition});
  }

  void sendPause(double currentPosition) {
    _socket.send({'type': 'PAUSE', 'position': currentPosition});
  }

  void sendSeek(double position) {
    _socket.send({'type': 'SEEK', 'position': position});
  }

  void loadVideo(String videoId, {String? title, String? thumbnail}) {
    _socket.send({
      'type': 'LOAD_VIDEO',
      'videoId': videoId,
      'videoTitle': title ?? videoId,
      'videoThumbnail': thumbnail ?? YouTubeService.thumbnailUrl(videoId),
    });
  }

  // ─── Chat ──────────────────────────────────────────────────────────────────

  void sendChatMessage(String text) {
    if (text.trim().isEmpty) return;
    _socket.send({'type': 'CHAT_MESSAGE', 'text': text.trim()});
  }

  // ─── Host Management ──────────────────────────────────────────────────────

  void addHost(String targetUserId) {
    _socket.send({'type': 'ADD_HOST', 'targetUserId': targetUserId});
  }

  void removeHost(String targetUserId) {
    _socket.send({'type': 'REMOVE_HOST', 'targetUserId': targetUserId});
  }

  // ─── YouTube Search ───────────────────────────────────────────────────────

  Future<void> searchYouTube(String query) async {
    if (query.trim().isEmpty) return;
    _isSearching = true;
    notifyListeners();

    _searchResults = await _ytService.search(query);
    _isSearching = false;
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }

  // ─── Message Handling ─────────────────────────────────────────────────────

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    switch (type) {
      case WsMessageType.connected:
        // userId assigned by server (overrides our persisted one for this session)
        // Note: we keep the socket-assigned userId for this session.
        break;

      case WsMessageType.roomCreated:
      case WsMessageType.roomJoined:
        final roomData = msg['room'] as Map<String, dynamic>;
        _room = RoomModel.fromJson(roomData);
        _connectionState = RoomConnectionState.inRoom;
        _errorMessage = null;
        break;

      case WsMessageType.roomError:
        _errorMessage = msg['message'] as String? ?? 'Room error';
        break;

      case WsMessageType.memberJoined:
        if (_room == null) break;
        final member = UserModel.fromJson(msg['member'] as Map<String, dynamic>);
        // Avoid duplicates
        final updated = [..._room!.members.where((m) => m.id != member.id), member];
        _room = _room!.copyWith(members: updated);
        break;

      case WsMessageType.memberLeft:
        if (_room == null) break;
        final leftId = msg['userId'] as String;
        final updated = _room!.members.map((m) {
          return m.id == leftId ? m.copyWith(isOnline: false) : m;
        }).toList();
        _room = _room!.copyWith(members: updated);
        break;

      // ─── SYNC EVENTS ────────────────────────────────────────────────────

      case WsMessageType.syncPlay:
        _applySyncEvent(msg, shouldPlay: true);
        break;

      case WsMessageType.syncPause:
        _applySyncEvent(msg, shouldPlay: false);
        break;

      case WsMessageType.syncSeek:
        if (_room == null) break;
        final sentPosition = (msg['position'] as num).toDouble();
        final serverTime = msg['serverTime'] as int;
        final isPlaying = msg['isPlaying'] as bool? ?? _room!.playback.isPlaying;

        // Compute adjusted position accounting for network delay
        final adjustedPos = _computeAdjustedPosition(sentPosition, serverTime);

        _room = _room!.copyWith(
          playback: _room!.playback.copyWith(
            position: adjustedPos,
            updatedAt: serverTime,
          ),
        );
        onSyncEvent?.call(adjustedPos, isPlaying);
        break;

      case WsMessageType.syncLoad:
        if (_room == null) break;
        _room = _room!.copyWith(
          playback: _room!.playback.copyWith(
            videoId: msg['videoId'] as String?,
            videoTitle: msg['videoTitle'] as String?,
            videoThumbnail: msg['videoThumbnail'] as String?,
            isPlaying: false,
            position: 0,
            updatedAt: msg['serverTime'] as int,
          ),
        );
        if (msg['videoId'] != null) {
          onVideoLoaded?.call(msg['videoId'] as String);
        }
        break;

      case WsMessageType.syncState:
        if (_room == null) break;
        final playback = PlaybackStateModel.fromJson(
            msg['playback'] as Map<String, dynamic>);
        final serverTime = msg['serverTime'] as int;

        // If video is playing, compute where it should be NOW
        double adjustedPos = playback.position;
        if (playback.isPlaying) {
          adjustedPos = _computeAdjustedPosition(playback.position, playback.updatedAt);
        }

        _room = _room!.copyWith(
          playback: playback.copyWith(position: adjustedPos),
        );
        onSyncEvent?.call(adjustedPos, playback.isPlaying);
        break;

      case WsMessageType.chatMessage:
        if (_room == null) break;
        final message = MessageModel.fromJson(
            msg['message'] as Map<String, dynamic>);
        _room = _room!.copyWith(messages: [..._room!.messages, message]);
        break;

      case WsMessageType.hostAdded:
        if (_room == null) break;
        final hostId = msg['hostId'] as String;
        if (!_room!.hosts.contains(hostId)) {
          _room = _room!.copyWith(hosts: [..._room!.hosts, hostId]);
          // If it's us, update our role
          if (hostId == _socket.userId) {
            _room = _room!.copyWith(isHost: true);
          }
        }
        break;

      case WsMessageType.hostRemoved:
        if (_room == null) break;
        final removedId = msg['hostId'] as String;
        _room = _room!.copyWith(
          hosts: _room!.hosts.where((id) => id != removedId).toList(),
          isHost: removedId == _socket.userId ? false : _room!.isHost,
        );
        break;
    }

    notifyListeners();
  }

  /// ─── Sync Algorithm ────────────────────────────────────────────────────
  ///
  /// When server sends { position: P, serverTime: T }:
  ///   - P is where the video was at time T (server clock)
  ///   - clientNow is our current time (adjusted for clock offset)
  ///   - networkDelay = (clientNow - T) / 1000 seconds
  ///   - adjustedPosition = P + networkDelay
  ///
  /// This means if the PLAY event took 150ms to arrive, the client
  /// starts the video 0.15s ahead — perfectly synchronized.
  ///
  /// Drift correction: If the difference is within [syncToleranceSeconds],
  /// we DON'T seek (avoids micro-stutters). Only large drifts get corrected.
  double _computeAdjustedPosition(double sentPosition, int serverTime) {
    final clientNow = _socket.serverNow; // our best estimate of server time
    final networkDelaySeconds = (clientNow - serverTime) / 1000.0;
    return sentPosition + networkDelaySeconds.clamp(0.0, 10.0);
  }

  void _applySyncEvent(Map<String, dynamic> msg, {required bool shouldPlay}) {
    if (_room == null) return;

    final sentPosition = (msg['position'] as num).toDouble();
    final serverTime = msg['serverTime'] as int;

    final adjustedPos = _computeAdjustedPosition(sentPosition, serverTime);

    _room = _room!.copyWith(
      playback: _room!.playback.copyWith(
        isPlaying: shouldPlay,
        position: adjustedPos,
        updatedAt: serverTime,
      ),
    );

    onSyncEvent?.call(adjustedPos, shouldPlay);
  }

  /// Request current sync state from server (e.g., after reconnect)
  void requestSync() {
    _socket.send({'type': 'REQUEST_SYNC'});
  }

  String? get socketUserId => _socket.userId;
  bool get isConnectedToServer => _socket.isConnected;

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
  }
}