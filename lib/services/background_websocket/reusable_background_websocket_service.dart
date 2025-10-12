import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import 'background_websocket_config.dart';
import 'background_websocket_interfaces.dart';
import 'background_websocket_implementations.dart';

/// Reusable Background WebSocket Service that can be configured for any application
class ReusableBackgroundWebSocketService {
  // Configuration
  static BackgroundWebSocketConfig? _config;
  static BackgroundMessageHandler? _messageHandler;
  static BackgroundServiceStorage? _storage;
  static BackgroundNotificationHandler? _notificationHandler;
  static BackgroundAuthHandler? _authHandler;
  static BackgroundLifecycleHandler? _lifecycleHandler;
  static BackgroundErrorHandler? _errorHandler;
  static BackgroundHeartbeatHandler? _heartbeatHandler;
  
  // Plugins
  static final List<BackgroundServicePlugin> _plugins = [];
  
  // Service instance
  static ReusableBackgroundWebSocketService? _instance;
  static ReusableBackgroundWebSocketService get instance => _instance ??= ReusableBackgroundWebSocketService._();
  
  ReusableBackgroundWebSocketService._();

  /// Initialize the reusable background WebSocket service
  static Future<void> initialize({
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
    developer.log('Initializing reusable background WebSocket service...', name: config.serviceTag);
    
    // Store configuration and handlers
    _config = config;
    _messageHandler = messageHandler;
    _storage = storage ?? SharedPreferencesBackgroundStorage();
    _notificationHandler = notificationHandler ?? FlutterLocalNotificationHandler();
    _authHandler = authHandler;
    _lifecycleHandler = lifecycleHandler ?? DefaultBackgroundLifecycleHandler(config.serviceTag);
    _errorHandler = errorHandler ?? DefaultBackgroundErrorHandler(config.serviceTag);
    _heartbeatHandler = heartbeatHandler ?? DefaultBackgroundHeartbeatHandler();
    
    // Register plugins
    if (plugins != null) {
      _plugins.addAll(plugins);
      for (final plugin in plugins) {
        await plugin.initialize();
      }
    }
    
    // Initialize the background service
    final service = FlutterBackgroundService();
    
    // Configure notification handler
    await _notificationHandler!.initialize(
      config.notificationChannelId,
      config.notificationChannelName,
      config.appIconPath,
    );
    
    // Configure the background service
    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        autoStart: true,
        onStart: onStart,
        isForegroundMode: config.isForegroundMode,
        autoStartOnBoot: config.autoStartOnBoot,
        initialNotificationTitle: config.appName,
        initialNotificationContent: 'Keeping connection alive',
        foregroundServiceNotificationId: config.foregroundServiceNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
    );
    
    await _lifecycleHandler!.onInitializing();
    
    developer.log('Reusable background service configured successfully', name: config.serviceTag);
  }

  /// Start the background service
  static Future<void> startService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        await service.startService();
        await _lifecycleHandler?.onServiceStarted();
        
        // Notify plugins
        for (final plugin in _plugins) {
          plugin.onServiceStarted();
        }
        
        developer.log('Background service started', name: _config?.serviceTag ?? 'ReusableBackgroundWS');
      } else {
        developer.log('Background service already running', name: _config?.serviceTag ?? 'ReusableBackgroundWS');
      }
    } catch (e) {
      _errorHandler?.onServiceError('Failed to start background service: $e');
      developer.log('Failed to start background service: $e', name: _config?.serviceTag ?? 'ReusableBackgroundWS', level: 1000);
    }
  }

  /// Stop the background service
  static Future<void> stopService() async {
    try {
      await _lifecycleHandler?.onServiceStopping();
      
      final service = FlutterBackgroundService();
      service.invoke('stop');
      
      await _lifecycleHandler?.onServiceStopped();
      
      // Notify plugins
      for (final plugin in _plugins) {
        plugin.onServiceStopped();
      }
      
      developer.log('Background service stopped', name: _config?.serviceTag ?? 'ReusableBackgroundWS');
    } catch (e) {
      _errorHandler?.onServiceError('Failed to stop background service: $e');
      developer.log('Failed to stop background service: $e', name: _config?.serviceTag ?? 'ReusableBackgroundWS', level: 1000);
    }
  }

  /// Send data to background service
  static Future<void> sendToService(String action, Map<String, dynamic> data) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke(action, data);
    } catch (e) {
      _errorHandler?.onServiceError('Failed to send data to service: $e');
      developer.log('Failed to send data to service: $e', name: _config?.serviceTag ?? 'ReusableBackgroundWS', level: 1000);
    }
  }

  /// Connect to WebSocket
  static Future<void> connect({required Map<String, dynamic> connectionData}) async {
    await sendToService('connect', {'data': connectionData});
  }

  /// Disconnect from WebSocket
  static Future<void> disconnect() async {
    await sendToService('disconnect', {});
  }

  /// Send message via WebSocket
  static Future<void> sendMessage(Map<String, dynamic> message) async {
    await sendToService('send_message', {'data': message});
  }

  /// Register a plugin
  static Future<void> registerPlugin(BackgroundServicePlugin plugin) async {
    if (!_plugins.contains(plugin)) {
      _plugins.add(plugin);
      await plugin.initialize();
    }
  }

  /// Unregister a plugin
  static void unregisterPlugin(BackgroundServicePlugin plugin) {
    if (_plugins.contains(plugin)) {
      plugin.dispose();
      _plugins.remove(plugin);
    }
  }

  /// Get configuration
  static BackgroundWebSocketConfig? get config => _config;
}

