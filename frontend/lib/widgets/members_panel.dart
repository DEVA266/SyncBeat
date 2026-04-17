import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../utils/app_theme.dart';

class MembersPanel extends StatelessWidget {
  const MembersPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, provider, _) {
        final room = provider.room;
        if (room == null) return const SizedBox.shrink();

        final members = room.members;
        final online = members.where((m) => m.isOnline).toList();
        final offline = members.where((m) => !m.isOnline).toList();

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _SectionHeader(
              label: 'Online',
              count: online.length,
              color: AppTheme.success,
            ),
            ...online.map((m) => _MemberTile(
                  member: m,
                  room: room,
                  provider: provider,
                )),
            if (offline.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionHeader(
                label: 'Offline',
                count: offline.length,
                color: AppTheme.textSecondary,
              ),
              ...offline.map((m) => _MemberTile(
                    member: m,
                    room: room,
                    provider: provider,
                  )),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final dynamic member;
  final dynamic room;
  final RoomProvider provider;

  const _MemberTile({
    required this.member,
    required this.room,
    required this.provider,
  });

  Color get _avatarColor {
    final colors = [
      AppTheme.accent,
      AppTheme.success,
      AppTheme.warning,
      AppTheme.danger,
      const Color(0xFF45B7D1),
    ];
    return colors[member.id.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = room.adminId == member.id;
    final isHost = room.hosts.contains(member.id);
    final isMe = provider.socketUserId == member.id;
    final canManage = room.isAdmin && !isMe && !isAdmin;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? AppTheme.accent.withOpacity(0.4) : AppTheme.divider,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _avatarColor.withOpacity(member.isOnline ? 1.0 : 0.4),
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Colors.white.withOpacity(member.isOnline ? 1.0 : 0.6),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (member.isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surfaceElevated, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Name + badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name + (isMe ? ' (you)' : ''),
                        style: TextStyle(
                          color: member.isOnline
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      _badge('ADMIN', AppTheme.adminBadge),
                    ] else if (isHost) ...[
                      const SizedBox(width: 6),
                      _badge('HOST', AppTheme.hostBadge),
                    ],
                  ],
                ),
                if (!member.isOnline)
                  const Text(
                    'Offline',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),

          // Admin controls
          if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppTheme.textSecondary, size: 20),
              color: AppTheme.surfaceElevated,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (action) {
                if (action == 'add_host') provider.addHost(member.id);
                if (action == 'remove_host') provider.removeHost(member.id);
              },
              itemBuilder: (_) => [
                if (!isHost)
                  const PopupMenuItem(
                    value: 'add_host',
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, color: AppTheme.hostBadge, size: 18),
                        SizedBox(width: 8),
                        Text('Make Host', style: TextStyle(color: AppTheme.textPrimary)),
                      ],
                    ),
                  ),
                if (isHost)
                  const PopupMenuItem(
                    value: 'remove_host',
                    child: Row(
                      children: [
                        Icon(Icons.star_border_rounded, color: AppTheme.danger, size: 18),
                        SizedBox(width: 8),
                        Text('Remove Host', style: TextStyle(color: AppTheme.danger)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}