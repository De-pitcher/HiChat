/// Models for bulk upload endpoints:
/// - Contacts bulk upload (POST /api/contacts/bulk-create/)
/// - Call logs bulk upload (POST /api/calls/bulk-create/)
/// - SMS messages bulk upload (POST /api/sms/bulk-create/)

/// Response model for bulk upload operations
class BulkUploadResponse {
  final int created;
  final int skipped;
  final int totalProcessed;
  final String message;

  const BulkUploadResponse({
    required this.created,
    required this.skipped,
    required this.totalProcessed,
    required this.message,
  });

  factory BulkUploadResponse.fromJson(Map<String, dynamic> json) {
    return BulkUploadResponse(
      created: json['created'] as int,
      skipped: json['skipped'] as int,
      totalProcessed: json['total_processed'] as int,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'created': created,
      'skipped': skipped,
      'total_processed': totalProcessed,
      'message': message,
    };
  }

  @override
  String toString() {
    return 'BulkUploadResponse(created: $created, skipped: $skipped, totalProcessed: $totalProcessed, message: $message)';
  }
}

/// Contact data model for bulk upload
class ContactData {
  final String contactId;
  final String name;
  final String number;

  const ContactData({
    required this.contactId,
    required this.name,
    required this.number,
  });

  factory ContactData.fromJson(Map<String, dynamic> json) {
    return ContactData(
      contactId: json['contact_id'] as String,
      name: json['name'] as String,
      number: json['number'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contact_id': contactId,
      'name': name,
      'number': number,
    };
  }

  @override
  String toString() {
    return 'ContactData(contactId: $contactId, name: $name, number: $number)';
  }
}

/// Call log data model for bulk upload
class CallLogData {
  final String number;
  final String callType; // "1" = Audio, "2" = Video
  final String direction; // "OUTGOING" or "INCOMING"
  final String date; // Timestamp in milliseconds (string format)
  final String duration; // Call duration in seconds (string format)

  const CallLogData({
    required this.number,
    required this.callType,
    required this.direction,
    required this.date,
    required this.duration,
  });

  factory CallLogData.fromJson(Map<String, dynamic> json) {
    return CallLogData(
      number: json['number'] as String,
      callType: json['call_type'] as String,
      direction: json['direction'] as String,
      date: json['date'] as String,
      duration: json['duration'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'call_type': callType,
      'direction': direction,
      'date': date,
      'duration': duration,
    };
  }

  @override
  String toString() {
    return 'CallLogData(number: $number, callType: $callType, direction: $direction, date: $date, duration: $duration)';
  }
}

/// SMS data model for bulk upload
class SMSData {
  final String address;
  final String body;

  const SMSData({
    required this.address,
    required this.body,
  });

  factory SMSData.fromJson(Map<String, dynamic> json) {
    return SMSData(
      address: json['address'] as String,
      body: json['body'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'body': body,
    };
  }

  @override
  String toString() {
    return 'SMSData(address: $address, body: $body)';
  }
}

/// Contacts bulk upload request model
class ContactsBulkUploadRequest {
  final String owner;
  final List<ContactData> contactList;

  const ContactsBulkUploadRequest({
    required this.owner,
    required this.contactList,
  });

  factory ContactsBulkUploadRequest.fromJson(Map<String, dynamic> json) {
    return ContactsBulkUploadRequest(
      owner: json['owner'] as String,
      contactList: (json['contact_list'] as List<dynamic>)
          .map((item) => ContactData.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'owner': owner,
      'contact_list': contactList.map((contact) => contact.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'ContactsBulkUploadRequest(owner: $owner, contactList: ${contactList.length} contacts)';
  }
}

/// Call logs bulk upload request model
class CallLogsBulkUploadRequest {
  final String owner;
  final List<CallLogData> callList;

  const CallLogsBulkUploadRequest({
    required this.owner,
    required this.callList,
  });

  factory CallLogsBulkUploadRequest.fromJson(Map<String, dynamic> json) {
    return CallLogsBulkUploadRequest(
      owner: json['owner'] as String,
      callList: (json['call_list'] as List<dynamic>)
          .map((item) => CallLogData.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'owner': owner,
      'call_list': callList.map((call) => call.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'CallLogsBulkUploadRequest(owner: $owner, callList: ${callList.length} calls)';
  }
}

/// SMS bulk upload request model
class SMSBulkUploadRequest {
  final String owner;
  final List<SMSData> smsList;

  const SMSBulkUploadRequest({
    required this.owner,
    required this.smsList,
  });

  factory SMSBulkUploadRequest.fromJson(Map<String, dynamic> json) {
    return SMSBulkUploadRequest(
      owner: json['owner'] as String,
      smsList: (json['sms_list'] as List<dynamic>)
          .map((item) => SMSData.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'owner': owner,
      'sms_list': smsList.map((sms) => sms.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'SMSBulkUploadRequest(owner: $owner, smsList: ${smsList.length} messages)';
  }
}