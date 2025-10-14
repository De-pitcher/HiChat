import 'package:flutter/services.dart';

class SmsPlugin {
  static const MethodChannel _channel = MethodChannel('com.hichat.sms_plugin');

  // Request SMS permissions
  static Future<bool> requestPermissions() async {
    try {
      final bool result = await _channel.invokeMethod('requestPermissions');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request SMS permissions: '${e.message}'.");
      return false;
    }
  }

  // Check if SMS permissions are granted
  static Future<bool> hasPermissions() async {
    try {
      final bool result = await _channel.invokeMethod('hasPermissions');
      return result;
    } on PlatformException catch (e) {
      print("Failed to check SMS permissions: '${e.message}'.");
      return false;
    }
  }

  // Read SMS messages
  static Future<List<Map<String, dynamic>>> readSms({
    int? limit,
    String? address,
    int? startDate,
    int? endDate,
  }) async {
    try {
      final Map<String, dynamic> arguments = {};
      if (limit != null) arguments['limit'] = limit;
      if (address != null) arguments['address'] = address;
      if (startDate != null) arguments['startDate'] = startDate;
      if (endDate != null) arguments['endDate'] = endDate;

      final dynamic rawResult = await _channel.invokeMethod('readSms', arguments);
      
      // Safely convert the result
      final List<Map<String, dynamic>> result = [];
      if (rawResult is List) {
        for (final item in rawResult) {
          if (item is Map) {
            // Convert Map<Object?, Object?> to Map<String, dynamic>
            final Map<String, dynamic> convertedMap = {};
            item.forEach((key, value) {
              convertedMap[key.toString()] = value;
            });
            result.add(convertedMap);
          }
        }
      }
      
      return result;
    } on PlatformException catch (e) {
      print("Failed to read SMS: '${e.message}'.");
      return [];
    }
  }

  // Send SMS message
  static Future<bool> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final Map<String, dynamic> arguments = {
        'phoneNumber': phoneNumber,
        'message': message,
      };

      final bool result = await _channel.invokeMethod('sendSms', arguments);
      return result;
    } on PlatformException catch (e) {
      print("Failed to send SMS: '${e.message}'.");
      return false;
    }
  }

  // Get SMS conversations (grouped by phone number)
  static Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final dynamic rawResult = await _channel.invokeMethod('getConversations');
      
      // Safely convert the result
      final List<Map<String, dynamic>> result = [];
      if (rawResult is List) {
        for (final item in rawResult) {
          if (item is Map) {
            // Convert Map<Object?, Object?> to Map<String, dynamic>
            final Map<String, dynamic> convertedMap = {};
            item.forEach((key, value) {
              convertedMap[key.toString()] = value;
            });
            result.add(convertedMap);
          }
        }
      }
      
      return result;
    } on PlatformException catch (e) {
      print("Failed to get SMS conversations: '${e.message}'.");
      return [];
    }
  }
}