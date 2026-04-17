import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../providers/room_provider.dart';
import '../utils/app_config.dart';
import '../utils/app_theme.dart';
import '../widgets/video_search_sheet.dart';

/// PlayerWidget
/// ------------
/// Embeds the YouTube player and wires it to the RoomProvider's sync system.
///
/// Sync logic:
///  - Host presses play/pause → sends event to server → server broadcasts
///    to all clients (including host) → all call _applySync()
///  - Non-host clients only receive events; their controls are hidden.
///  - Drift correction runs every 5 seconds when playing: if the player
///    position differs from expected by > syncToleranceSeconds, we seek.
class PlayerWidget extends StatefulWidget {
  const PlayerWidget({super.key});

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget> {
  YoutubePlayerController? _controller;
  String? _currentVideoId;

  // Expected position tracking for drift correction
  double _expectedPosition = 0.0;
  DateTime? _playStartedAt;
  bool _isExpectingPlay = false;

  Timer? _driftTimer;

  // Prevents feedback loops: when we programmatically seek/play/pause,
  // we don't want to re-broadcast that event.
  bool _suppressEvents = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<RoomProvider>();

      // Register sync callback — called when server sends a sync event
      provider.onSyncEvent = _applySync;

      // Register video load callback
      provider.onVideoLoaded = _loadVideo;

      // If room already has a video (late joiner), initialize it
      final playback = provider.room?.playback;
      if (playback != null && playback.hasVideo) {
        _initPlayer(playback.videoId!);
        if (playback.isPlaying) {
          _applySync(playback.position, true);
        }
      }
    });

    // Drift correction: every 5 seconds, check if we're in sync
    _driftTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkDrift());
  }

  void _initPlayer(String videoId) {
    _controller?.dispose();

    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        disableDragSeek: false,
        enableCaption: false,
        loop: false,
        forceHD: false,
      ),
    );

    _controller!.addListener(_onPlayerStateChange);
    _currentVideoId = videoId;

    if (mounted) setState(() {});
  }

  void _loadVideo(String videoId) {
    if (_currentVideoId == videoId) return;

    if (_controller != null) {
      _controller!.load(videoId);
      _currentVideoId = videoId;
    } else {
      _initPlayer(videoId);
    }
  }

  /// Called by RoomProvider when a sync event arrives from the server.
  /// This is the core of the sync system.
  void _applySync(double position, bool shouldPlay) {
    if (_controller == null) return;

    _suppressEvents = true;

    final currentPos = _controller!.value.position.inMilliseconds / 1000.0;
    final diff = (currentPos - position).abs();

    // Only seek if drift is beyond tolerance (avoids jarring micro-seeks)
    if (diff > AppConfig.syncToleranceSeconds) {
      _controller!.seekTo(Duration(milliseconds: (position * 1000).round()));
    }

    if (shouldPlay) {
      _controller!.play();
      _expectedPosition = position;
      _playStartedAt = DateTime.now();
      _isExpectingPlay = true;
    } else {
      _controller!.pause();
      _expectedPosition = position;
      _isExpectingPlay = false;
    }

    // Re-enable event broadcasting after a short delay
    // (player state change listener fires slightly after our command)
    Future.delayed(const Duration(milliseconds: 500), () {
      _suppressEvents = false;
    });
  }

  /// Periodic drift correction.
  /// If the player has drifted more than [syncToleranceSeconds] from
  /// where it should be, silently seek back into sync.
  void _checkDrift() {
    if (_controller == null || !_isExpectingPlay || _playStartedAt == null) return;
    if (!_controller!.value.isPlaying) return;

    final elapsed = DateTime.now().difference(_playStartedAt!).inMilliseconds / 1000.0;
    final expectedNow = _expectedPosition + elapsed;
    final actualPos = _controller!.value.position.inMilliseconds / 1000.0;

    final drift = (actualPos - expectedNow).abs();

    if (drift > AppConfig.syncToleranceSeconds * 2) {
      // Significant drift — silently correct
      _suppressEvents = true;
      _controller!.seekTo(Duration(milliseconds: (expectedNow * 1000).round()));
      Future.delayed(const Duration(milliseconds: 300), () => _suppressEvents = false);
    }
  }

  /// Listen to the YouTube player's state changes and broadcast
  /// to the room (only if host and not from a programmatic change).
  void _onPlayerStateChange() {
    if (_suppressEvents) return;
    if (!mounted) return;

    final provider = context.read<RoomProvider>();
    final room = provider.room;
    if (room == null || !room.isHost) return;

    final playerValue = _controller?.value;
    if (playerValue == null) return;

    // We don't broadcast on every tick — only on state transitions.
    // The player widget handles actual play/pause via host control buttons.
  }

  @override
  void dispose() {
    _driftTimer?.cancel();
    _controller?.removeListener(_onPlayerStateChange);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, provider, _) {
        final room = provider.room;
        final playback = room?.playback;

        // No video loaded yet
        if (playback == null || !playback.hasVideo || _controller == null) {
          return _buildPlaceholder(provider);
        }

        return Column(
          children: [
            // YouTube player
            YoutubePlayer(
              controller: _controller!,
              showVideoProgressIndicator: true,
              progressIndicatorColor: AppTheme.accent,
              progressColors: const ProgressBarColors(
                playedColor: AppTheme.accent,
                handleColor: AppTheme.accentLight,
                bufferedColor: Color(0xFF3A3A5A),
                backgroundColor: Color(0xFF1A1A2A),
              ),
              onReady: () {
                // Request sync when player is ready (handles late joiners)
                provider.requestSync();
              },
            ),
            // Video title + host controls
            _buildVideoInfo(playback, provider),
          ],
        );
      },
    );
  }

  Widget _buildPlaceholder(RoomProvider provider) {
    final isHost = provider.room?.isHost ?? false;
    return Container(
      height: 220,
      width: double.infinity,
      color: AppTheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_video_rounded,
            size: 56,
            color: AppTheme.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isHost ? 'Tap "Change Video" to load a song' : 'Waiting for host to start...',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          if (isHost) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppTheme.surfaceElevated,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => ChangeNotifierProvider.value(
                    value: provider,
                    child: const VideoSearchSheet(),
                  ),
                );
              },
              icon: const Icon(Icons.search_rounded),
              label: const Text('Find a Video'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoInfo(playback, RoomProvider provider) {
    final isHost = provider.room?.isHost ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playback.videoTitle ?? 'Now Playing',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      playback.isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                      size: 14,
                      color: playback.isPlaying ? AppTheme.success : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      playback.isPlaying ? 'Playing in sync' : 'Paused',
                      style: TextStyle(
                        color: playback.isPlaying ? AppTheme.success : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Host-only playback controls
          if (isHost && _controller != null)
            Row(
              children: [
                _controlButton(
                  icon: Icons.replay_10_rounded,
                  onTap: () {
                    final pos = _controller!.value.position.inSeconds.toDouble();
                    provider.sendSeek((pos - 10).clamp(0, double.infinity));
                  },
                ),
                const SizedBox(width: 4),
                _controlButton(
                  icon: playback.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  size: 40,
                  color: AppTheme.accent,
                  onTap: () {
                    final pos = _controller!.value.position.inMilliseconds / 1000.0;
                    if (playback.isPlaying) {
                      provider.sendPause(pos);
                    } else {
                      provider.sendPlay(pos);
                    }
                  },
                ),
                const SizedBox(width: 4),
                _controlButton(
                  icon: Icons.forward_10_rounded,
                  onTap: () {
                    final pos = _controller!.value.position.inSeconds.toDouble();
                    provider.sendSeek(pos + 10);
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 28,
    Color color = AppTheme.textPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: size, color: color),
    );
  }
}

// Import for VideoSearchSheet used in placeholder
