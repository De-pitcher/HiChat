# Reusable Background WebSocket Service

## Overview

This is a 100% reusable background WebSocket service implementation for Flutter applications. It provides a complete solution for maintaining persistent WebSocket connections in the background across Android and iOS platforms.

## Features

- ✅ **100% Reusable**: Configure for any application type (Chat, Gaming, IoT, Trading, etc.)
- ✅ **Plugin Architecture**: Extensible through custom plugins
- ✅ **Configuration-Driven**: Easy setup with predefined configurations
- ✅ **Cross-Platform**: Android and iOS support
- ✅ **Automatic Reconnection**: Exponential backoff with configurable limits
- ✅ **Message Queuing**: Offline message handling
- ✅ **Heartbeat Support**: Keep connections alive
- ✅ **Authentication**: Pluggable auth handlers
- ✅ **Notifications**: Background notification support
- ✅ **Error Handling**: Comprehensive error management
- ✅ **Lifecycle Management**: Proper service lifecycle handling

## Architecture

```
ReusableBackgroundWebSocketService
├── BackgroundWebSocketConfig (Configuration)
├── BackgroundMessageHandler (Message Processing)
├── BackgroundServiceStorage (Data Persistence)
├── BackgroundNotificationHandler (Notifications)
├── BackgroundAuthHandler (Authentication)
├── BackgroundLifecycleHandler (Service Lifecycle)
├── BackgroundErrorHandler (Error Management)
├── BackgroundHeartbeatHandler (Connection Health)
└── BackgroundServicePlugin[] (Extensible Features)
```

## Quick Start

### 1. Basic Chat Application

```dart
import 'package:your_app/services/background_websocket/background_websocket_service_factory.dart';
import 'package:your_app/services/background_websocket/background_websocket_implementations.dart';

// Define your message handler
class MyChatMessageHandler extends BackgroundMessageHandler {
  @override
  Future<void> handleMessage(BackgroundWebSocketMessage message) async {
    switch (message.type) {
      case 'chat_message':
        // Handle chat message
        await _processChatMessage(message);
        break;
      case 'user_status':
        // Handle user status update
        await _processUserStatus(message);
        break;
      default:
        print('Unknown message type: ${message.type}');
    }
  }

  @override
  void onConnectionEstablished() {
    print('Chat WebSocket connected');
  }

  @override
  void onConnectionLost() {
    print('Chat WebSocket disconnected');
  }

  // ... implement other required methods
}

// Initialize the service
Future<void> initializeChatService() async {
  await BackgroundWebSocketServiceFactory.createChatService(
    appName: 'MyChat',
    webSocketUrl: 'wss://api.mychat.com/ws',
    messageHandler: MyChatMessageHandler(),
    // Optional: custom storage, notifications, auth, etc.
  );
}

// Start the service
Future<void> startChatService() async {
  await ReusableBackgroundWebSocketService.startService();
}

// Connect to WebSocket
Future<void> connectToChat(String username, String token) async {
  await ReusableBackgroundWebSocketService.connect(
    connectionData: {
      'username': username,
      'token': token,
    },
  );
}

// Send a message
Future<void> sendChatMessage(String text, String recipientId) async {
  await ReusableBackgroundWebSocketService.sendMessage({
    'type': 'chat_message',
    'text': text,
    'recipient_id': recipientId,
    'timestamp': DateTime.now().toIso8601String(),
  });
}
```

### 2. Gaming Application

```dart
class MyGameMessageHandler extends BackgroundMessageHandler {
  @override
  Future<void> handleMessage(BackgroundWebSocketMessage message) async {
    switch (message.type) {
      case 'game_update':
        await _processGameUpdate(message);
        break;
      case 'player_joined':
        await _processPlayerJoined(message);
        break;
      case 'match_found':
        await _processMatchFound(message);
        break;
    }
  }
  // ... implement other methods
}

Future<void> initializeGameService() async {
  await BackgroundWebSocketServiceFactory.createGamingService(
    appName: 'MyGame',
    webSocketUrl: 'wss://api.mygame.com/ws',
    messageHandler: MyGameMessageHandler(),
  );
}
```

### 3. IoT Application

```dart
class MyIoTMessageHandler extends BackgroundMessageHandler {
  @override
  Future<void> handleMessage(BackgroundWebSocketMessage message) async {
    switch (message.type) {
      case 'sensor_data':
        await _processSensorData(message);
        break;
      case 'device_status':
        await _processDeviceStatus(message);
        break;
      case 'alert':
        await _processAlert(message);
        break;
    }
  }
  // ... implement other methods
}

Future<void> initializeIoTService() async {
  await BackgroundWebSocketServiceFactory.createIoTService(
    appName: 'MyIoT',
    webSocketUrl: 'wss://api.myiot.com/ws',
    messageHandler: MyIoTMessageHandler(),
  );
}
```

## Advanced Usage

### Custom Configuration

```dart
Future<void> createCustomService() async {
  final config = BackgroundWebSocketConfig(
    appName: 'MyCustomApp',
    notificationChannelId: 'custom_websocket',
    notificationChannelName: 'Custom WebSocket',
    webSocketUrl: 'wss://api.mycustomapp.com/ws',
    maxQueueSize: 200,
    maxReconnectAttempts: 15,
    heartbeatInterval: Duration(seconds: 20),
    initialReconnectDelay: Duration(seconds: 3),
    maxReconnectDelay: Duration(minutes: 10),
    serviceTag: 'CustomAppWS',
  );

  await BackgroundWebSocketServiceFactory.createCustomService(
    config: config,
    messageHandler: MyCustomMessageHandler(),
    storage: MyCustomStorage(),
    notificationHandler: MyCustomNotificationHandler(),
    authHandler: MyCustomAuthHandler(),
    plugins: [
      MyCustomPlugin(),
      AnotherCustomPlugin(),
    ],
  );
}
```

