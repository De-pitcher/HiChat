import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'background_websocket_interfaces.dart';

/// Default SharedPreferences implementation of BackgroundServiceStorage
class SharedPreferencesBackgroundStorage implements BackgroundServiceStorage {
  @override
  Future<String?> getConnectionInfo(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      debugPrint('SharedPreferencesBackgroundStorage: Error getting $key: $e');
      return null;
    }
  }

  @override
  Future<void> setConnectionInfo(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('SharedPreferencesBackgroundStorage: Error setting $key: $e');
    }
  }

  @override
  Future<void> clearConnectionInfo(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (e) {
      debugPrint('SharedPreferencesBackgroundStorage: Error clearing $key: $e');
    }
  }

  @override
  Future<void> clearAllConnectionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('websocket_') || key.startsWith('background_ws_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('SharedPreferencesBackgroundStorage: Error clearing all: $e');
    }
  }

  @override
  Future<bool> hasConnectionInfo(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(key);
    } catch (e) {
      debugPrint('SharedPreferencesBackgroundStorage: Error checking $key: $e');
      return false;
    }
  }
}

/// Default Flutter Local Notifications implementation
class FlutterLocalNotificationHandler implements BackgroundNotificationHandler {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  String _channelId = '';
  String _channelName = '';

  @override
  Future<void> initialize(String channelId, String channelName, String appIconPath) async {
    _channelId = channelId;
    _channelName = channelName;
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings);
    
    // Create notification channel for Android
    final androidChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: 'Background WebSocket notifications',
      importance: Importance.low,
      showBadge: false,
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? id,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Background WebSocket notifications',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(
        id?.hashCode ?? 0,
        title,
        body,
        notificationDetails,
        payload: id,
      );
    } catch (e) {
      debugPrint('FlutterLocalNotificationHandler: Failed to show notification: $e');
    }
  }

  @override
  Future<void> clearAllNotifications() async {
    try {
      await _notifications.cancelAll();
    } catch (e) {
      debugPrint('FlutterLocalNotificationHandler: Failed to clear all notifications: $e');
    }
  }

  @override
  Future<void> clearNotification(String id) async {
    try {
      await _notifications.cancel(id.hashCode);
    } catch (e) {
      debugPrint('FlutterLocalNotificationHandler: Failed to clear notification $id: $e');
    }
  }
}

/// Default error handler that logs errors
class DefaultBackgroundErrorHandler implements BackgroundErrorHandler {
  final String tag;

  DefaultBackgroundErrorHandler(this.tag);

  @override
  void onWebSocketError(dynamic error) {
    debugPrint('$tag: WebSocket error: $error');
  }

  @override
  void onConnectionError(String error) {
    debugPrint('$tag: Connection error: $error');
  }

  @override
  void onMessageError(String error, BackgroundWebSocketMessage? message) {
    debugPrint('$tag: Message error: $error, Message: ${message?.type}');
  }

  @override
  void onServiceError(String error) {
    debugPrint('$tag: Service error: $error');
  }

  @override
  void onStorageError(String error) {
    debugPrint('$tag: Storage error: $error');
  }
}

/// Default heartbeat handler
class DefaultBackgroundHeartbeatHandler implements BackgroundHeartbeatHandler {
  @override
  BackgroundWebSocketMessage generateHeartbeat() {
    return BackgroundWebSocketMessage(
      type: 'heartbeat',
      payload: {
        'type': 'heartbeat',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  void handleHeartbeatResponse(BackgroundWebSocketMessage response) {
    // Default implementation does nothing
  }

  @override
  bool isHeartbeatResponse(BackgroundWebSocketMessage message) {
    return message.type == 'heartbeat_response' || message.type == 'pong';
  }
}

/// Default lifecycle handler that does nothing
class DefaultBackgroundLifecycleHandler implements BackgroundLifecycleHandler {
  final String tag;

  DefaultBackgroundLifecycleHandler(this.tag);

  @override
  Future<void> onInitializing() async {
    debugPrint('$tag: Service initializing');
  }

  @override
  Future<void> onServiceStarted() async {
    debugPrint('$tag: Service started');
  }

  @override
  Future<void> onServiceStopping() async {
    debugPrint('$tag: Service stopping');
  }

  @override
  Future<void> onServiceStopped() async {
    debugPrint('$tag: Service stopped');
  }

  @override
  Future<void> onReconnectAttempt(int attemptNumber) async {
    debugPrint('$tag: Reconnect attempt #$attemptNumber');
  }

  @override
  Future<void> onReconnectFailed() async {
    debugPrint('$tag: All reconnection attempts failed');
  }
}

/// Token-based authentication handler
class TokenBasedAuthHandler implements BackgroundAuthHandler {
  final String? token;
  final String? username;
  final Map<String, dynamic>? additionalData;

  TokenBasedAuthHandler({
    this.token,
    this.username,
    this.additionalData,
  });

  @override
  Future<Map<String, dynamic>?> getAuthData() async {
    final authData = <String, dynamic>{};
    
    if (token != null) {
      authData['token'] = token;
    }
    
    if (username != null) {
      authData['username'] = username;
    }
    
    if (additionalData != null) {
      authData.addAll(additionalData!);
    }
    
    return authData.isEmpty ? null : authData;
  }

  @override
  bool get requiresAuth => token != null || username != null || (additionalData?.isNotEmpty ?? false);

  @override
  void onAuthSuccess() {
    // Default implementation does nothing
  }

  @override
  void onAuthFailure(String error) {
    debugPrint('TokenBasedAuthHandler: Authentication failed: $error');
  }
}

/// Query parameter authentication handler
class QueryParamAuthHandler implements BackgroundAuthHandler {
  final Map<String, String> queryParams;

  QueryParamAuthHandler(this.queryParams);

  @override
  Future<Map<String, dynamic>?> getAuthData() async {
    return queryParams.cast<String, dynamic>();
  }

  @override
  bool get requiresAuth => queryParams.isNotEmpty;

  @override
  void onAuthSuccess() {
    // Default implementation does nothing
  }

  @override
  void onAuthFailure(String error) {
    debugPrint('QueryParamAuthHandler: Authentication failed: $error');
  }
}