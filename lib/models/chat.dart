import 'user.dart';
import 'message.dart';

enum ChatType {
  direct, // One-on-one chat
  group,  // Group chat
}

class Chat {
  final String id;
  final String name;
  final ChatType type;
  final List<String> participantIds;
  final List<User> participants;
  final Message? lastMessage;
  final DateTime lastActivity;
  final int unreadCount;
  final String? groupImageUrl;
  final String? description;
  final String? createdBy;
  final DateTime createdAt;

  const Chat({
    required this.id,
    required this.name,
    required this.type,
    required this.participantIds,
    this.participants = const [],
    this.lastMessage,
    required this.lastActivity,
    this.unreadCount = 0,
    this.groupImageUrl,
    this.description,
    this.createdBy,
    required this.createdAt,
  });

  Chat copyWith({
    String? id,
    String? name,
    ChatType? type,
    List<String>? participantIds,
    List<User>? participants,
    Message? lastMessage,
    DateTime? lastActivity,
    int? unreadCount,
    String? groupImageUrl,
    String? description,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      participantIds: participantIds ?? this.participantIds,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      lastActivity: lastActivity ?? this.lastActivity,
      unreadCount: unreadCount ?? this.unreadCount,
      groupImageUrl: groupImageUrl ?? this.groupImageUrl,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isDirectChat => type == ChatType.direct;
  bool get isGroupChat => type == ChatType.group;
  bool get hasUnreadMessages => unreadCount > 0;

  // Get the other user in a direct chat
  User? getOtherUser(String currentUserId) {
    if (!isDirectChat) return null;
    return participants.firstWhere(
      (user) => user.id != currentUserId,
      orElse: () => throw Exception('Other user not found in direct chat'),
    );
  }

  // Get display name for the chat
  String getDisplayName(String currentUserId) {
    if (isGroupChat) return name;
    
    final otherUser = getOtherUser(currentUserId);
    return otherUser?.username ?? 'Unknown User';
  }

  // Get display image for the chat
  String? getDisplayImage(String currentUserId) {
    if (isGroupChat) return groupImageUrl;
    
    final otherUser = getOtherUser(currentUserId);
    return otherUser?.profileImageUrl;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'participantIds': participantIds,
      'participants': participants.map((user) => user.toJson()).toList(),
      'lastMessage': lastMessage?.toJson(),
      'lastActivity': lastActivity.millisecondsSinceEpoch,
      'unreadCount': unreadCount,
      'groupImageUrl': groupImageUrl,
      'description': description,
      'createdBy': createdBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      name: json['name'] as String,
      type: ChatType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ChatType.direct,
      ),
      participantIds: List<String>.from(json['participantIds'] as List),
      participants: (json['participants'] as List?)
              ?.map((userJson) => User.fromJson(userJson as Map<String, dynamic>))
              .toList() ??
          [],
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      lastActivity: DateTime.fromMillisecondsSinceEpoch(json['lastActivity'] as int),
      unreadCount: json['unreadCount'] as int? ?? 0,
      groupImageUrl: json['groupImageUrl'] as String?,
      description: json['description'] as String?,
      createdBy: json['createdBy'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  @override
  String toString() {
    return 'Chat(id: $id, name: $name, type: $type, unreadCount: $unreadCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Chat && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}