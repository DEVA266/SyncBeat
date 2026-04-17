import 'user_model.dart';
import 'message_model.dart';
import 'playback_state_model.dart';

class RoomModel {
  final String id;
  final String adminId;
  final List<String> hosts;
  final List<UserModel> members;
  final PlaybackStateModel playback;
  final List<MessageModel> messages;
  final bool isAdmin;
  final bool isHost;

  const RoomModel({
    required this.id,
    required this.adminId,
    required this.hosts,
    required this.members,
    required this.playback,
    required this.messages,
    required this.isAdmin,
    required this.isHost,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    final yourRole = json['yourRole'] as Map<String, dynamic>? ?? {};
    return RoomModel(
      id: json['id'] as String,
      adminId: json['adminId'] as String,
      hosts: List<String>.from(json['hosts'] as List? ?? []),
      members: (json['members'] as List? ?? [])
          .map((m) => UserModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      playback: PlaybackStateModel.fromJson(
          json['playback'] as Map<String, dynamic>? ?? {}),
      messages: (json['messages'] as List? ?? [])
          .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      isAdmin: yourRole['isAdmin'] as bool? ?? false,
      isHost: yourRole['isHost'] as bool? ?? false,
    );
  }

  RoomModel copyWith({
    List<String>? hosts,
    List<UserModel>? members,
    PlaybackStateModel? playback,
    List<MessageModel>? messages,
    bool? isHost,
    bool? isAdmin,
    String? adminId,
  }) {
    return RoomModel(
      id: id,
      adminId: adminId ?? this.adminId,
      hosts: hosts ?? this.hosts,
      members: members ?? this.members,
      playback: playback ?? this.playback,
      messages: messages ?? this.messages,
      isAdmin: isAdmin ?? this.isAdmin,
      isHost: isHost ?? this.isHost,
    );
  }

  int get onlineMemberCount => members.where((m) => m.isOnline).length;
}