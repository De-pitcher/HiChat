import 'dart:developer' as developer;
import 'background_websocket_config.dart';
import 'background_websocket_interfaces.dart';
import 'reusable_background_websocket_service.dart';

/// Factory class to create and configure reusable background WebSocket services
class BackgroundWebSocketServiceFactory {
  /// Create a chat application WebSocket service
  static Future<void> createChatService({
    required String appName,
    required String webSocketUrl,
    required BackgroundMessageHandler messageHandler,
    BackgroundServiceStorage? storage,
    BackgroundNotificationHandler? notificationHandler,
    BackgroundAuthHandler? authHandler,
    List<BackgroundServicePlugin>? plugins,
    Map<String, dynamic>? customConfig,
  }) async {
    final config = BackgroundWebSocketConfig.forChat(
      appName: appName,
      webSocketUrl: webSocketUrl,
      appIconPath: customConfig?['appIconPath'],
    );
    
    await ReusableBackgroundWebSocketService.initialize(
      config: config,
      messageHandler: messageHandler,
      storage: storage,
      notificationHandler: notificationHandler,
      authHandler: authHandler,
      plugins: plugins,
    );
    
    developer.log('Chat WebSocket service created for: $appName', name: config.serviceTag);
  }

  /// Create a gaming application WebSocket service
  static Future<void> createGamingService({
    required String appName,
    required String webSocketUrl,
    required BackgroundMessageHandler messageHandler,
    BackgroundServiceStorage? storage,
    BackgroundNotificationHandler? notificationHandler,
    BackgroundAuthHandler? authHandler,
    List<BackgroundServicePlugin>? plugins,
    Map<String, dynamic>? customConfig,
  }) async {
    final config = BackgroundWebSocketConfig.forGaming(
      appName: appName,
      webSocketUrl: webSocketUrl,
      appIconPath: customConfig?['appIconPath'],
    );
    
    await ReusableBackgroundWebSocketService.initialize(
      config: config,
      messageHandler: messageHandler,
      storage: storage,
      notificationHandler: notificationHandler,
      authHandler: authHandler,
      plugins: plugins,
    );
    
    developer.log('Gaming WebSocket service created for: $appName', name: config.serviceTag);
  }

  /// Create an IoT application WebSocket service
  static Future<void> createIoTService({
    required String appName,
    required String webSocketUrl,
    required BackgroundMessageHandler messageHandler,
    BackgroundServiceStorage? storage,
    BackgroundNotificationHandler? notificationHandler,
    BackgroundAuthHandler? authHandler,
    List<BackgroundServicePlugin>? plugins,
    Map<String, dynamic>? customConfig,
  }) async {
    final config = BackgroundWebSocketConfig.forIoT(
      appName: appName,
      webSocketUrl: webSocketUrl,
      appIconPath: customConfig?['appIconPath'],
    );
    
    await ReusableBackgroundWebSocketService.initialize(
      config: config,
      messageHandler: messageHandler,
      storage: storage,
      notificationHandler: notificationHandler,
      authHandler: authHandler,
      plugins: plugins,
    );
    
    developer.log('IoT WebSocket service created for: $appName', name: config.serviceTag);
  }

  /// Create a trading application WebSocket service
  static Future<void> createTradingService({
    required String appName,
    required String webSocketUrl,
    required BackgroundMessageHandler messageHandler,
    BackgroundServiceStorage? storage,
    BackgroundNotificationHandler? notificationHandler,
    BackgroundAuthHandler? authHandler,
    List<BackgroundServicePlugin>? plugins,
    Map<String, dynamic>? customConfig,
  }) async {
    final config = BackgroundWebSocketConfig.forTrading(
      appName: appName,
      webSocketUrl: webSocketUrl,
      appIconPath: customConfig?['appIconPath'],
    );
    
    await ReusableBackgroundWebSocketService.initialize(
      config: config,
      messageHandler: messageHandler,
      storage: storage,
      notificationHandler: notificationHandler,
      authHandler: authHandler,
      plugins: plugins,
    );
    
    developer.log('Trading WebSocket service created for: $appName', name: config.serviceTag);
  }

  /// Create a custom WebSocket service with full configuration control
  static Future<void> createCustomService({
    required BackgroundWebSocketConfig config,
    required BackgroundMessageHandler messageHandler,
    BackgroundServiceStorage? storage,
    BackgroundNotificationHandler? notificationHandler,
    BackgroundAuthHandler? authHandler,
    BackgroundLifecycleHandler? lifecycleHandler,
    BackgroundErrorHandler? errorHandler,
    BackgroundHeartbeatHandler? heartbeatHandler,
    List<BackgroundServicePlugin>? plugins,
  }) async {
    await ReusableBackgroundWebSocketService.initialize(
      config: config,
      messageHandler: messageHandler,
      storage: storage,
      notificationHandler: notificationHandler,
      authHandler: authHandler,
      lifecycleHandler: lifecycleHandler,
      errorHandler: errorHandler,
      heartbeatHandler: heartbeatHandler,
      plugins: plugins,
    );
    
    developer.log('Custom WebSocket service created', name: config.serviceTag);
  }
}

/// Helper class for creating common plugin combinations
class BackgroundServicePluginFactory {
  /// Create a basic chat plugin set
  static List<BackgroundServicePlugin> createChatPlugins({
    BackgroundNotificationHandler? notificationHandler,
  }) {
    return [
      // Add chat-specific plugins here
      // Example: ChatMessagePlugin(), FileTransferPlugin(), etc.
    ];
  }

  /// Create a basic gaming plugin set
  static List<BackgroundServicePlugin> createGamingPlugins() {
    return [
      // Add gaming-specific plugins here
      // Example: GameStatePlugin(), LeaderboardPlugin(), etc.
    ];
  }

  /// Create a basic IoT plugin set
  static List<BackgroundServicePlugin> createIoTPlugins() {
    return [
      // Add IoT-specific plugins here
      // Example: DeviceStatusPlugin(), SensorDataPlugin(), etc.
    ];
  }

  /// Create a basic trading plugin set
  static List<BackgroundServicePlugin> createTradingPlugins() {
    return [
      // Add trading-specific plugins here
      // Example: PriceAlertPlugin(), OrderExecutionPlugin(), etc.
    ];
  }
}