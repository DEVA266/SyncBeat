import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/room_provider.dart';
import '../utils/app_theme.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final atBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 40;
      if (atBottom != _isAtBottom) {
        setState(() => _isAtBottom = atBottom);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    context.read<RoomProvider>().sendChatMessage(text);
    _textController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, provider, _) {
        final messages = provider.room?.messages ?? [];
        final myId = provider.socketUserId;

        // Auto-scroll when new messages arrive
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isAtBottom && _scrollController.hasClients) {
            _scrollToBottom();
          }
        });

        return Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isMe = msg.userId == myId;
                        return _MessageBubble(
                          key: ValueKey(msg.id),
                          message: msg,
                          isMe: isMe,
                        );
                      },
                    ),
            ),

            // Jump to bottom button
            if (!_isAtBottom)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 4),
                  child: GestureDetector(
                    onTap: _scrollToBottom,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.arrow_downward_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),

            // Input field
            _buildInputBar(),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 40, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            'No messages yet.\nSay hello! 👋',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.divider)),
        color: AppTheme.surface,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: AppTheme.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final dynamic message;
  final bool isMe;

  const _MessageBubble({super.key, required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: _avatarColor(message.userId),
              child: Text(
                message.userName.isNotEmpty ? message.userName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.userName,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.accent : AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    timeago.format(message.dateTime, allowFromNow: true),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(String userId) {
    final colors = [
      const Color(0xFF6C63FF),
      const Color(0xFF4ECCA3),
      const Color(0xFFFFB347),
      const Color(0xFFFF6B6B),
      const Color(0xFF45B7D1),
      const Color(0xFF98D8C8),
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }
}