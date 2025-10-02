enum MessageType {
  text,
  image,
  file,
  audio,
  video,
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final String? replyToMessageId;
  final Map<String, dynamic>? metadata; // For file info, image dimensions, etc.

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    required this.timestamp,
    this.replyToMessageId,
    this.metadata,
  });

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    MessageType? type,
    MessageStatus? status,
    DateTime? timestamp,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isText => type == MessageType.text;
  bool get isImage => type == MessageType.image;
  bool get isFile => type == MessageType.file;
  bool get isAudio => type == MessageType.audio;
  bool get isVideo => type == MessageType.video;

  bool get isRead => status == MessageStatus.read;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isSent => status == MessageStatus.sent;
  bool get isSending => status == MessageStatus.sending;
  bool get isFailed => status == MessageStatus.failed;

  // Convenience getters for metadata
  String? get fileUrl => metadata?['file_url']?.toString();
  Map<String, dynamic>? get senderInfo => metadata?['sender'] as Map<String, dynamic>?;
  String? get senderUsername => senderInfo?['username']?.toString();
  String? get senderEmail => senderInfo?['email']?.toString();
  String? get senderImageUrl => senderInfo?['image_url']?.toString();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'content': content,
      'type': type.name,
      'status': status.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'replyToMessageId': replyToMessageId,
      'metadata': metadata,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    // Handle sender information
    Map<String, dynamic>? senderData;
    if (json['sender'] != null) {
      senderData = json['sender'] as Map<String, dynamic>;
    }

    // Handle file URL for media messages
    String? fileUrl;
    if (json['file'] != null) {
      fileUrl = json['file'].toString();
    }

    // Create metadata with file info if available
    Map<String, dynamic>? metadata = json['metadata'] as Map<String, dynamic>?;
    if (fileUrl != null || senderData != null) {
      metadata ??= {};
      if (fileUrl != null) {
        metadata['file_url'] = fileUrl;
      }
      if (senderData != null) {
        metadata['sender'] = senderData;
      }
    }

    return Message(
      id: (json['id'] ?? json['message_id'])?.toString() ?? '',
      chatId: (json['chatId'] ?? json['chat_id'])?.toString() ?? '',
      senderId: (json['senderId'] ?? json['sender_id'] ?? senderData?['id'])?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      type: _parseMessageType(json['type'] ?? json['message_type']),
      status: _parseMessageStatus(json['status'] ?? json['read_status']),
      timestamp: _parseTimestamp(json['timestamp'] ?? json['created_at']),
      replyToMessageId: (json['replyToMessageId'] ?? json['reply_to_message_id'])?.toString(),
      metadata: metadata,
    );
  }

  static MessageType _parseMessageType(dynamic type) {
    if (type == null) return MessageType.text;
    final typeStr = type.toString().toLowerCase();
    switch (typeStr) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'audio':
        return MessageType.audio;
      case 'video':
        return MessageType.video;
      default:
        return MessageType.text;
    }
  }

  static MessageStatus _parseMessageStatus(dynamic status) {
    if (status == null) return MessageStatus.sent;
    final statusStr = status.toString().toLowerCase();
    switch (statusStr) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    }
    
    return DateTime.now();
  }

  @override
  String toString() {
    return 'Message(id: $id, senderId: $senderId, content: $content, type: $type, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}