import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../plugins/sms_plugin.dart';
import '../models/sms_message.dart';

/// Service for handling SMS operations including reading, sending, and managing SMS messages
/// Uses android_sms_reader for reading and flutter_sms for sending SMS messages
class SMSService extends ChangeNotifier {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();  // SMS data and state
  List<SMSMessage> _smsMessages = [];
  List<SMSConversation> _conversations = [];
  bool _isLoading = false;
  bool _hasPermission = false;
  String? _error;

  // Getters
  List<SMSMessage> get smsMessages => List.from(_smsMessages);
  List<SMSConversation> get conversations => List.from(_conversations);
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String? get error => _error;

  /// Initialize the SMS service and check permissions
  Future<void> initialize() async {
    debugPrint('SMSService: Initializing SMS service...');
    try {
      await _checkPermissions();
      if (_hasPermission) {
        // Load SMS messages without any limit to get all data
        await loadSMSMessages(); // No limit parameter = load all SMS messages
      }
    } catch (e) {
      debugPrint('SMSService: Error during initialization: $e');
      _error = 'Failed to initialize SMS service: $e';
      notifyListeners();
    }
  }

  /// Check and request SMS permissions
  Future<bool> _checkPermissions() async {
    try {
      debugPrint('SMSService: Checking SMS permissions...');
      
      // Check if permissions are already granted using our plugin
      _hasPermission = await SmsPlugin.hasPermissions();
      
      if (_hasPermission) {
        debugPrint('SMSService: SMS permission already granted');
        return true;
      }

      // Request permissions using our plugin
      debugPrint('SMSService: Requesting SMS permission...');
      _hasPermission = await SmsPlugin.requestPermissions();
      debugPrint('SMSService: Permission request result: $_hasPermission');
      
      if (!_hasPermission) {
        _error = 'SMS permissions not granted. Please enable them in app settings.';
        notifyListeners();
      }

      return _hasPermission;
    } catch (e) {
      debugPrint('SMSService: Error checking permissions: $e');
      _error = 'Failed to check SMS permissions: $e';
      _hasPermission = false;
      notifyListeners();
      return false;
    }
  }

  /// Load SMS messages from device using sms_advanced package
  Future<void> loadSMSMessages({int? limit, bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) {
      debugPrint('SMSService: Already loading SMS messages, skipping...');
      return;
    }

    debugPrint('SMSService: Loading SMS messages from device...');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Check permissions first
      if (!_hasPermission) {
        final hasPermission = await _checkPermissions();
        if (!hasPermission) {
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      // Query all SMS messages from device using our SMS plugin
      debugPrint('SMSService: Querying SMS messages from device with limit: $limit');
      
      // Fetch all SMS messages (inbox + sent) using our plugin
      final dynamic rawMessages = await SmsPlugin.readSms(
        limit: limit,
      );
      
      debugPrint('SMSService: Raw SMS plugin returned: ${rawMessages.runtimeType}');
      if (rawMessages is List) {
        debugPrint('SMSService: Raw SMS list length: ${rawMessages.length}');
      }
      
      // Safely cast the raw response
      final List<Map<String, dynamic>> deviceMessages = [];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is Map) {
            // Convert Map<Object?, Object?> to Map<String, dynamic>
            final Map<String, dynamic> convertedMap = {};
            item.forEach((key, value) {
              convertedMap[key.toString()] = value;
            });
            deviceMessages.add(convertedMap);
          }
        }
      }
      
      debugPrint('SMSService: Found ${deviceMessages.length} SMS messages on device');

      // Log first few raw messages for debugging
      for (int i = 0; i < deviceMessages.length.clamp(0, 5); i++) {
        final msg = deviceMessages[i];
        debugPrint('SMSService: Raw SMS #${i + 1}: ${msg.toString()}');
      }
      
      // Check if all messages have unique addresses
      final uniqueAddresses = <String>{};
      for (final msg in deviceMessages) {
        final address = msg['address']?.toString() ?? '';
        if (address.isNotEmpty) {
          uniqueAddresses.add(address);
        }
      }
      debugPrint('SMSService: Found ${uniqueAddresses.length} unique addresses in ${deviceMessages.length} messages');
      debugPrint('SMSService: Unique addresses: ${uniqueAddresses.toList()}');

