import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/player_widget.dart';
import '../widgets/chat_panel.dart';
import '../widgets/members_panel.dart';
import '../widgets/video_search_sheet.dart';
import 'home_screen.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyRoomId(String roomId) {
    Clipboard.setData(ClipboardData(text: roomId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room ID "$roomId" copied to clipboard'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _leaveRoom() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('Leave Room?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'You will be disconnected from this room.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<RoomProvider>().leaveRoom();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _openVideoSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<RoomProvider>(),
        child: const VideoSearchSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, provider, _) {
        final room = provider.room;
        if (room == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: _buildAppBar(room, provider),
          body: Column(
            children: [
              // Connection banner
              if (!provider.isConnectedToServer) _buildReconnectBanner(),

              // Player section (fixed height)
              PlayerWidget(key: const ValueKey('player')),

              // Host controls bar
              if (room.isHost) _buildHostControls(provider),

              // Tabs: Chat | Members
              _buildTabBar(),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    ChatPanel(),
                    MembersPanel(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(room, RoomProvider provider) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Room ID badge
            GestureDetector(
              onTap: () => _copyRoomId(room.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tag, size: 14, color: AppTheme.accentLight),
                    const SizedBox(width: 4),
                    Text(
                      room.id,
                      style: const TextStyle(
                        color: AppTheme.accentLight,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 12, color: AppTheme.accentLight),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Role badges
            if (room.isAdmin)
              _roleBadge('ADMIN', AppTheme.adminBadge)
            else if (room.isHost)
              _roleBadge('HOST', AppTheme.hostBadge),
            const Spacer(),
            // Online count
            Row(
              children: [
                const Icon(Icons.people_outline_rounded, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${room.onlineMemberCount}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded, color: AppTheme.danger),
              onPressed: _leaveRoom,
              tooltip: 'Leave room',
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildReconnectBanner() {
    return Container(
      width: double.infinity,
      color: AppTheme.warning.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Reconnecting...',
            style: TextStyle(color: AppTheme.warning, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHostControls(RoomProvider provider) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.divider),
          bottom: BorderSide(color: AppTheme.divider),
        ),
        color: AppTheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.queue_music_rounded, size: 16, color: AppTheme.hostBadge),
          const SizedBox(width: 8),
          const Text(
            'Host Controls',
            style: TextStyle(
              color: AppTheme.hostBadge,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _openVideoSearch,
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('Change Video'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentLight,
              side: const BorderSide(color: AppTheme.accent),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
        color: AppTheme.surface,
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppTheme.accent,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.accent,
        indicatorWeight: 2,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: const [
          Tab(icon: Icon(Icons.chat_bubble_outline_rounded, size: 16), text: 'Chat'),
          Tab(icon: Icon(Icons.people_outline_rounded, size: 16), text: 'Members'),
        ],
      ),
    );
  }
}