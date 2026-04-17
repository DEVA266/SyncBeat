import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_config.dart';

class YouTubeSearchResult {
  final String videoId;
  final String title;
  final String channelName;
  final String thumbnailUrl;
  final String duration; // e.g., "3:45"

  const YouTubeSearchResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.thumbnailUrl,
    this.duration = '',
  });
}

/// YouTubeService
/// --------------
/// Wraps YouTube Data API v3 for video search.
///
/// If no API key is configured, falls back to manual video ID entry.
class YouTubeService {
  static const String _baseUrl = 'https://www.googleapis.com/youtube/v3';

  /// Search YouTube videos.
  /// Returns empty list if API key is not set.
  Future<List<YouTubeSearchResult>> search(String query) async {
    if (AppConfig.youtubeApiKey.isEmpty) return [];

    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'part': 'snippet',
        'q': query,
        'type': 'video',
        'maxResults': '10',
        'key': AppConfig.youtubeApiKey,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List? ?? [];

      return items.map((item) {
        final snippet = item['snippet'] as Map<String, dynamic>;
        final id = item['id'] as Map<String, dynamic>;
        final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
        final medium = thumbnails['medium'] as Map<String, dynamic>? ?? {};

        return YouTubeSearchResult(
          videoId: id['videoId'] as String? ?? '',
          title: snippet['title'] as String? ?? 'Unknown',
          channelName: snippet['channelTitle'] as String? ?? '',
          thumbnailUrl: medium['url'] as String? ?? '',
        );
      }).where((r) => r.videoId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Extract video ID from a YouTube URL or return as-is if it's already an ID.
  static String? extractVideoId(String input) {
    input = input.trim();

    // Already a video ID (11 chars, alphanumeric + - _)
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(input)) {
      return input;
    }

    // Try parsing as URL
    try {
      final uri = Uri.parse(input);
      // youtu.be/VIDEO_ID
      if (uri.host == 'youtu.be') {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
      // youtube.com/watch?v=VIDEO_ID
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
    } catch (_) {}

    return null;
  }

  /// Get thumbnail URL for a video ID
  static String thumbnailUrl(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/mqdefault.jpg';
  }
}