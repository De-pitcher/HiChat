/// Configuration class for Background WebSocket Service
/// Makes the service completely reusable across different applications
class BackgroundWebSocketConfig {
  /// Application name displayed in notifications
  final String appName;
  
  /// Unique identifier for notification channel
  final String notificationChannelId;
  
  /// Display name for notification channel
  final String notificationChannelName;
  
  /// WebSocket server URL
  final String webSocketUrl;
  
  /// Application icon path for notifications
  final String appIconPath;
  
  /// Service notification ID (should be unique per app)
  final int foregroundServiceNotificationId;
  
  /// Maximum number of messages to queue when disconnected
  final int maxQueueSize;
  
  /// Maximum number of reconnection attempts
  final int maxReconnectAttempts;
  
  /// Initial delay between reconnection attempts
  final Duration initialReconnectDelay;
  
  /// Maximum delay between reconnection attempts
  final Duration maxReconnectDelay;
  
  /// Interval for sending heartbeat messages
  final Duration heartbeatInterval;
  
  /// Whether to auto-start service on boot
  final bool autoStartOnBoot;
  
  /// Whether to run as foreground service (Android)
  final bool isForegroundMode;
  
  /// Storage keys configuration
  final BackgroundStorageKeys storageKeys;
  
  /// Service tag for logging
  final String serviceTag;

  const BackgroundWebSocketConfig({
    required this.appName,
    required this.notificationChannelId,
    required this.notificationChannelName,
    required this.webSocketUrl,
    this.appIconPath = '@mipmap/ic_launcher',
    this.foregroundServiceNotificationId = 888,
    this.maxQueueSize = 100,
    this.maxReconnectAttempts = 10,
    this.initialReconnectDelay = const Duration(seconds: 5),
    this.maxReconnectDelay = const Duration(minutes: 5),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.autoStartOnBoot = true,
    this.isForegroundMode = true,
    this.storageKeys = const BackgroundStorageKeys(),
    this.serviceTag = 'BackgroundWS',
  });

  /// Create configuration for chat applications
  factory BackgroundWebSocketConfig.forChat({
    required String appName,
    required String webSocketUrl,
    String? appIconPath,
  }) {
    return BackgroundWebSocketConfig(
      appName: appName,
      notificationChannelId: '${appName.toLowerCase()}_chat_websocket',
      notificationChannelName: '$appName Chat',
      webSocketUrl: webSocketUrl,
      appIconPath: appIconPath ?? '@mipmap/ic_launcher',
      serviceTag: '${appName}BackgroundWS',
    );
  }

  /// Create configuration for gaming applications
  factory BackgroundWebSocketConfig.forGaming({
    required String appName,
    required String webSocketUrl,
    String? appIconPath,
  }) {
    return BackgroundWebSocketConfig(
      appName: appName,
      notificationChannelId: '${appName.toLowerCase()}_game_websocket',
      notificationChannelName: '$appName Game Updates',
      webSocketUrl: webSocketUrl,
      appIconPath: appIconPath ?? '@mipmap/ic_launcher',
      heartbeatInterval: const Duration(seconds: 15), // More frequent for gaming
      maxQueueSize: 200, // Larger queue for game events
      serviceTag: '${appName}GameWS',
    );
  }

  /// Create configuration for IoT applications
  factory BackgroundWebSocketConfig.forIoT({
    required String appName,
    required String webSocketUrl,
    String? appIconPath,
  }) {
    return BackgroundWebSocketConfig(
      appName: appName,
      notificationChannelId: '${appName.toLowerCase()}_iot_websocket',
      notificationChannelName: '$appName Device Updates',
      webSocketUrl: webSocketUrl,
      appIconPath: appIconPath ?? '@mipmap/ic_launcher',
      heartbeatInterval: const Duration(minutes: 1), // Less frequent for IoT
      maxQueueSize: 50, // Smaller queue for device updates
      serviceTag: '${appName}IoTWS',
    );
  }

  /// Create configuration for trading applications
  factory BackgroundWebSocketConfig.forTrading({
    required String appName,
    required String webSocketUrl,
    String? appIconPath,
  }) {
    return BackgroundWebSocketConfig(
      appName: appName,
      notificationChannelId: '${appName.toLowerCase()}_trading_websocket',
      notificationChannelName: '$appName Trading Alerts',
      webSocketUrl: webSocketUrl,
      appIconPath: appIconPath ?? '@mipmap/ic_launcher',
      heartbeatInterval: const Duration(seconds: 10), // Very frequent for trading
      maxQueueSize: 500, // Large queue for trading data
      serviceTag: '${appName}TradingWS',
    );
  }
}

/// Storage keys configuration for flexibility
class BackgroundStorageKeys {
  final String usernameKey;
  final String tokenKey;
  final String connectionInfoPrefix;

  const BackgroundStorageKeys({
    this.usernameKey = 'websocket_username',
    this.tokenKey = 'websocket_token',
    this.connectionInfoPrefix = 'background_ws_',
  });

  /// Create storage keys with custom prefix
  factory BackgroundStorageKeys.withPrefix(String prefix) {
    return BackgroundStorageKeys(
      usernameKey: '${prefix}_username',
      tokenKey: '${prefix}_token',
      connectionInfoPrefix: '${prefix}_',
    );
  }
}