### Creating Custom Plugins

```dart
class MyCustomPlugin extends BackgroundServicePlugin {
  @override
  String get pluginName => 'MyCustomPlugin';

  @override
  List<String> get supportedMessageTypes => ['custom_message', 'special_event'];

  @override
  Future<void> initialize() async {
    print('MyCustomPlugin initialized');
  }

  @override
  bool handleMessage(BackgroundWebSocketMessage message) {
    if (message.type == 'custom_message') {
      // Handle custom message
      _processCustomMessage(message);
      return true; // Message handled
    }
    return false; // Message not handled
  }

  @override
  void onConnectionChanged(bool isConnected) {
    print('MyCustomPlugin: Connection changed - $isConnected');
  }

  @override
  void onServiceStarted() {
    print('MyCustomPlugin: Service started');
  }

  @override
  void onServiceStopped() {
    print('MyCustomPlugin: Service stopped');
  }

  @override
  void dispose() {
    print('MyCustomPlugin disposed');
  }

  void _processCustomMessage(BackgroundWebSocketMessage message) {
    // Custom message processing logic
  }
}
```

### Custom Authentication Handler

```dart
class MyAuthHandler extends BackgroundAuthHandler {
  @override
  bool get requiresAuth => true;

  @override
  Future<Map<String, dynamic>?> getAuthData() async {
    // Get auth data from secure storage, preferences, etc.
    final token = await _getStoredToken();
    return {
      'authorization': 'Bearer $token',
      'user_id': await _getUserId(),
    };
  }

  @override
  Future<void> onAuthSuccess() async {
    print('Authentication successful');
  }

  @override
  Future<void> onAuthFailure(String error) async {
    print('Authentication failed: $error');
    // Handle auth failure (refresh token, logout, etc.)
  }
}
```

### Custom Storage Handler

```dart
class MyCustomStorage extends BackgroundServiceStorage {
  @override
  Future<void> storeConnectionInfo(String key, String value) async {
    // Store in encrypted storage, database, etc.
    await MySecureStorage.store(key, value);
  }

  @override
  Future<String?> getConnectionInfo(String key) async {
    return await MySecureStorage.retrieve(key);
  }

  @override
  Future<void> clearConnectionInfo() async {
    await MySecureStorage.clearAll();
  }
}
```

## Multiple Services

You can run multiple background services simultaneously:

```dart
// Service 1: Chat
await BackgroundWebSocketServiceFactory.createChatService(
  appName: 'MyChat',
  webSocketUrl: 'wss://chat.myapp.com/ws',
  messageHandler: ChatMessageHandler(),
);

// Service 2: Gaming (separate instance)
await BackgroundWebSocketServiceFactory.createGamingService(
  appName: 'MyGame', 
  webSocketUrl: 'wss://game.myapp.com/ws',
  messageHandler: GameMessageHandler(),
);

// Start both services
await ReusableBackgroundWebSocketService.startService();
// Note: For truly separate services, you'd need to create separate instances
// or implement a service manager that handles multiple configurations
```

## Configuration Options

### BackgroundWebSocketConfig Parameters

- `appName`: Application name for notifications
- `notificationChannelId`: Unique notification channel identifier
- `notificationChannelName`: Human-readable channel name
- `webSocketUrl`: WebSocket server URL
- `appIconPath`: Path to app icon for notifications
- `foregroundServiceNotificationId`: Notification ID for foreground service
- `maxQueueSize`: Maximum number of queued messages
- `maxReconnectAttempts`: Maximum reconnection attempts
- `initialReconnectDelay`: Initial delay before reconnection
- `maxReconnectDelay`: Maximum delay between reconnections
- `heartbeatInterval`: Interval for sending heartbeat messages
- `autoStartOnBoot`: Whether to start service on device boot
- `isForegroundMode`: Run as foreground service (Android)
- `storageKeys`: Custom storage key configuration
- `serviceTag`: Tag for logging and identification

### Predefined Configurations

The service comes with predefined configurations for common use cases:

- **Chat Applications**: Optimized for messaging with notifications
- **Gaming Applications**: Low-latency configuration for real-time gaming
- **IoT Applications**: Efficient for sensor data and device communication
- **Trading Applications**: High-frequency updates with priority handling

## Best Practices

1. **Initialize Once**: Initialize the service once in your app's main function
2. **Handle Lifecycle**: Properly start/stop the service based on app lifecycle
3. **Error Handling**: Implement robust error handling in your message handlers
4. **Memory Management**: Be mindful of memory usage in background operations
5. **Testing**: Test reconnection scenarios and background/foreground transitions
6. **Permissions**: Ensure proper permissions for background services and notifications

## Platform Considerations

### Android
- Requires foreground service permission for persistent background operation
- Uses notification channels for Android 8.0+
- Supports auto-start on boot

### iOS
- Background app refresh must be enabled
- Limited background execution time
- Uses background processing for connection maintenance

## Troubleshooting

### Common Issues

1. **Service not starting**: Check permissions and initialization
2. **Connection drops**: Verify network connectivity and server availability
3. **Messages not received**: Ensure proper message handler implementation
4. **High battery usage**: Optimize heartbeat interval and message processing

### Debug Logging

Enable debug logging by setting the service tag:

```dart
developer.log('Debug message', name: 'YourServiceTag');
```

## Migration from Existing Services

To migrate from your existing WebSocket service:

1. Identify your current message types and handlers
2. Create a custom message handler implementing `BackgroundMessageHandler`
3. Replace your service initialization with the reusable service
4. Test thoroughly in background/foreground scenarios

This reusable service provides enterprise-grade WebSocket functionality while maintaining complete flexibility for customization.