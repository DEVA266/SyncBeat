class PlaybackStateModel {
  final String? videoId;
  final String? videoTitle;
  final String? videoThumbnail;
  final bool isPlaying;
  final double position; // seconds
  final int updatedAt;   // server timestamp (ms)

  const PlaybackStateModel({
    this.videoId,
    this.videoTitle,
    this.videoThumbnail,
    this.isPlaying = false,
    this.position = 0.0,
    required this.updatedAt,
  });

  factory PlaybackStateModel.empty() {
    return PlaybackStateModel(updatedAt: DateTime.now().millisecondsSinceEpoch);
  }

  factory PlaybackStateModel.fromJson(Map<String, dynamic> json) {
    return PlaybackStateModel(
      videoId: json['videoId'] as String?,
      videoTitle: json['videoTitle'] as String?,
      videoThumbnail: json['videoThumbnail'] as String?,
      isPlaying: json['isPlaying'] as bool? ?? false,
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      updatedAt: json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  PlaybackStateModel copyWith({
    String? videoId,
    String? videoTitle,
    String? videoThumbnail,
    bool? isPlaying,
    double? position,
    int? updatedAt,
  }) {
    return PlaybackStateModel(
      videoId: videoId ?? this.videoId,
      videoTitle: videoTitle ?? this.videoTitle,
      videoThumbnail: videoThumbnail ?? this.videoThumbnail,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasVideo => videoId != null && videoId!.isNotEmpty;
}