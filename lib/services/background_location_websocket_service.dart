import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'unified_background_websocket_service.dart';

/// Background Location WebSocket service that keeps location sharing connections alive
/// even when the app is in background or closed
class BackgroundLocationWebSocketService {
  static BackgroundLocationWebSocketService? _instance;
  
  BackgroundLocationWebSocketService._();
  
  static BackgroundLocationWebSocketService get instance {
    _instance ??= BackgroundLocationWebSocketService._();
    return _instance!;
  }

  /// Initialize the background location WebSocket service
  static Future<void> initialize() async {
    debugPrint('🚀 BackgroundLocationWebSocketService: Starting initialization...');
    
    // Use the unified background service
    await UnifiedBackgroundWebSocketService.initialize();
    
    debugPrint('✅ BackgroundLocationWebSocketService: Unified service configured successfully');
  }

  /// Connect to location WebSocket in background
  Future<bool> connectToLocationWebSocket(String userId, String username, {String? token}) async {
    try {
      debugPrint('🔄 BackgroundLocationWebSocketService: Connecting to location WebSocket for: $userId ($username)');
      
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        debugPrint('❌ Background service is not running, starting it first...');
        
        // Wait a bit longer for Android to process the runtime permissions
        debugPrint('⏳ Waiting for Android system to process location permissions...');
        await Future.delayed(const Duration(seconds: 3));
        
        await service.startService();
        
        // Wait for service to be ready
        await Future.delayed(const Duration(seconds: 2));
      }
      
      service.invoke('connect_location', {
        'user_id': userId,
        'username': username,
        if (token != null) 'token': token,
      });
      
      debugPrint('✅ BackgroundLocationWebSocketService: Connect command sent successfully');
      return true;
      
    } catch (e) {
      debugPrint('❌ BackgroundLocationWebSocketService: Failed to connect to location WebSocket: $e');
      return false;
    }
  }

  /// Disconnect from location WebSocket
  Future<void> disconnectFromLocationWebSocket() async {
    try {
      debugPrint('🔌 BackgroundLocationWebSocketService: Disconnecting from location WebSocket...');
      
      final service = FlutterBackgroundService();
      service.invoke('disconnect_location');
      
      debugPrint('✅ BackgroundLocationWebSocketService: Disconnect command sent successfully');
      
    } catch (e) {
      debugPrint('❌ BackgroundLocationWebSocketService: Failed to disconnect from location WebSocket: $e');
    }
  }

  /// Send location message
  Future<void> sendLocationMessage(Map<String, dynamic> message) async {
    final service = FlutterBackgroundService();
    service.invoke('send_location_message', {'data': message});
  }

  /// Stop the background service
  Future<void> stopService() async {
    try {
      debugPrint('🛑 BackgroundLocationWebSocketService: Stopping background service...');
      
      final service = FlutterBackgroundService();
      service.invoke('stop_service');
      
      debugPrint('✅ BackgroundLocationWebSocketService: Stop command sent successfully');
      
    } catch (e) {
      debugPrint('❌ BackgroundLocationWebSocketService: Failed to stop background service: $e');
    }
  }

  /// Request location sharing from another user
  Future<void> requestLocationSharing(String targetUserId) async {
    await sendLocationMessage({
      'type': 'request_location_sharing',
      'target_user_id': targetUserId,
      'command': 'request_location_sharing',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Send current location manually
  Future<void> shareCurrentLocation() async {
    final service = FlutterBackgroundService();
    service.invoke('share_current_location');
  }
}