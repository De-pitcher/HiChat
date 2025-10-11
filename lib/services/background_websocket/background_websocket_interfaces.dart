/// Message wrapper for background WebSocket messages
class BackgroundWebSocketMessage {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? id;

  BackgroundWebSocketMessage({
    required this.type,
    required this.payload,
    DateTime? timestamp,
    this.id,
  }) : timestamp = timestamp ?? DateTime.now();

  factory BackgroundWebSocketMessage.fromJson(Map<String, dynamic> json) {
    return BackgroundWebSocketMessage(
      type: json['type'] as String? ?? 'unknown',
      payload: json,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      id: json['id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'timestamp': timestamp.millisecondsSinceEpoch,
      if (id != null) 'id': id,
      ...payload,
    };
  }

  @override
  String toString() => 'BackgroundWebSocketMessage(type: $type, id: $id)';
}

/// Abstract message handler for processing WebSocket messages
abstract class BackgroundMessageHandler {
  /// Handle incoming WebSocket message
  void handleMessage(BackgroundWebSocketMessage message);
  
  /// Called when WebSocket connection is established
  void onConnectionEstablished() {}
  
  /// Called when WebSocket connection is lost
  void onConnectionLost() {}
  
  /// Called when background service starts
  void onServiceStarted() {}
  
  /// Called when background service stops
  void onServiceStopped() {}
  
  /// Called when a message is queued due to connection issues
  void onMessageQueued(BackgroundWebSocketMessage message) {}
  
  /// Called when a queued message is successfully sent
  void onQueuedMessageSent(BackgroundWebSocketMessage message) {}
  
  /// Called when a message permanently fails after max retries
  void onMessagePermanentlyFailed(BackgroundWebSocketMessage message) {}
  
  /// Get list of message types this handler supports
  List<String> get supportedMessageTypes;
}

/// Abstract storage interface for background service persistence
abstract class BackgroundServiceStorage {
  /// Get stored connection information
  Future<String?> getConnectionInfo(String key);
  
  /// Set connection information
  Future<void> setConnectionInfo(String key, String value);
  
  /// Clear specific connection information
  Future<void> clearConnectionInfo(String key);
  
  /// Clear all connection information
  Future<void> clearAllConnectionInfo();
  
  /// Check if connection info exists
  Future<bool> hasConnectionInfo(String key);
}

/// Abstract notification handler for customizable notifications
abstract class BackgroundNotificationHandler {
  /// Show notification for received message
  Future<void> showNotification({
    required String title,
    required String body,
    String? id,
    Map<String, dynamic>? payload,
  });
  
  /// Initialize notification system
  Future<void> initialize(String channelId, String channelName, String appIconPath);
  
  /// Clear all notifications
  Future<void> clearAllNotifications();
  
  /// Clear specific notification
  Future<void> clearNotification(String id);
}

/// Connection authentication handler
abstract class BackgroundAuthHandler {
  /// Get authentication data for connection
  Future<Map<String, dynamic>?> getAuthData();
  
  /// Handle authentication success
  void onAuthSuccess() {}
  
  /// Handle authentication failure
  void onAuthFailure(String error) {}
  
  /// Check if authentication is required
  bool get requiresAuth => true;
}

/// Lifecycle event handler for background service events
abstract class BackgroundLifecycleHandler {
  /// Called when service is initializing
  Future<void> onInitializing() async {}
  
  /// Called when service has started successfully
  Future<void> onServiceStarted() async {}
  
  /// Called when service is stopping
  Future<void> onServiceStopping() async {}
  
  /// Called when service has stopped
  Future<void> onServiceStopped() async {}
  
  /// Called when reconnection attempt starts
  Future<void> onReconnectAttempt(int attemptNumber) async {}
  
  /// Called when all reconnection attempts are exhausted
  Future<void> onReconnectFailed() async {}
}

/// Error handler for background service errors
abstract class BackgroundErrorHandler {
  /// Handle WebSocket errors
  void onWebSocketError(dynamic error);
  
  /// Handle connection errors
  void onConnectionError(String error);
  
  /// Handle message processing errors
  void onMessageError(String error, BackgroundWebSocketMessage? message);
  
  /// Handle service errors
  void onServiceError(String error);
  
  /// Handle storage errors
  void onStorageError(String error);
}

/// Heartbeat handler for custom heartbeat logic
abstract class BackgroundHeartbeatHandler {
  /// Generate heartbeat message
  BackgroundWebSocketMessage generateHeartbeat();
  
  /// Handle heartbeat response
  void handleHeartbeatResponse(BackgroundWebSocketMessage response) {}
  
  /// Check if message is a heartbeat response
  bool isHeartbeatResponse(BackgroundWebSocketMessage message) => false;
}

/// Plugin interface for extending background service functionality
abstract class BackgroundServicePlugin {
  /// Plugin name
  String get pluginName;
  
  /// Plugin version
  String get pluginVersion => '1.0.0';
  
  /// Message types this plugin handles
  List<String> get supportedMessageTypes;
  
  /// Initialize plugin
  Future<void> initialize() async {}
  
  /// Handle message if supported
  bool handleMessage(BackgroundWebSocketMessage message);
  
  /// Called when service starts
  void onServiceStarted() {}
  
  /// Called when service stops
  void onServiceStopped() {}
  
  /// Called when connection state changes
  void onConnectionChanged(bool isConnected) {}
  
  /// Dispose plugin resources
  void dispose() {}
}