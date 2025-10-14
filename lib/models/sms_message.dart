/// SMS Message model for handling device SMS messages
/// Compatible with custom SMS plugin and API upload functionality

enum SMSType {
  inbox,    // Received SMS
  sent,     // Sent SMS  
  draft,    // Draft SMS
  outbox,   // Outbox SMS (pending send)
  failed,   // Failed SMS
}

enum SMSStatus {
  none,
  complete,
  pending,
  failed,
}

class SMSMessage {
  final int? id;                    // Device SMS ID
  final String address;             // Phone number (sender/recipient)
  final String body;                // SMS content/text
  final DateTime date;              // SMS timestamp
  final SMSType type;               // Message type (inbox, sent, etc.)
  final SMSStatus status;           // Delivery status
  final int? threadId;              // Conversation thread ID
  final bool read;                  // Whether message has been read
  final String? serviceCenterAddress; // SMS service center
  final String? subject;            // Message subject (if any)

  const SMSMessage({
    this.id,
    required this.address,
    required this.body,
    required this.date,
    this.type = SMSType.inbox,
    this.status = SMSStatus.complete,
    this.threadId,
    this.read = true,
    this.serviceCenterAddress,
    this.subject,
  });

  /// Create SMSMessage from our custom SMS plugin data
  factory SMSMessage.fromPluginData(Map<String, dynamic> data) {
    try {
      print('SMSMessage.fromPluginData: Converting data: ${data.toString()}');
      
      // Safe type conversion with fallbacks
      final id = data['id'] != null ? int.tryParse(data['id'].toString()) : null;
      final address = data['address']?.toString() ?? '';
      final body = data['body']?.toString() ?? '';
      final dateMs = data['date'] != null ? int.tryParse(data['date'].toString()) ?? 0 : 0;
      final type = data['type'] != null ? int.tryParse(data['type'].toString()) ?? 1 : 1;
      final threadId = data['threadId'] != null ? int.tryParse(data['threadId'].toString()) : null;
      final read = data['read'] == true || data['read']?.toString() == 'true';
      
      print('SMSMessage.fromPluginData: Parsed - ID:$id, Address:$address, Body:${body.length} chars, Date:$dateMs, Type:$type, ThreadID:$threadId, Read:$read');
      
      final smsMessage = SMSMessage(
        id: id,
        address: address,
        body: body,
        date: DateTime.fromMillisecondsSinceEpoch(dateMs),
        type: _mapPluginType(type),
        status: SMSStatus.complete,
        threadId: threadId,
        read: read,
        serviceCenterAddress: null,
        subject: null,
      );
      
      print('SMSMessage.fromPluginData: Successfully created SMSMessage - Address:${smsMessage.address}, Type:${smsMessage.type}, Date:${smsMessage.date}');
      return smsMessage;
    } catch (e, stackTrace) {
      print('SMSMessage.fromPluginData: Error converting data: $e');
      print('SMSMessage.fromPluginData: Stack trace: $stackTrace');
      print('SMSMessage.fromPluginData: Failed data: ${data.toString()}');
      rethrow;
    }
  }

