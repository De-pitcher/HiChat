import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Background WebSocket service that keeps chat connections alive
/// even when the app is in background or closed
class BackgroundWebSocketService {
  static const String _tag = 'BackgroundWS';
  static const String _notificationChannelId = 'hichat_websocket';
  static const String _notificationChannelName = 'HiChat WebSocket';
  
  // Service instance
  static BackgroundWebSocketService? _instance;
  static BackgroundWebSocketService get instance => _instance ??= BackgroundWebSocketService._();
  
  // Notification plugin
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  BackgroundWebSocketService._();

  /// Initialize and start the background service
  static Future<void> initialize() async {
    developer.log('Initializing background WebSocket service...', name: _tag);
    
    // Initialize the background service
    final service = FlutterBackgroundService();
    
    // Configure notification channel
    await _initializeNotifications();
    
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
        isForegroundMode: true,
        autoStartOnBoot: true,
        initialNotificationTitle: 'HiChat',
        initialNotificationContent: 'Keeping chat connection alive',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
    );
    
    developer.log('Background service configured successfully', name: _tag);
  }

  /// Start the background service
  static Future<void> startService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        await service.startService();
        developer.log('Background service started', name: _tag);
      } else {
        developer.log('Background service already running', name: _tag);
      }
    } catch (e) {
      developer.log('Failed to start background service: $e', name: _tag, level: 1000);
    }
  }

  /// Stop the background service
  static Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
      developer.log('Background service stopped', name: _tag);
    } catch (e) {
      developer.log('Failed to stop background service: $e', name: _tag, level: 1000);
    }
  }

  /// Send data to background service
  static Future<void> sendToService(String action, Map<String, dynamic> data) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke(action, data);
    } catch (e) {
      developer.log('Failed to send data to service: $e', name: _tag, level: 1000);
    }
  }

  /// Initialize notifications
  static Future<void> _initializeNotifications() async {
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
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Notifications for WebSocket background service',
      importance: Importance.low,
      showBadge: false,
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Show notification for new message
  static Future<void> showMessageNotification({
    required String title,
    required String body,
    String? chatId,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _notificationChannelId,
        _notificationChannelName,
        channelDescription: 'New message notifications',
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
      
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(
        chatId?.hashCode ?? 0,
        title,
        body,
        notificationDetails,
        payload: chatId,
      );
    } catch (e) {
      developer.log('Failed to show notification: $e', name: _tag, level: 1000);
    }
  }
}

/// Main entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  developer.log('Background service onStart called', name: BackgroundWebSocketService._tag);
  
  // Initialize the WebSocket service in background
  final backgroundService = _BackgroundServiceImpl(service);
  await backgroundService.initialize();
  
  // Listen for service commands
  service.on('stop').listen((event) {
    backgroundService.dispose();
    service.stopSelf();
  });
  
  service.on('connect').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    await backgroundService.connect(
      username: data['username'] as String,
      token: data['token'] as String?,
    );
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

/// Background service implementation
class _BackgroundServiceImpl {
  static const String _tag = 'BackgroundServiceImpl';
  static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/chat/';
  
  /// Debug method to test URL construction and basic connectivity
  static Future<void> debugConnection(String username) async {
    try {
      final encodedUsername = Uri.encodeComponent(username);
      final urlString = '$_wsUrl$encodedUsername/';
      developer.log('=== Debug Connection Test ===', name: _tag);
      developer.log('Base URL: $_wsUrl', name: _tag);
      developer.log('Username: "$username"', name: _tag);
      developer.log('Encoded: "$encodedUsername"', name: _tag);
      developer.log('Final URL: "$urlString"', name: _tag);
      
      final uri = Uri.tryParse(urlString);
      if (uri == null) {
        developer.log('❌ URI parsing failed!', name: _tag, level: 1000);
        return;
      }
      
      developer.log('✅ URI parsed successfully: $uri', name: _tag);
      developer.log('URI components - scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}', name: _tag);
      
      // Test basic HTTP connectivity to the host
      try {
        final httpUri = Uri.parse('https://${uri.host}/');
        developer.log('Testing HTTP connectivity to: $httpUri', name: _tag);
        
        final response = await http.get(httpUri).timeout(Duration(seconds: 10));
        developer.log('✅ HTTP test successful, status: ${response.statusCode}', name: _tag);
      } catch (httpError) {
        developer.log('❌ HTTP test failed: $httpError', name: _tag, level: 1000);
      }
      
      developer.log('=== End Debug Test ===', name: _tag);
    } catch (e) {
      developer.log('❌ Debug connection test failed: $e', name: _tag, level: 1000);
    }
  }
  
