import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'unified_background_websocket_service.dart';

/// Background Media WebSocket service that keeps media upload connections alive
/// even when the app is in background or closed
class BackgroundMediaWebSocketService {
  static BackgroundMediaWebSocketService? _instance;
  
  BackgroundMediaWebSocketService._();
  
  static BackgroundMediaWebSocketService get instance {
    _instance ??= BackgroundMediaWebSocketService._();
    return _instance!;
  }

  /// Initialize the background media WebSocket service
  static Future<void> initialize() async {
    debugPrint('🚀 BackgroundMediaWebSocketService: Starting initialization...');
    
    // Use the unified background service
    await UnifiedBackgroundWebSocketService.initialize();
    
    debugPrint('✅ BackgroundMediaWebSocketService: Unified service configured successfully');
  }

  /// Connect to media WebSocket in background
  Future<bool> connectToMediaWebSocket(String userId, String username, {String? token}) async {
    try {
      debugPrint('🔄 BackgroundMediaWebSocketService: Connecting to media WebSocket for: $userId ($username)');
      
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        debugPrint('❌ Background service is not running, starting it first...');
        await service.startService();
        
        // CRITICAL FIX: Wait MUCH longer for service to fully initialize
        // Background isolate needs time to:
        // 1. Start Flutter engine
        // 2. Load all Dart code  
        // 3. Call onUnifiedBackgroundStart (the pragma entry point)
        // 4. Create UnifiedWebSocketManager
        // 5. Register ALL event listeners
        debugPrint('⏳ BackgroundMediaWebSocketService: Waiting 5 seconds for full service startup, Flutter engine load, and listener registration...');
        await Future.delayed(const Duration(seconds: 5));
        debugPrint('✅ BackgroundMediaWebSocketService: Full service initialization delay complete');
      } else {
        // Service already running, but wait for listener registration
        debugPrint('⏳ BackgroundMediaWebSocketService: Service already running, waiting 2 seconds for listener registration...');
        await Future.delayed(const Duration(seconds: 2));
        debugPrint('✅ BackgroundMediaWebSocketService: Listener registration delay complete');
      }
      
      debugPrint('📤 BackgroundMediaWebSocketService: Invoking connect_media event with params - userId: $userId, username: $username, token: ${token != null ? 'present' : 'null'}');
      service.invoke('connect_media', {
        'user_id': userId,
        'username': username,
        if (token != null) 'token': token,
      });
      debugPrint('✅ BackgroundMediaWebSocketService: Connect command invoked successfully');
      
      // Add post-invocation wait to ensure event reaches the listener
      debugPrint('⏳ BackgroundMediaWebSocketService: Waiting 2 seconds for background isolate to receive and process connect_media...');
      await Future.delayed(const Duration(seconds: 2));
      debugPrint('✅ BackgroundMediaWebSocketService: Background processing should be complete');
      
      return true;
      
    } catch (e, st) {
      debugPrint('❌ BackgroundMediaWebSocketService: Failed to connect to media WebSocket: $e');
      debugPrint('❌ BackgroundMediaWebSocketService: Stack trace: $st');
      return false;
    }
  }

  /// Disconnect from media WebSocket
  Future<void> disconnectFromMediaWebSocket() async {
    try {
      debugPrint('🔌 BackgroundMediaWebSocketService: Disconnecting from media WebSocket...');
      
      final service = FlutterBackgroundService();
      service.invoke('disconnect_media');
      
      debugPrint('✅ BackgroundMediaWebSocketService: Disconnect command sent successfully');
      
    } catch (e) {
      debugPrint('❌ BackgroundMediaWebSocketService: Failed to disconnect from media WebSocket: $e');
    }
  }

  /// Send media message
  Future<void> sendMediaMessage(Map<String, dynamic> message) async {
    final service = FlutterBackgroundService();
    service.invoke('send_media_message', {'data': message});
  }

  /// Stop the background service
  Future<void> stopService() async {
    try {
      debugPrint('🛑 BackgroundMediaWebSocketService: Stopping background service...');
      
      final service = FlutterBackgroundService();
      service.invoke('stop_service');
      
      debugPrint('✅ BackgroundMediaWebSocketService: Stop command sent successfully');
      
    } catch (e) {
      debugPrint('❌ BackgroundMediaWebSocketService: Failed to stop background service: $e');
    }
  }

  /// Upload media file
  Future<void> uploadMedia(String filePath, String messageId, String recipientId) async {
    await sendMediaMessage({
      'type': 'media_upload',
      'file_path': filePath,
      'message_id': messageId,
      'recipient_id': recipientId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Request media download
  Future<void> downloadMedia(String mediaUrl, String messageId) async {
    await sendMediaMessage({
      'type': 'media_download',
      'media_url': mediaUrl,
      'message_id': messageId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}