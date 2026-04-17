class MessageModel {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final int timestamp;

  const MessageModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      text: json['text'] as String,
      timestamp: json['timestamp'] as int,
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}