  // Background service implementation
  
  final ServiceInstance _service;
  WebSocketChannel? _webSocket;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  // Connection state
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 5);
  static const Duration _maxReconnectDelay = Duration(minutes: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  
  // Message queue for offline messages
  final List<Map<String, dynamic>> _messageQueue = [];
  static const int _maxQueueSize = 100;
  
  _BackgroundServiceImpl(this._service);

  /// Initialize the background service
  Future<void> initialize() async {
    developer.log('Initializing background service implementation', name: _tag);
    
    // Setup heartbeat timer
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    
    // Update service notification
    await _updateServiceNotification('Initialized', 'WebSocket service ready');
  }

  /// Connect to WebSocket
  Future<void> connect({required String username, String? token}) async {
    try {
      // Validate username
      if (username.isEmpty) {
        throw ArgumentError('Username cannot be empty');
      }
      
      developer.log('Connecting to WebSocket: $username', name: _tag);
      
      _shouldReconnect = true;
      _reconnectAttempts = 0;
      
      await _initiateConnection(username, token);
    } catch (e) {
      developer.log('Connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Disconnect from WebSocket
  void disconnect() {
    developer.log('Disconnecting WebSocket', name: _tag);
    
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _isConnected = false;
    
    _updateServiceNotification('Disconnected', 'WebSocket disconnected');
  }

  /// Send message via WebSocket
  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (_isConnected && _webSocket != null) {
      try {
        _webSocket!.sink.add(jsonEncode(message));
        developer.log('Message sent: ${message['type']}', name: _tag);
      } catch (e) {
        developer.log('Failed to send message: $e', name: _tag, level: 900);
        _queueMessage(message);
      }
    } else {
      developer.log('WebSocket not connected, queuing message', name: _tag, level: 900);
      _queueMessage(message);
    }
  }

  /// Initiate WebSocket connection
  Future<void> _initiateConnection(String username, String? token) async {
    try {
      // Validate username
      if (username.isEmpty) {
        throw ArgumentError('Username cannot be empty');
      }
      
      // Clean and validate username
      final cleanUsername = username.trim();
      if (cleanUsername.isEmpty) {
        throw ArgumentError('Username cannot be empty after trimming');
      }
      
      // Build WebSocket URL more safely with proper encoding
      final encodedUsername = Uri.encodeComponent(cleanUsername);
      
      // Construct URL directly to avoid Uri.replace() issues
      final wsUrlString = '$_wsUrl$encodedUsername/';
      final wsUri = Uri.parse(wsUrlString);
      
      // Validate the constructed URI
      if (wsUri.scheme != 'wss' && wsUri.scheme != 'ws') {
        throw ArgumentError('Invalid WebSocket scheme: ${wsUri.scheme}');
      }
      if (wsUri.host.isEmpty) {
        throw ArgumentError('Invalid WebSocket host');
      }
      if (wsUri.hasPort && wsUri.port == 0) {
        throw ArgumentError('Invalid WebSocket port: ${wsUri.port}');
      }
      if (wsUri.fragment.isNotEmpty) {
        developer.log('Warning: WebSocket URL has fragment: ${wsUri.fragment}', name: _tag, level: 900);
      }
      
      developer.log('Connecting with username: "$cleanUsername"', name: _tag);
      developer.log('Encoded username: "$encodedUsername"', name: _tag);
      developer.log('WebSocket URL: $wsUri', name: _tag);
      developer.log('URL components - scheme: ${wsUri.scheme}, host: ${wsUri.host}, path: ${wsUri.path}', name: _tag);
      
      // Test basic connectivity first
      try {
        final testUri = Uri.parse('https://${wsUri.host}/');
        developer.log('Testing basic connectivity to: $testUri', name: _tag);
        final response = await http.head(testUri).timeout(Duration(seconds: 5));
        developer.log('Basic connectivity test successful, status: ${response.statusCode}', name: _tag);
      } catch (connectivityError) {
        developer.log('Basic connectivity test failed: $connectivityError', name: _tag, level: 900);
        // Continue anyway, might still work
      }

      // Attempt WebSocket connection with specific error handling and timeout
      try {
        developer.log('🚀 FINAL URL BEING PASSED TO WebSocketChannel.connect(): $wsUri', name: _tag);
        developer.log('🚀 URL toString(): ${wsUri.toString()}', name: _tag);
        developer.log('🚀 URL components: scheme=${wsUri.scheme}, host=${wsUri.host}, port=${wsUri.hasPort ? wsUri.port : 'default'}, path=${wsUri.path}, query=${wsUri.query}, fragment=${wsUri.fragment}', name: _tag);
        
        // Create WebSocket connection with timeout
        _webSocket = WebSocketChannel.connect(
          wsUri,
          protocols: null, // No specific protocols
        );
        
        developer.log('WebSocketChannel.connect() returned successfully', name: _tag);
        
        developer.log('WebSocket channel created, setting up stream listener...', name: _tag);
        
        // Listen to the stream with error handling
        _subscription = _webSocket!.stream.listen(
          _onMessage,
          onError: (error) {
            developer.log('WebSocket stream error: $error', name: _tag, level: 1000);
            _onError(error);
          },
          onDone: () {
            developer.log('WebSocket stream closed', name: _tag);
            _onDisconnected();
          },
        );
        
        developer.log('WebSocket stream listener set up successfully', name: _tag);
        
      } catch (wsError) {
        developer.log('WebSocketChannel.connect() failed: $wsError', name: _tag, level: 1000);
        developer.log('WebSocket error type: ${wsError.runtimeType}', name: _tag, level: 1000);
        
        // Provide more specific error information
        final errorString = wsError.toString();
        if (errorString.contains('Certificate')) {
          developer.log('❌ SSL Certificate issue detected', name: _tag, level: 1000);
        } else if (errorString.contains('HTTP status code: 500')) {
          developer.log('❌ Server error (HTTP 500) - Server is having issues', name: _tag, level: 1000);
        } else if (errorString.contains('HTTP status code: 404')) {
          developer.log('❌ Endpoint not found (HTTP 404) - Check WebSocket URL', name: _tag, level: 1000);
        } else if (errorString.contains('HTTP status code: 403')) {
          developer.log('❌ Access forbidden (HTTP 403) - Check authentication', name: _tag, level: 1000);
        } else if (errorString.contains('not upgraded to websocket')) {
          developer.log('❌ WebSocket upgrade failed - Server rejected WebSocket connection', name: _tag, level: 1000);
        } else if (errorString.contains('network') || errorString.contains('connection')) {
          developer.log('❌ Network connectivity issue detected', name: _tag, level: 1000);
        } else if (errorString.contains('handshake')) {
          developer.log('❌ WebSocket handshake failed', name: _tag, level: 1000);
        }
        
        rethrow;
      }
      
      // Connection successful
      _isConnected = true;
      _reconnectAttempts = 0;
      
      developer.log('WebSocket connected successfully', name: _tag);
      await _updateServiceNotification('Connected', 'Chat service running');
      
      // Send authentication if token provided
      if (token != null) {
        await sendMessage({
          'type': 'authenticate',
          'token': token,
          'username': username,
        });
      }
      
      // Flush queued messages
      await _flushMessageQueue();
      
    } catch (e) {
      developer.log('Connection failed: $e', name: _tag, level: 1000);
      _onError(e);
    }
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString()) as Map<String, dynamic>;
      developer.log('Received message: ${data['type']}', name: _tag);
      
      // Handle different message types
      switch (data['type']) {
        case 'new_message':
          _handleNewMessage(data);
          break;
        case 'typing':
          _handleTyping(data);
          break;
        case 'message_status':
          _handleMessageStatus(data);
          break;
        case 'heartbeat_response':
          // Heartbeat acknowledged
          break;
        default:
          developer.log('Unknown message type: ${data['type']}', name: _tag);
      }
      
      // Send message to main app if it's running
      _service.invoke('websocket_message', {'data': data});
      
    } catch (e) {
      developer.log('Error processing message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle new message
  void _handleNewMessage(Map<String, dynamic> data) {
    final senderName = data['sender_name'] as String? ?? 'Unknown';
    final content = data['content'] as String? ?? '';
    final chatId = data['chat_id'] as String?;
    
    // Show notification for new message
    BackgroundWebSocketService.showMessageNotification(
      title: senderName,
      body: content,
      chatId: chatId,
    );
    
    // Store message locally (could implement local storage here)
    developer.log('New message from $senderName: $content', name: _tag);
  }

  /// Handle typing indicator
  void _handleTyping(Map<String, dynamic> data) {
    // Forward typing indicator to main app
    developer.log('Typing indicator: ${data['username']} in ${data['chat_id']}', name: _tag);
  }

  /// Handle message status update
  void _handleMessageStatus(Map<String, dynamic> data) {
    developer.log('Message status: ${data['message_id']} -> ${data['status']}', name: _tag);
  }

  /// Handle WebSocket errors
  void _onError(dynamic error) {
    developer.log('WebSocket error: $error', name: _tag, level: 1000);
    _isConnected = false;
    
    if (_shouldReconnect) {
      // Check if it's a server error (5xx) for different retry strategy
      final errorString = error.toString();
      final isServerError = errorString.contains('HTTP status code: 5') ||
                           errorString.contains('status code: 500') ||
                           errorString.contains('status code: 502') ||
                           errorString.contains('status code: 503') ||
                           errorString.contains('status code: 504');
      
      if (isServerError) {
        developer.log('Server error detected, using longer retry delay', name: _tag, level: 900);
      }
      
      _scheduleReconnect(isServerError: isServerError);
    }
  }

  /// Handle WebSocket disconnection
  void _onDisconnected() {
    developer.log('WebSocket disconnected', name: _tag, level: 900);
    _isConnected = false;
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect({bool isServerError = false}) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      developer.log('Max reconnect attempts reached', name: _tag, level: 1000);
      _updateServiceNotification('Failed', 'Connection failed');
      return;
    }

    // Use longer delay for server errors (5xx) since it's not a client issue
    final baseDelay = isServerError ? 
      Duration(seconds: 10) : // Server errors: start with 10s delay
      _initialReconnectDelay;   // Client errors: use normal delay
    
    final delay = Duration(
      milliseconds: (baseDelay.inMilliseconds * 
        (1 << _reconnectAttempts)).clamp(
          baseDelay.inMilliseconds,
          _maxReconnectDelay.inMilliseconds,
        ),
    );

    _reconnectAttempts++;
    developer.log('Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)', name: _tag);
    
    _updateServiceNotification(
      'Reconnecting...', 
      'Attempt $_reconnectAttempts in ${delay.inSeconds}s'
    );
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _retryConnection());
  }

  /// Retry connection
  Future<void> _retryConnection() async {
    try {
      // Get stored connection info
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('websocket_username');
      final token = prefs.getString('websocket_token');
      
      developer.log('Retry connection - stored username: "$username", has token: ${token != null}', name: _tag);
      
      if (username != null && username.isNotEmpty && username.trim().isNotEmpty) {
        await _initiateConnection(username.trim(), token);
      } else {
        developer.log('No valid stored username for reconnection (username: "$username")', name: _tag, level: 900);
        // Stop reconnection attempts if no valid username
        _shouldReconnect = false;
        await _updateServiceNotification('Failed', 'No username for connection');
      }
    } catch (e) {
      developer.log('Reconnection failed: $e', name: _tag, level: 1000);
      _onError(e);
    }
  }

  /// Send heartbeat to keep connection alive
  void _sendHeartbeat() {
    if (_isConnected && _webSocket != null) {
      try {
        _webSocket!.sink.add(jsonEncode({
          'type': 'heartbeat',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        developer.log('Heartbeat sent', name: _tag);
      } catch (e) {
        developer.log('Failed to send heartbeat: $e', name: _tag, level: 900);
      }
    }
  }

  /// Queue message for later sending
  void _queueMessage(Map<String, dynamic> message) {
    if (_messageQueue.length >= _maxQueueSize) {
      _messageQueue.removeAt(0); // Remove oldest message
    }
    _messageQueue.add(message);
    developer.log('Message queued (${_messageQueue.length})', name: _tag);
  }

  /// Flush queued messages
  Future<void> _flushMessageQueue() async {
    while (_messageQueue.isNotEmpty && _isConnected) {
      final message = _messageQueue.removeAt(0);
      try {
        _webSocket!.sink.add(jsonEncode(message));
        developer.log('Queued message sent: ${message['type']}', name: _tag);
        
        // Small delay between messages
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        developer.log('Failed to send queued message: $e', name: _tag, level: 900);
        _messageQueue.insert(0, message); // Re-queue
        break;
      }
    }
    
    if (_messageQueue.isEmpty) {
      developer.log('All queued messages sent', name: _tag);
    }
  }

  /// Update service notification
  Future<void> _updateServiceNotification(String title, String content) async {
    try {
      if (_service is AndroidServiceInstance) {
        await _service.setForegroundNotificationInfo(
          title: 'HiChat - $title',
          content: content,
        );
      }
    } catch (e) {
      developer.log('Failed to update notification: $e', name: _tag, level: 900);
    }
  }

  /// Dispose resources
  void dispose() {
    developer.log('Disposing background service', name: _tag);
    
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _messageQueue.clear();
  }
}