  /// Create SMSMessage from JSON (for API responses)
  factory SMSMessage.fromJson(Map<String, dynamic> json) {
    return SMSMessage(
      id: json['id'] as int?,
      address: json['address'] as String,
      body: json['body'] as String,
      date: DateTime.parse(json['date'] as String),
      type: SMSType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SMSType.inbox,
      ),
      status: SMSStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SMSStatus.complete,
      ),
      threadId: json['thread_id'] as int?,
      read: json['read'] as bool? ?? true,
      serviceCenterAddress: json['service_center_address'] as String?,
      subject: json['subject'] as String?,
    );
  }

  /// Convert SMSMessage to JSON (for API requests)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'address': address,
      'body': body,
      'date': date.toIso8601String(),
      'type': type.name,
      'status': status.name,
      'thread_id': threadId,
      'read': read,
      'service_center_address': serviceCenterAddress,
      'subject': subject,
    };
  }

  /// Create a copy of SMSMessage with updated fields
  SMSMessage copyWith({
    int? id,
    String? address,
    String? body,
    DateTime? date,
    SMSType? type,
    SMSStatus? status,
    int? threadId,
    bool? read,
    String? serviceCenterAddress,
    String? subject,
  }) {
    return SMSMessage(
      id: id ?? this.id,
      address: address ?? this.address,
      body: body ?? this.body,
      date: date ?? this.date,
      type: type ?? this.type,
      status: status ?? this.status,
      threadId: threadId ?? this.threadId,
      read: read ?? this.read,
      serviceCenterAddress: serviceCenterAddress ?? this.serviceCenterAddress,
      subject: subject ?? this.subject,
    );
  }

  /// Check if this is a received message
  bool get isReceived => type == SMSType.inbox;

  /// Check if this is a sent message  
  bool get isSent => type == SMSType.sent;

  /// Check if this is a draft message
  bool get isDraft => type == SMSType.draft;

  /// Get formatted phone number for display
  String get formattedAddress {
    // Remove any non-digit characters except +
    String cleaned = address.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Format for display if it's a valid phone number
    if (cleaned.length >= 10) {
      return cleaned;
    }
    
    return address; // Return original if formatting fails
  }

  /// Get conversation partner name (for display)
  String get contactName {
    // This would typically be resolved from contacts
    // For now, return the formatted address
    return formattedAddress;
  }

  /// Convert to API-compatible SMSData format
  Map<String, dynamic> toApiData() {
    return {
      'address': address,
      'body': body,
    };
  }

  @override
  String toString() {
    return 'SMSMessage(id: $id, address: $address, body: ${body.length > 50 ? '${body.substring(0, 50)}...' : body}, date: $date, type: $type, read: $read)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SMSMessage &&
        other.id == id &&
        other.address == address &&
        other.body == body &&
        other.date == date &&
        other.type == type;
  }

  @override
  int get hashCode {
    return Object.hash(id, address, body, date, type);
  }

  /// Helper method to map SMS plugin message types to our enum
  static SMSType _mapPluginType(int type) {
    // SMS plugin uses Android Telephony.Sms constants
    // 1 = inbox, 2 = sent, 3 = draft, 4 = outbox, 5 = failed
    switch (type) {
      case 1:
        return SMSType.inbox;
      case 2:
        return SMSType.sent;
      case 3:
        return SMSType.draft;
      case 4:
        return SMSType.outbox;
      case 5:
        return SMSType.failed;
      default:
        return SMSType.inbox;
    }
  }
}

/// SMS Conversation model for grouping messages by contact
class SMSConversation {
  final String address;           // Phone number
  final String contactName;      // Contact display name
  final List<SMSMessage> messages;
  final SMSMessage? lastMessage;
  final int unreadCount;
  final DateTime? lastMessageDate;

  const SMSConversation({
    required this.address,
    required this.contactName,
    required this.messages,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastMessageDate,
  });

  /// Create conversation from list of SMS messages
  factory SMSConversation.fromMessages({
    required String address,
    required String contactName,
    required List<SMSMessage> messages,
  }) {
    // Sort messages by date (newest first)
    final sortedMessages = List<SMSMessage>.from(messages)
      ..sort((a, b) => b.date.compareTo(a.date));

    final lastMessage = sortedMessages.isNotEmpty ? sortedMessages.first : null;
    final unreadCount = sortedMessages.where((msg) => !msg.read && msg.isReceived).length;

    return SMSConversation(
      address: address,
      contactName: contactName,
      messages: sortedMessages,
      lastMessage: lastMessage,
      unreadCount: unreadCount,
      lastMessageDate: lastMessage?.date,
    );
  }

  /// Get formatted last message preview
  String get lastMessagePreview {
    if (lastMessage == null) return 'No messages';
    
    final preview = lastMessage!.body.replaceAll('\n', ' ').trim();
    return preview.length > 100 ? '${preview.substring(0, 100)}...' : preview;
  }

  /// Check if conversation has unread messages
  bool get hasUnreadMessages => unreadCount > 0;

  @override
  String toString() {
    return 'SMSConversation(address: $address, contactName: $contactName, messageCount: ${messages.length}, unreadCount: $unreadCount)';
  }
}