      // Convert to our SMS message format
      debugPrint('SMSService: Converting ${deviceMessages.length} SMS messages to SMSMessage objects...');
      final List<SMSMessage?> convertedMessages = deviceMessages
          .map((msgData) {
            try {
              final smsMessage = SMSMessage.fromPluginData(msgData);
              return smsMessage;
            } catch (e) {
              debugPrint('SMSService: Error converting SMS message: $e');
              debugPrint('SMSService: Raw data that failed: ${msgData.toString()}');
              return null;
            }
          })
          .toList();
      
      debugPrint('SMSService: Converted ${convertedMessages.length} messages, checking for nulls...');
      final nullCount = convertedMessages.where((msg) => msg == null).length;
      debugPrint('SMSService: Found $nullCount null messages after conversion');
      
      // Filter and check what gets removed
      final validMessages = convertedMessages
          .where((msg) => msg != null)
          .cast<SMSMessage>()
          .toList();
      
      debugPrint('SMSService: ${validMessages.length} non-null messages');
      
      final nonEmptyBodyMessages = validMessages
          .where((msg) => msg.body.isNotEmpty)
          .toList();
      
      debugPrint('SMSService: ${nonEmptyBodyMessages.length} messages with non-empty bodies (removed ${validMessages.length - nonEmptyBodyMessages.length} empty body messages)');
      
      _smsMessages = nonEmptyBodyMessages
          .where((msg) => msg.address.isNotEmpty)
          .toList();
      
      debugPrint('SMSService: ${_smsMessages.length} messages with non-empty addresses (removed ${nonEmptyBodyMessages.length - _smsMessages.length} empty address messages)');

      // Sort by date (newest first)
      _smsMessages.sort((a, b) => b.date.compareTo(a.date));

      // Apply limit if specified
      if (limit != null && _smsMessages.length > limit) {
        _smsMessages = _smsMessages.take(limit).toList();
      }

      // Group messages into conversations
      _groupMessagesIntoConversations();

      debugPrint('SMSService: Processed ${_smsMessages.length} SMS messages into ${_conversations.length} conversations');