/// Main entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  final config = ReusableBackgroundWebSocketService._config;
  developer.log('Background service onStart called', name: config?.serviceTag ?? 'ReusableBackgroundWS');
  
  // Initialize the WebSocket service in background
  final backgroundService = _ReusableBackgroundServiceImpl(service);
  await backgroundService.initialize();
  
  // Listen for service commands
  service.on('stop').listen((event) {
    backgroundService.dispose();
    service.stopSelf();
  });
  
  service.on('connect').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    await backgroundService.connect(connectionData: data);
  });
  
  service.on('disconnect').listen((event) {
    backgroundService.disconnect();
  });
  
  service.on('send_message').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    await backgroundService.sendMessage(data);
  });
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Reusable background service implementation
class _ReusableBackgroundServiceImpl {
  final ServiceInstance _service;
  WebSocketChannel? _webSocket;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  // Configuration and handlers
  BackgroundWebSocketConfig get _config => ReusableBackgroundWebSocketService._config!;
  BackgroundMessageHandler get _messageHandler => ReusableBackgroundWebSocketService._messageHandler!;
  BackgroundServiceStorage get _storage => ReusableBackgroundWebSocketService._storage!;
  BackgroundAuthHandler? get _authHandler => ReusableBackgroundWebSocketService._authHandler;
  BackgroundLifecycleHandler get _lifecycleHandler => ReusableBackgroundWebSocketService._lifecycleHandler!;
  BackgroundErrorHandler get _errorHandler => ReusableBackgroundWebSocketService._errorHandler!;
  BackgroundHeartbeatHandler get _heartbeatHandler => ReusableBackgroundWebSocketService._heartbeatHandler!;
  List<BackgroundServicePlugin> get _plugins => ReusableBackgroundWebSocketService._plugins;
  
  // Connection state
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  
  // Message queue for offline messages
  final List<BackgroundWebSocketMessage> _messageQueue = [];
  
  _ReusableBackgroundServiceImpl(this._service);

  /// Initialize the background service
  Future<void> initialize() async {
    developer.log('Initializing reusable background service implementation', name: _config.serviceTag);
    
    // Setup heartbeat timer
    _heartbeatTimer = Timer.periodic(_config.heartbeatInterval, (_) => _sendHeartbeat());
    
    // Update service notification
    await _updateServiceNotification('Initialized', 'WebSocket service ready');
  }

  /// Connect to WebSocket
  Future<void> connect({required Map<String, dynamic> connectionData}) async {
    try {
      developer.log('Connecting to WebSocket', name: _config.serviceTag);
      
      _shouldReconnect = true;
      _reconnectAttempts = 0;
      
      await _initiateConnection(connectionData);
    } catch (e) {
      _errorHandler.onConnectionError('Connection failed: $e');
      developer.log('Connection failed: $e', name: _config.serviceTag, level: 1000);
    }
  }

  /// Disconnect from WebSocket
  void disconnect() {
    developer.log('Disconnecting WebSocket', name: _config.serviceTag);
    
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _isConnected = false;
    
    _updateServiceNotification('Disconnected', 'WebSocket disconnected');
    _messageHandler.onConnectionLost();
    
    // Notify plugins
    for (final plugin in _plugins) {
      plugin.onConnectionChanged(false);
    }
  }

