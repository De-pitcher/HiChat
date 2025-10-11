import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_websocket/background_websocket_interfaces.dart';
import 'background_websocket/background_websocket_service_factory.dart';
import 'background_websocket/reusable_background_websocket_service.dart';

/// HiChat-specific message handler implementation
class HiChatMessageHandler extends BackgroundMessageHandler {
  @override
  List<String> get supportedMessageTypes => [
    'new_message',
    'user_online',
    'user_offline',
    'typing_start',
    'typing_stop',
    'message_delivered',
    'message_read',
  ];

  @override
  Future<void> handleMessage(BackgroundWebSocketMessage message) async {
    developer.log('Processing HiChat message: ${message.type}', name: 'HiChatWS');
    
    switch (message.type) {
      case 'new_message':
        await _handleNewMessage(message);
        break;
      case 'user_online':
        await _handleUserOnline(message);
        break;
      case 'user_offline':
        await _handleUserOffline(message);
        break;
      case 'typing_start':
        await _handleTypingStart(message);
        break;
      case 'typing_stop':
        await _handleTypingStop(message);
        break;
      case 'message_delivered':
        await _handleMessageDelivered(message);
        break;
      case 'message_read':
        await _handleMessageRead(message);
        break;
      default:
        developer.log('Unknown HiChat message type: ${message.type}', name: 'HiChatWS', level: 900);
    }
  }

  @override
  void onConnectionEstablished() {
    developer.log('HiChat WebSocket connected', name: 'HiChatWS');
    // Send presence update
    ReusableBackgroundWebSocketService.sendMessage({
      'type': 'presence_update',
      'status': 'online',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void onConnectionLost() {
    developer.log('HiChat WebSocket disconnected', name: 'HiChatWS');
  }

  @override
  void onMessageQueued(BackgroundWebSocketMessage message) {
    developer.log('HiChat message queued: ${message.type}', name: 'HiChatWS');
  }

  @override
  void onQueuedMessageSent(BackgroundWebSocketMessage message) {
    developer.log('HiChat queued message sent: ${message.type}', name: 'HiChatWS');
  }

  Future<void> _handleNewMessage(BackgroundWebSocketMessage message) async {
    try {
      final messageData = message.payload;
      final senderName = messageData['sender_name'] as String? ?? 'Unknown';
      final messageText = messageData['text'] as String? ?? '';
      final chatId = messageData['chat_id'] as String? ?? '';
      
      // Show notification
      await _showChatNotification(
        title: senderName,
        body: messageText,
        chatId: chatId,
      );
      
      // Store message locally if needed
      await _storeMessage(messageData);
      
    } catch (e) {
      developer.log('Error handling new message: $e', name: 'HiChatWS', level: 1000);
    }
  }

  Future<void> _handleUserOnline(BackgroundWebSocketMessage message) async {
    final userId = message.payload['user_id'] as String?;
    if (userId != null) {
      developer.log('User $userId came online', name: 'HiChatWS');
      // Update user status in cache
    }
  }

  Future<void> _handleUserOffline(BackgroundWebSocketMessage message) async {
    final userId = message.payload['user_id'] as String?;
    if (userId != null) {
      developer.log('User $userId went offline', name: 'HiChatWS');
      // Update user status in cache
    }
  }

  Future<void> _handleTypingStart(BackgroundWebSocketMessage message) async {
    final userId = message.payload['user_id'] as String?;
    final chatId = message.payload['chat_id'] as String?;
    if (userId != null && chatId != null) {
      developer.log('User $userId started typing in $chatId', name: 'HiChatWS');
      // Update typing indicators
    }
  }

  Future<void> _handleTypingStop(BackgroundWebSocketMessage message) async {
    final userId = message.payload['user_id'] as String?;
    final chatId = message.payload['chat_id'] as String?;
    if (userId != null && chatId != null) {
      developer.log('User $userId stopped typing in $chatId', name: 'HiChatWS');
      // Update typing indicators
    }
  }

  Future<void> _handleMessageDelivered(BackgroundWebSocketMessage message) async {
    final messageId = message.payload['message_id'] as String?;
    if (messageId != null) {
      developer.log('Message $messageId delivered', name: 'HiChatWS');
      // Update message status
    }
  }

  Future<void> _handleMessageRead(BackgroundWebSocketMessage message) async {
    final messageId = message.payload['message_id'] as String?;
    if (messageId != null) {
      developer.log('Message $messageId read', name: 'HiChatWS');
      // Update message status
    }
  }

  Future<void> _showChatNotification({
    required String title,
    required String body,
    required String chatId,
  }) async {
    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      
      const androidDetails = AndroidNotificationDetails(
        'hichat_messages',
        'HiChat Messages',
        channelDescription: 'Notifications for new messages',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await flutterLocalNotificationsPlugin.show(
        chatId.hashCode,
        title,
        body,
        notificationDetails,
        payload: 'chat:$chatId',
      );
      
    } catch (e) {
      developer.log('Failed to show notification: $e', name: 'HiChatWS', level: 1000);
    }
  }

  Future<void> _storeMessage(Map<String, dynamic> messageData) async {
    try {
      // Store message in local database or cache
      // This would integrate with your existing message storage system
      developer.log('Message stored locally', name: 'HiChatWS');
    } catch (e) {
      developer.log('Failed to store message: $e', name: 'HiChatWS', level: 1000);
    }
  }
}

/// HiChat-specific authentication handler
class HiChatAuthHandler extends BackgroundAuthHandler {
  @override
  bool get requiresAuth => true;

  @override
  Future<Map<String, dynamic>?> getAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final token = prefs.getString('auth_token');
      
      if (userId != null && token != null) {
        return {
          'user_id': userId,
          'token': token,
          'client_type': 'mobile',
        };
      }
      
      return null;
    } catch (e) {
      developer.log('Failed to get auth data: $e', name: 'HiChatWS', level: 1000);
      return null;
    }
  }

  @override
  Future<void> onAuthSuccess() async {
    developer.log('HiChat authentication successful', name: 'HiChatWS');
  }

  @override
  Future<void> onAuthFailure(String error) async {
    developer.log('HiChat authentication failed: $error', name: 'HiChatWS', level: 1000);
    // Handle auth failure - maybe refresh token or logout user
  }
}

/// HiChat service integration class
class HiChatBackgroundService {
  static bool _initialized = false;

