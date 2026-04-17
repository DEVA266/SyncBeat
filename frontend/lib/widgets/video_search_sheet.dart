// ignore_for_file: unused_local_variable, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../services/youtube_service.dart';
import '../utils/app_theme.dart';

/// VideoSearchSheet
/// ----------------
/// Bottom sheet for searching YouTube or entering a video ID/URL directly.
/// Available only to hosts.
class VideoSearchSheet extends StatefulWidget {
  const VideoSearchSheet({super.key});

  @override
  State<VideoSearchSheet> createState() => _VideoSearchSheetState();
}

class _VideoSearchSheetState extends State<VideoSearchSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  final _urlController = TextEditingController();
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _loadByUrl(RoomProvider provider) {
    final input = _urlController.text.trim();
    final videoId = YouTubeService.extractVideoId(input);

    if (videoId == null) {
      setState(() => _urlError = 'Invalid YouTube URL or video ID');
      return;
    }

    provider.loadVideo(videoId, title: 'Video ($videoId)');
    Navigator.pop(context);
  }

  void _loadSearchResult(RoomProvider provider, YouTubeSearchResult result) {
    provider.loadVideo(
      result.videoId,
      title: result.title,
      thumbnail: result.thumbnailUrl,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Consumer<RoomProvider>(
        builder: (context, provider, _) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.queue_music_rounded, color: AppTheme.accent),
                  SizedBox(width: 10),
                  Text(
                    'Load a Video',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.accent,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.accent,
              tabs: const [
                Tab(text: 'Search YouTube'),
                Tab(text: 'URL / Video ID'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSearchTab(provider, scrollCtrl),
                  _buildUrlTab(provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(RoomProvider provider, ScrollController scrollCtrl) {
    final hasApiKey = true; // Show search tab; actual check in service

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search videos...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppTheme.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: AppTheme.textSecondary, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              provider.clearSearch();
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (q) {
                    if (q.trim().isNotEmpty) provider.searchYouTube(q);
                  },
                  onChanged: (v) => setState(() {}),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final q = _searchController.text.trim();
                  if (q.isNotEmpty) provider.searchYouTube(q);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: const Text('Search'),
              ),
            ],
          ),
        ),

        Expanded(
          child: provider.isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : provider.searchResults.isEmpty
                  ? _buildSearchEmpty()
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: provider.searchResults.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppTheme.divider, height: 1),
                      itemBuilder: (_, i) {
                        final result = provider.searchResults[i];
                        return _SearchResultTile(
                          result: result,
                          onTap: () => _loadSearchResult(provider, result),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSearchEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.youtube_searched_for_rounded,
              size: 48, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            'Search for a YouTube video\nto play for the room',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            'Requires YouTube API key in AppConfig',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlTab(RoomProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste a YouTube URL or Video ID:',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. dQw4w9WgXcQ  or  https://youtu.be/...',
              errorText: _urlError,
              prefixIcon:
                  const Icon(Icons.link_rounded, color: AppTheme.textSecondary),
            ),
            onChanged: (_) => setState(() => _urlError = null),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _loadByUrl(provider),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _loadByUrl(provider),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Load Video'),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: AppTheme.textSecondary),
                    SizedBox(width: 6),
                    Text(
                      'Accepted formats',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• Video ID: dQw4w9WgXcQ\n'
                  '• youtu.be/dQw4w9WgXcQ\n'
                  '• youtube.com/watch?v=dQw4w9WgXcQ',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final YouTubeSearchResult result;
  final VoidCallback onTap;

  const _SearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: result.thumbnailUrl.isNotEmpty
            ? Image.network(
                result.thumbnailUrl,
                width: 80,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbPlaceholder(),
              )
            : _thumbPlaceholder(),
      ),
      title: Text(
        result.title,
        style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.channelName,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_rounded,
            color: AppTheme.accent, size: 32),
        onPressed: onTap,
      ),
      onTap: onTap,
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 80,
      height: 48,
      color: AppTheme.surfaceElevated,
      child: const Icon(Icons.music_video_rounded,
          color: AppTheme.textSecondary, size: 24),
    );
  }
}