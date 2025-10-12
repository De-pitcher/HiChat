import 'package:flutter/foundation.dart';
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
  User? getOtherUser(dynamic currentUserId) {
    if (!isDirectChat) return null;
    
    // If no participants, return null instead of throwing exception
    if (participants.isEmpty) return null;
    
    try {
      return participants.firstWhere(
        (user) => user.id.toString() != currentUserId.toString(),
      );
    } catch (e) {
      // If no other user found, return null instead of throwing exception
      return null;
    }
  }

  // Get the other user's ID in a direct chat
  String? getOtherUserId(dynamic currentUserId) {
    if (!isDirectChat) return null;
    
    // Try to get from participants first
    final otherUser = getOtherUser(currentUserId);
    if (otherUser != null) return otherUser.id.toString();
    
    // Fallback: try to get from participantIds
    if (participantIds.isNotEmpty) {
      try {
        return participantIds.firstWhere(
          (userId) => userId != currentUserId.toString(),
        );
      } catch (e) {
        // If no other user ID found, return null
        return null;
      }
    }
    
    return null;
  }

  // Get display name for the chat
  String getDisplayName(dynamic currentUserId) {
    if (isGroupChat) return name;
    
    final otherUser = getOtherUser(currentUserId);
    if (otherUser != null) {
      return otherUser.username;
    }
    
    // Debug logging to understand the issue
    debugPrint('Chat.getDisplayName: Failed to find other user for chat $id');
    debugPrint('  - currentUserId: $currentUserId');
    debugPrint('  - participants.length: ${participants.length}');
    debugPrint('  - participantIds: $participantIds');
    if (participants.isNotEmpty) {
      debugPrint('  - participant user IDs: ${participants.map((u) => u.id).toList()}');
    }
    debugPrint('  - chat.name: "$name"');
    
    // Fallback: if no participants or other user not found, use chat name or default
    if (name.isNotEmpty) return name;
    return 'New Chat';
  }

  // Get display image for the chat
  String? getDisplayImage(dynamic currentUserId) {
    if (isGroupChat) return groupImageUrl;
    
    final otherUser = getOtherUser(currentUserId);
    if (otherUser == null) {
      debugPrint('Chat.getDisplayImage: Failed to find other user for chat $id');
    }
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
    final chatType = _parseChatType(json['type'] ?? json['chat_type']);
    final participants = _parseParticipants(json['participants']);
    
    // For direct chats, try to derive name from participants if not provided
    String chatName = json['name']?.toString() ?? json['chat_name']?.toString() ?? '';
    if (chatName.isEmpty && chatType == ChatType.direct && participants.isNotEmpty) {
      // Try to use the first participant's username as the chat name
      chatName = participants.first.username;
      debugPrint('Chat.fromJson: Derived direct chat name from participant: "$chatName"');
    }
    if (chatName.isEmpty) {
      chatName = 'Chat'; // Final fallback
    }
    
    return Chat(
      id: (json['id'] ?? json['chat_id'])?.toString() ?? '',
      name: chatName,
      type: chatType,
      participantIds: _parseParticipantIds(json['participantIds'] ?? json['participant_ids'] ?? json['participants']),
      participants: participants,
      lastMessage: _parseLastMessage(json['lastMessage'] ?? json['last_message']),
      lastActivity: _parseDateTime(json['lastActivity'] ?? json['last_activity'] ?? json['updated_at']),
      unreadCount: (json['unreadCount'] ?? json['unread_count'] ?? 0) as int,
      groupImageUrl: json['groupImageUrl']?.toString() ?? json['group_image_url']?.toString(),
      description: json['description']?.toString(),
      createdBy: (json['createdBy'] ?? json['created_by'])?.toString(),
      createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']),
    );
  }

  static ChatType _parseChatType(dynamic type) {
    if (type == null) return ChatType.direct;
    final typeStr = type.toString().toLowerCase();
    return typeStr == 'group' ? ChatType.group : ChatType.direct;
  }

  static List<String> _parseParticipantIds(dynamic participants) {
    if (participants == null) return [];
    
    if (participants is List) {
      return participants.map((p) {
        if (p is Map<String, dynamic>) {
          return (p['id'] ?? p['user_id'])?.toString() ?? '';
        }
        return p.toString();
      }).where((id) => id.isNotEmpty).toList();
    }
    
    return [];
  }

  static List<User> _parseParticipants(dynamic participants) {
    if (participants == null) return [];
    
    if (participants is List) {
      return participants
          .whereType<Map<String, dynamic>>()
          .map((p) => User.fromJson(p))
          .toList();
    }
    
    return [];
  }

  static Message? _parseLastMessage(dynamic lastMessage) {
    if (lastMessage == null) return null;
    
    if (lastMessage is Map<String, dynamic>) {
      try {
        return Message.fromJson(lastMessage);
      } catch (e) {
        return null;
      }
    }
    
    return null;
  }

  static DateTime _parseDateTime(dynamic dateTime) {
    if (dateTime == null) return DateTime.now();
    
    if (dateTime is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateTime);
    } else if (dateTime is String) {
      return DateTime.tryParse(dateTime) ?? DateTime.now();
    }
    
    return DateTime.now();
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