  /// Initialize HiChat background WebSocket service
  static Future<void> initialize() async {
    if (_initialized) {
      developer.log('HiChat background service already initialized', name: 'HiChatWS');
      return;
    }

    try {
      await BackgroundWebSocketServiceFactory.createChatService(
        appName: 'HiChat',
        webSocketUrl: 'wss://your-hichat-server.com/ws', // Replace with your actual WebSocket URL
        messageHandler: HiChatMessageHandler(),
        authHandler: HiChatAuthHandler(),
        customConfig: {
          'appIconPath': '@mipmap/ic_launcher',
        },
      );

      _initialized = true;
      developer.log('HiChat background service initialized successfully', name: 'HiChatWS');
      
    } catch (e) {
      developer.log('Failed to initialize HiChat background service: $e', name: 'HiChatWS', level: 1000);
      rethrow;
    }
  }

  /// Start the HiChat background service
  static Future<void> start() async {
    if (!_initialized) {
      await initialize();
    }
    
    await ReusableBackgroundWebSocketService.startService();
    developer.log('HiChat background service started', name: 'HiChatWS');
  }

  /// Stop the HiChat background service
  static Future<void> stop() async {
    await ReusableBackgroundWebSocketService.stopService();
    developer.log('HiChat background service stopped', name: 'HiChatWS');
  }

  /// Connect to HiChat WebSocket
  static Future<void> connect({
    required String userId,
    required String token,
  }) async {
    await ReusableBackgroundWebSocketService.connect(
      connectionData: {
        'user_id': userId,
        'token': token,
        'client_type': 'mobile',
      },
    );
    developer.log('HiChat WebSocket connection initiated', name: 'HiChatWS');
  }

  /// Disconnect from HiChat WebSocket
  static Future<void> disconnect() async {
    await ReusableBackgroundWebSocketService.disconnect();
    developer.log('HiChat WebSocket disconnected', name: 'HiChatWS');
  }

  /// Send a chat message
  static Future<void> sendMessage({
    required String chatId,
    required String text,
    required String recipientId,
  }) async {
    await ReusableBackgroundWebSocketService.sendMessage({
      'type': 'chat_message',
      'chat_id': chatId,
      'text': text,
      'recipient_id': recipientId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Send typing indicator
  static Future<void> sendTypingIndicator({
    required String chatId,
    required bool isTyping,
  }) async {
    await ReusableBackgroundWebSocketService.sendMessage({
      'type': isTyping ? 'typing_start' : 'typing_stop',
      'chat_id': chatId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Mark message as read
  static Future<void> markMessageAsRead({
    required String messageId,
    required String chatId,
  }) async {
    await ReusableBackgroundWebSocketService.sendMessage({
      'type': 'mark_read',
      'message_id': messageId,
      'chat_id': chatId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Update user presence
  static Future<void> updatePresence({
    required String status, // 'online', 'away', 'busy', 'offline'
  }) async {
    await ReusableBackgroundWebSocketService.sendMessage({
      'type': 'presence_update',
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

/// Integration example for your main.dart
/*
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize HiChat background service
  await HiChatBackgroundService.initialize();
  
  runApp(MyApp());
}

// In your authentication flow:
Future<void> onUserLogin(String userId, String token) async {
  // Start background service
  await HiChatBackgroundService.start();
  
  // Connect to WebSocket
  await HiChatBackgroundService.connect(
    userId: userId,
    token: token,
  );
}

// In your logout flow:
Future<void> onUserLogout() async {
  // Disconnect and stop service
  await HiChatBackgroundService.disconnect();
  await HiChatBackgroundService.stop();
}

// In your chat screen:
Future<void> sendChatMessage(String text, String recipientId, String chatId) async {
  await HiChatBackgroundService.sendMessage(
    chatId: chatId,
    text: text,
    recipientId: recipientId,
  );
}
*/