      _isLoading = false;
      notifyListeners();

    } catch (e) {
      debugPrint('SMSService: Error loading SMS messages: $e');
      _error = 'Failed to load SMS messages: $e';
      _isLoading = false;
      notifyListeners();
    }
  }





  /// Group SMS messages into conversations by phone number
  void _groupMessagesIntoConversations() {
    debugPrint('SMSService: Grouping ${_smsMessages.length} messages into conversations...');
    
    final Map<String, List<SMSMessage>> messagesByAddress = {};
    
    // Group messages by address (phone number)
    for (final message in _smsMessages) {
      final address = message.formattedAddress;
      if (!messagesByAddress.containsKey(address)) {
        messagesByAddress[address] = [];
        debugPrint('SMSService: New conversation for address: $address');
      }
      messagesByAddress[address]!.add(message);
    }

    debugPrint('SMSService: Found ${messagesByAddress.keys.length} unique addresses/conversations');
    
    // Debug: Show how many messages per conversation (first 10 only)
    int counter = 0;
    messagesByAddress.forEach((address, messages) {
      if (counter < 10) {
        debugPrint('SMSService: Conversation $address has ${messages.length} messages');
      }
      counter++;
    });
    
    if (messagesByAddress.length > 10) {
      debugPrint('SMSService: ... and ${messagesByAddress.length - 10} more conversations');
    }

    // Create conversation objects
    _conversations = messagesByAddress.entries.map((entry) {
      final address = entry.key;
      final messages = entry.value;
      
      // For now, use the phone number as the contact name
      // In a real app, you'd resolve this from the contacts
      final contactName = _getContactNameForAddress(address);
      
      return SMSConversation.fromMessages(
        address: address,
        contactName: contactName,
        messages: messages,
      );
    }).toList();

    // Sort conversations by last message date
    _conversations.sort((a, b) {
      final aDate = a.lastMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    debugPrint('SMSService: Created ${_conversations.length} conversations');
  }

  /// Get contact name for a phone number (placeholder implementation)
  String _getContactNameForAddress(String address) {
    // In a real implementation, you would:
    // 1. Query the contacts database for this phone number
    // 2. Return the contact's display name if found
    // 3. Format the phone number nicely if no contact found
    
    // For now, just return the formatted phone number
    return address;
  }

  /// Send an SMS message
  Future<bool> sendSMS({
    required String address,
    required String message,
  }) async {
    debugPrint('SMSService: Sending SMS to $address...');
    
    try {
      // Check permissions
      if (!_hasPermission) {
        final hasPermission = await _checkPermissions();
        if (!hasPermission) {
          throw Exception('SMS permission not granted');
        }
      }

      // Send SMS using our SMS plugin
      final bool result = await SmsPlugin.sendSms(
        phoneNumber: address,
        message: message,
      );

      debugPrint('SMSService: SMS sent successfully to $address - Result: $result');
      
      if (!result) {
        throw Exception('Failed to send SMS');
      }
      
      // Add sent message to our local list
      final sentMessage = SMSMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        address: address,
        body: message,
        date: DateTime.now(),
        type: SMSType.sent,
        read: true,
      );

      _smsMessages.insert(0, sentMessage);
      _groupMessagesIntoConversations();
      
      return true;
    } catch (e) {
      debugPrint('SMSService: Error sending SMS: $e');
      _error = 'Failed to send SMS: $e';
      notifyListeners();
      return false;
    }
  }

  /// Get messages for a specific conversation
  List<SMSMessage> getMessagesForAddress(String address) {
    return _smsMessages
        .where((msg) => msg.formattedAddress == address)
        .toList();
  }

  /// Get conversation for a specific address
  SMSConversation? getConversationForAddress(String address) {
    return _conversations
        .cast<SMSConversation?>()
        .firstWhere(
          (conv) => conv?.address == address,
          orElse: () => null,
        );
  }

  /// Mark messages as read for a specific address
  Future<void> markMessagesAsRead(String address) async {
    debugPrint('SMSService: Marking messages as read for $address');
    
    try {
      // Find messages for this address that are unread
      final unreadMessages = _smsMessages
          .where((msg) => 
              msg.formattedAddress == address && 
              !msg.read && 
              msg.isReceived)
          .toList();

      if (unreadMessages.isEmpty) {
        debugPrint('SMSService: No unread messages found for $address');
        return;
      }

      // Mark messages as read in our local list
      for (final message in unreadMessages) {
        final index = _smsMessages.indexOf(message);
        if (index != -1) {
          _smsMessages[index] = message.copyWith(read: true);
        }
      }

      // Update conversations
      _groupMessagesIntoConversations();
      
      debugPrint('SMSService: Marked ${unreadMessages.length} messages as read for $address');
      notifyListeners();

    } catch (e) {
      debugPrint('SMSService: Error marking messages as read: $e');
      _error = 'Failed to mark messages as read: $e';
      notifyListeners();
    }
  }

  /// Get total unread SMS count
  int get totalUnreadCount {
    return _conversations
        .map((conv) => conv.unreadCount)
        .fold(0, (sum, count) => sum + count);
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Show permission dialog helper
  void showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('SMS Permission Required'),
          content: const Text(
            'This app needs access to your SMS messages to display and manage them.\n\n'
            'Please enable SMS permission in your device settings:\n'
            'Settings > Apps > HiChat > Permissions > SMS',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  /// Convert SMS messages to API format for bulk upload
  List<Map<String, dynamic>> getMessagesForAPIUpload() {
    return _smsMessages
        .map((msg) => msg.toApiData())
        .toList();
  }

  /// Refresh SMS messages (wrapper for loadSMSMessages with force refresh)
  Future<void> refresh() async {
    await loadSMSMessages(forceRefresh: true);
  }

  @override
  void dispose() {
    debugPrint('SMSService: Disposing SMS service');
    super.dispose();
  }
}