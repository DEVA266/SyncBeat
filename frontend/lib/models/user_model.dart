class UserModel {
  final String id;
  final String name;
  final bool isOnline;
  final int joinedAt;

  const UserModel({
    required this.id,
    required this.name,
    this.isOnline = true,
    required this.joinedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isOnline: json['isOnline'] as bool? ?? true,
      joinedAt: json['joinedAt'] as int? ?? 0,
    );
  }

  UserModel copyWith({bool? isOnline}) {
    return UserModel(
      id: id,
      name: name,
      isOnline: isOnline ?? this.isOnline,
      joinedAt: joinedAt,
    );
  }
}