import 'user.dart';

/// Represents the reply context for a message
class ReplyMessage {
  final String id;
  final String content;
  final User sender;
  final String? fileUrl;
  final String messageType;

  const ReplyMessage({
    required this.id,
    required this.content,
    required this.sender,
    this.fileUrl,
    this.messageType = 'text',
  });

  /// Create ReplyMessage from JSON (typically from backend)
  factory ReplyMessage.fromJson(Map<String, dynamic> json) {
    return ReplyMessage(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      sender: User.fromJson(json['sender'] as Map<String, dynamic>),
      fileUrl: json['file_url']?.toString(),
      messageType: json['message_type']?.toString() ?? 'text',
    );
  }

  /// Convert to JSON for sending to backend
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'sender': sender.toJson(),
      'file_url': fileUrl,
      'message_type': messageType,
    };
  }

  /// Create ReplyMessage from a regular Message
  factory ReplyMessage.fromMessage(Map<String, dynamic> messageData) {
    final senderData = messageData['sender'] as Map<String, dynamic>?;
    
    return ReplyMessage(
      id: messageData['id']?.toString() ?? '',
      content: messageData['content']?.toString() ?? '',
      sender: senderData != null 
          ? User.fromJson(senderData)
          : User(
              id: int.tryParse(messageData['sender_id']?.toString() ?? '0') ?? 0,
              username: messageData['sender_username']?.toString() ?? 'Unknown',
              email: messageData['sender_email']?.toString() ?? '',
              createdAt: DateTime.now(),
            ),
      fileUrl: messageData['file_url']?.toString() ?? messageData['file']?.toString(),
      messageType: messageData['message_type']?.toString() ?? 'text',
    );
  }

  /// Get display text for the reply preview
  String get displayText {
    switch (messageType.toLowerCase()) {
      case 'image':
        return '📷 Image';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎵 Audio';
      case 'file':
        return '📎 File';
      default:
        return content.length > 50 ? '${content.substring(0, 50)}...' : content;
    }
  }

  /// Get icon for the message type
  String get typeIcon {
    switch (messageType.toLowerCase()) {
      case 'image':
        return '📷';
      case 'video':
        return '🎥';
      case 'audio':
        return '🎵';
      case 'file':
        return '📎';
      default:
        return '';
    }
  }

  @override
  String toString() {
    return 'ReplyMessage(id: $id, sender: ${sender.username}, content: ${content.length > 30 ? '${content.substring(0, 30)}...' : content})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReplyMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}