  /// Send message via WebSocket
  Future<void> sendMessage(Map<String, dynamic> messageData) async {
    final message = BackgroundWebSocketMessage.fromJson(messageData);
    
    if (_isConnected && _webSocket != null) {
      try {
        _webSocket!.sink.add(jsonEncode(message.payload));
        developer.log('Message sent: ${message.type}', name: _config.serviceTag);
      } catch (e) {
        _errorHandler.onMessageError('Failed to send message: $e', message);
        _queueMessage(message);
      }
    } else {
      developer.log('WebSocket not connected, queuing message', name: _config.serviceTag, level: 900);
      _queueMessage(message);
    }
  }

  /// Initiate WebSocket connection
  Future<void> _initiateConnection(Map<String, dynamic> connectionData) async {
    try {
      // Build WebSocket URL
      final uri = Uri.parse(_config.webSocketUrl);
      
      // Add authentication data if available
      Map<String, String>? queryParams;
      if (_authHandler != null) {
        final authData = await _authHandler!.getAuthData();
        if (authData != null) {
          queryParams = authData.map((key, value) => MapEntry(key, value.toString()));
        }
      }
      
      // Add connection data to query params
      queryParams ??= {};
      connectionData.forEach((key, value) {
        queryParams![key] = value.toString();
      });
      
      final finalUri = uri.replace(queryParameters: queryParams);
      developer.log('Connecting to: $finalUri', name: _config.serviceTag);
      
      _webSocket = WebSocketChannel.connect(finalUri);
      
      // Listen to the stream
      _subscription = _webSocket!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnected,
      );
      
      // Connection successful
      _isConnected = true;
      _reconnectAttempts = 0;
      
      developer.log('WebSocket connected successfully', name: _config.serviceTag);
      await _updateServiceNotification('Connected', 'Service running');
      
      _messageHandler.onConnectionEstablished();
      _authHandler?.onAuthSuccess();
      
      // Notify plugins
      for (final plugin in _plugins) {
        plugin.onConnectionChanged(true);
      }
      
      // Send authentication message if required
      if (_authHandler != null && _authHandler!.requiresAuth) {
        final authData = await _authHandler!.getAuthData();
        if (authData != null) {
          await sendMessage({
            'type': 'authenticate',
            ...authData,
          });
        }
      }
      
      // Flush queued messages
      await _flushMessageQueue();
      
    } catch (e) {
      _errorHandler.onConnectionError('Connection failed: $e');
      developer.log('Connection failed: $e', name: _config.serviceTag, level: 1000);
      _onError(e);
    }
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data.toString()) as Map<String, dynamic>;
      final message = BackgroundWebSocketMessage.fromJson(jsonData);
      
      developer.log('Received message: ${message.type}', name: _config.serviceTag);
      
      // Check if it's a heartbeat response
      if (_heartbeatHandler.isHeartbeatResponse(message)) {
        _heartbeatHandler.handleHeartbeatResponse(message);
        return;
      }
      
      // Try plugins first
      bool handled = false;
      for (final plugin in _plugins) {
        if (plugin.supportedMessageTypes.contains(message.type)) {
          if (plugin.handleMessage(message)) {
            handled = true;
            break;
          }
        }
      }
      
      // If no plugin handled it, use main handler
      if (!handled) {
        _messageHandler.handleMessage(message);
      }
      
      // Send message to main app if it's running
      _service.invoke('websocket_message', {'data': jsonData});
      
    } catch (e) {
      _errorHandler.onMessageError('Error processing message: $e', null);
      developer.log('Error processing message: $e', name: _config.serviceTag, level: 1000);
    }
  }

  /// Handle WebSocket errors
  void _onError(dynamic error) {
    _errorHandler.onWebSocketError(error);
    developer.log('WebSocket error: $error', name: _config.serviceTag, level: 1000);
    _isConnected = false;
    
    _messageHandler.onConnectionLost();
    
    // Notify plugins
    for (final plugin in _plugins) {
      plugin.onConnectionChanged(false);
    }
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Handle WebSocket disconnection
  void _onDisconnected() {
    developer.log('WebSocket disconnected', name: _config.serviceTag, level: 900);
    _isConnected = false;
    
    _messageHandler.onConnectionLost();
    
    // Notify plugins
    for (final plugin in _plugins) {
      plugin.onConnectionChanged(false);
    }
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _config.maxReconnectAttempts) {
      developer.log('Max reconnect attempts reached', name: _config.serviceTag, level: 1000);
      _updateServiceNotification('Failed', 'Connection failed');
      _lifecycleHandler.onReconnectFailed();
      return;
    }

    final delay = Duration(
      milliseconds: (_config.initialReconnectDelay.inMilliseconds * 
        (1 << _reconnectAttempts)).clamp(
          _config.initialReconnectDelay.inMilliseconds,
          _config.maxReconnectDelay.inMilliseconds,
        ),
    );

    _reconnectAttempts++;
    developer.log('Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)', name: _config.serviceTag);
    
    _updateServiceNotification(
      'Reconnecting...', 
      'Attempt $_reconnectAttempts in ${delay.inSeconds}s'
    );
    
    _lifecycleHandler.onReconnectAttempt(_reconnectAttempts);
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _retryConnection());
  }

  /// Retry connection
  Future<void> _retryConnection() async {
    try {
      // Get stored connection info
      final username = await _storage.getConnectionInfo(_config.storageKeys.usernameKey);
      final token = await _storage.getConnectionInfo(_config.storageKeys.tokenKey);
      
      if (username != null) {
        final connectionData = <String, dynamic>{'username': username};
        if (token != null) {
          connectionData['token'] = token;
        }
        await _initiateConnection(connectionData);
      } else {
        developer.log('No stored connection info for reconnection', name: _config.serviceTag, level: 900);
      }
    } catch (e) {
      _errorHandler.onConnectionError('Reconnection failed: $e');
      developer.log('Reconnection failed: $e', name: _config.serviceTag, level: 1000);
      _onError(e);
    }
  }

  /// Send heartbeat to keep connection alive
  void _sendHeartbeat() {
    if (_isConnected && _webSocket != null) {
      try {
        final heartbeat = _heartbeatHandler.generateHeartbeat();
        _webSocket!.sink.add(jsonEncode(heartbeat.payload));
        developer.log('Heartbeat sent', name: _config.serviceTag);
      } catch (e) {
        _errorHandler.onWebSocketError('Failed to send heartbeat: $e');
        developer.log('Failed to send heartbeat: $e', name: _config.serviceTag, level: 900);
      }
    }
  }

  /// Queue message for later sending
  void _queueMessage(BackgroundWebSocketMessage message) {
    if (_messageQueue.length >= _config.maxQueueSize) {
      _messageQueue.removeAt(0); // Remove oldest message
    }
    _messageQueue.add(message);
    _messageHandler.onMessageQueued(message);
    developer.log('Message queued (${_messageQueue.length})', name: _config.serviceTag);
  }

  /// Flush queued messages
  Future<void> _flushMessageQueue() async {
    while (_messageQueue.isNotEmpty && _isConnected) {
      final message = _messageQueue.removeAt(0);
      try {
        _webSocket!.sink.add(jsonEncode(message.payload));
        _messageHandler.onQueuedMessageSent(message);
        developer.log('Queued message sent: ${message.type}', name: _config.serviceTag);
        
        // Small delay between messages
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        _errorHandler.onMessageError('Failed to send queued message: $e', message);
        developer.log('Failed to send queued message: $e', name: _config.serviceTag, level: 900);
        _messageQueue.insert(0, message); // Re-queue
        break;
      }
    }
    
    if (_messageQueue.isEmpty) {
      developer.log('All queued messages sent', name: _config.serviceTag);
    }
  }

  /// Update service notification
  Future<void> _updateServiceNotification(String title, String content) async {
    try {
      if (_service is AndroidServiceInstance) {
        await _service.setForegroundNotificationInfo(
          title: '${_config.appName} - $title',
          content: content,
        );
      }
    } catch (e) {
      _errorHandler.onServiceError('Failed to update notification: $e');
      developer.log('Failed to update notification: $e', name: _config.serviceTag, level: 900);
    }
  }

  /// Dispose resources
  void dispose() {
    developer.log('Disposing background service', name: _config.serviceTag);
    
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _messageQueue.clear();
    
    // Dispose plugins
    for (final plugin in _plugins) {
      plugin.dispose();
    }
  }
}