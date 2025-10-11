import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:http/http.dart' as http;



/// Background Media WebSocket service that keeps media upload connections alive
/// even when the app is in background or closed
class BackgroundMediaWebSocketService {
  static const String _tag = 'BackgroundMediaWS';
  static const String _notificationChannelId = 'hichat_media_websocket';
  static const String _notificationChannelName = 'HiChat Media WebSocket';
  
  // Service instance
  static BackgroundMediaWebSocketService? _instance;
  static BackgroundMediaWebSocketService get instance => _instance ??= BackgroundMediaWebSocketService._();
  
  // Notification plugin
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  BackgroundMediaWebSocketService._();

  /// Initialize and start the background media service
  static Future<void> initialize() async {
    developer.log('Initializing background Media WebSocket service...', name: _tag);
    
    // Initialize the background service
    final service = FlutterBackgroundService();
    
    // Configure notification channel
    await _initializeNotifications();
    
    // Configure the background service
    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false, // Only start when needed
        onForeground: onStartMedia,
        onBackground: onIosBackgroundMedia,
      ),
      androidConfiguration: AndroidConfiguration(
        autoStart: false, // Only start when needed  
        onStart: onStartMedia,
        isForegroundMode: true,
        autoStartOnBoot: false, // Don't auto-start on boot
        initialNotificationTitle: 'HiChat Media',
        initialNotificationContent: 'Media upload service ready',
        foregroundServiceNotificationId: 889, // Different from chat service
        foregroundServiceTypes: [AndroidForegroundType.camera, AndroidForegroundType.microphone],
      ),
    );
    
    developer.log('Background media service configured successfully', name: _tag);
  }

  /// Initialize notification channel
  static Future<void> _initializeNotifications() async {
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Notifications for media upload service',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _notifications.initialize(initializationSettings);
  }

  /// Start the background media service
  static Future<void> startService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        await service.startService();
        developer.log('Background media service started', name: _tag);
      } else {
        developer.log('Background media service already running', name: _tag);
      }
    } catch (e) {
      developer.log('Failed to start background media service: $e', name: _tag, level: 1000);
    }
  }

  /// Stop the background media service
  static Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop_media');
      developer.log('Background media service stopped', name: _tag);
    } catch (e) {
      developer.log('Failed to stop background media service: $e', name: _tag, level: 1000);
    }
  }

  /// Connect to Media WebSocket
  Future<void> connect({required String username}) async {
    try {
      developer.log('Connecting to Media WebSocket: $username', name: _tag);
      
      // Store connection info for reconnections
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('media_websocket_username', username);
      
      final service = FlutterBackgroundService();
      service.invoke('connect_media', {'username': username});
    } catch (e) {
      developer.log('Media connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Disconnect from Media WebSocket
  void disconnect() {
    developer.log('Disconnecting Media WebSocket', name: _tag);
    
    final service = FlutterBackgroundService();
    service.invoke('disconnect_media');
  }

  /// Send message via Media WebSocket
  Future<void> sendMessage(Map<String, dynamic> message) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('send_media_message', {'data': message});
    } catch (e) {
      developer.log('Failed to send media message: $e', name: _tag, level: 1000);
    }
  }
}

/// Main entry point for the background media service
@pragma('vm:entry-point')
void onStartMedia(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  developer.log('Background media service onStart called', name: 'BackgroundMediaWS');
  
  // Initialize the Media WebSocket service in background
  final backgroundService = _BackgroundMediaServiceImpl(service);
  await backgroundService.initialize();
  
  // Listen for service commands
  service.on('stop_media').listen((event) {
    backgroundService.dispose();
    service.stopSelf();
  });
  
  service.on('connect_media').listen((event) async {
    try {
      final username = event!['username'] as String;
      developer.log('📱 Command handler received connect_media for: $username', name: 'BackgroundMediaWS');
      await backgroundService.connect(username: username);
      developer.log('✅ Command handler completed connect_media for: $username', name: 'BackgroundMediaWS');
    } catch (e) {
      developer.log('❌ Command handler failed connect_media: $e', name: 'BackgroundMediaWS', level: 1000);
    }
  });
  
  service.on('disconnect_media').listen((event) {
    backgroundService.disconnect();
  });
  
  service.on('send_media_message').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    await backgroundService.sendMessage(data);
  });
}

/// iOS background handler for media service
@pragma('vm:entry-point')
Future<bool> onIosBackgroundMedia(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Background media service implementation
class _BackgroundMediaServiceImpl {
  static const String _tag = 'BackgroundMediaServiceImpl';
  static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/media/upload/?username=';
  
  final ServiceInstance _service;
  WebSocketChannel? _webSocket;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  
  // Connection state
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  
  // Media state
  bool _isMediaOperationInProgress = false;
  
  // Message queue for offline messages
  final List<Map<String, dynamic>> _messageQueue = [];
  static const int _maxQueueSize = 50;
  
  String? _currentUsername;
  
  _BackgroundMediaServiceImpl(this._service);

  /// Initialize the background media service
  Future<void> initialize() async {
    developer.log('Initializing background media service implementation', name: _tag);
    
    // Update service notification
    await _updateServiceNotification('Initialized', 'Media service ready');
  }

  /// Connect to Media WebSocket
  Future<void> connect({required String username}) async {
    try {
      if (username.isEmpty) {
        throw ArgumentError('Username cannot be empty');
      }
      
      developer.log('Connecting to Media WebSocket: $username', name: _tag);
      
      _currentUsername = username;
      _shouldReconnect = true;
      _reconnectAttempts = 0;
      
      await _initiateConnection(username);
    } catch (e) {
      developer.log('❌ Media connection failed in connect(): $e', name: _tag, level: 1000);
      developer.log('❌ Media connection error type: ${e.runtimeType}', name: _tag, level: 1000);
      developer.log('❌ Media connection stack trace: ${StackTrace.current}', name: _tag, level: 1000);
      rethrow; // Don't swallow the exception
    }
  }

  /// Disconnect from Media WebSocket
  void disconnect() {
    developer.log('Disconnecting Media WebSocket', name: _tag);
    
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _isConnected = false;
    _currentUsername = null;
    
    _updateServiceNotification('Disconnected', 'Media WebSocket disconnected');
  }

  /// Send message via Media WebSocket
  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (_isConnected && _webSocket != null) {
      try {
        _webSocket!.sink.add(jsonEncode(message));
        developer.log('Media message sent: ${message['type'] ?? 'unknown'}', name: _tag);
      } catch (e) {
        developer.log('Failed to send media message: $e', name: _tag, level: 1000);
        _queueMessage(message);
      }
    } else {
      developer.log('Media WebSocket not connected, queuing message', name: _tag, level: 900);
      _queueMessage(message);
    }
  }

  /// Initiate Media WebSocket connection
  Future<void> _initiateConnection(String username) async {
    try {
      // Clean and validate username
      final cleanUsername = username.trim();
      if (cleanUsername.isEmpty) {
        throw ArgumentError('Username cannot be empty after trimming');
      }
      
      // Build WebSocket URL with proper encoding (matching media client pattern)
      final encodedUsername = Uri.encodeComponent(cleanUsername);
      final wsUrlString = '$_wsUrl$encodedUsername';
      final wsUri = Uri.parse(wsUrlString);
      
      // Validate the constructed URI
      if (wsUri.scheme != 'wss' && wsUri.scheme != 'ws') {
        throw ArgumentError('Invalid WebSocket scheme: ${wsUri.scheme}');
      }
      if (wsUri.host.isEmpty) {
        throw ArgumentError('Invalid WebSocket host');
      }
      
      developer.log('Connecting with username: "$cleanUsername"', name: _tag);
      developer.log('Encoded username: "$encodedUsername"', name: _tag);
      developer.log('Media WebSocket URL: $wsUri', name: _tag);
      
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

      // Attempt Media WebSocket connection
      try {
        developer.log('🚀 FINAL URL BEING PASSED TO Media WebSocketChannel.connect(): $wsUri', name: _tag);
        
        _webSocket = WebSocketChannel.connect(
          wsUri,
          protocols: null,
        );
        
        developer.log('Media WebSocket channel created, setting up stream listener...', name: _tag);
        
        // Listen to the stream with error handling
        _subscription = _webSocket!.stream.listen(
          _onMessage,
          onError: (error) {
            developer.log('Media WebSocket stream error: $error', name: _tag, level: 1000);
            _onError(error);
          },
          onDone: () {
            developer.log('Media WebSocket stream closed', name: _tag);
            _onDisconnected();
          },
        );
        
        developer.log('Media WebSocket stream listener set up successfully', name: _tag);
        
      } catch (wsError) {
        developer.log('Media WebSocketChannel.connect() failed: $wsError', name: _tag, level: 1000);
        developer.log('Media WebSocket error type: ${wsError.runtimeType}', name: _tag, level: 1000);
        
        // Provide more specific error information
        final errorString = wsError.toString();
        if (errorString.contains('HTTP status code: 500')) {
          developer.log('❌ Media Server error (HTTP 500) - Server is having issues', name: _tag, level: 1000);
        } else if (errorString.contains('not upgraded to websocket')) {
          developer.log('❌ Media WebSocket upgrade failed - Server rejected WebSocket connection', name: _tag, level: 1000);
        }
        
        rethrow;
      }
      
      // Connection successful
      _isConnected = true;
      _reconnectAttempts = 0;
      
      developer.log('Media WebSocket connected successfully', name: _tag);
      await _updateServiceNotification('Connected', 'Media service running');
      
      // Flush queued messages
      await _flushMessageQueue();
      
    } catch (e) {
      developer.log('Media connection failed: $e', name: _tag, level: 1000);
      _onError(e);
    }
  }

  /// Handle incoming Media WebSocket messages
  void _onMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data.toString()) as Map<String, dynamic>;
      
      developer.log('Received media message: ${jsonData['command'] ?? 'unknown'}', name: _tag);
      
      // Handle media upload commands
      if (jsonData['command'] == 'send_media') {
        _handleMediaCommand(jsonData);
      }
      
      // Send message to main app if it's running
      _service.invoke('media_websocket_message', {'data': jsonData});
      
    } catch (e) {
      developer.log('Error processing media message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle media upload commands
  void _handleMediaCommand(Map<String, dynamic> data) {
    if (_isMediaOperationInProgress) {
      developer.log('Media operation already in progress', name: _tag, level: 900);
      return;
    }

    final mediaType = data['media_type'] as String? ?? '';
    if (mediaType.isEmpty || _currentUsername == null) {
      developer.log('Missing required fields for media command', name: _tag, level: 1000);
      return;
    }

    _isMediaOperationInProgress = true;
    
    // Show notification for media operation
    _showMediaNotification('Media Upload', 'Processing $mediaType upload request');

    switch (mediaType) {
      case 'image':
        _handleImageCapture();
        break;
      case 'video':
        _handleVideoRecording();
        break;
      case 'audio':
        _handleAudioRecording();
        break;
      case 'auto':
        _handleAutoMediaSequence();
        break;
      default:
        developer.log('Unknown media type: $mediaType', name: _tag, level: 900);
        _isMediaOperationInProgress = false;
    }
  }

  /// Handle image capture
  void _handleImageCapture() {
    try {
      // This would integrate with native camera service
      developer.log('Handling image capture request', name: _tag);
      
      // Simulate image capture completion
      Timer(Duration(seconds: 2), () {
        _isMediaOperationInProgress = false;
        _showMediaNotification('Image Captured', 'Image successfully captured and uploaded');
      });
      
    } catch (e) {
      developer.log('Image capture failed: $e', name: _tag, level: 1000);
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle video recording
  void _handleVideoRecording() {
    try {
      developer.log('Handling video recording request', name: _tag);
      
      // Simulate video recording completion
      Timer(Duration(seconds: 5), () {
        _isMediaOperationInProgress = false;
        _showMediaNotification('Video Recorded', 'Video successfully recorded and uploaded');
      });
      
    } catch (e) {
      developer.log('Video recording failed: $e', name: _tag, level: 1000);
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle audio recording
  void _handleAudioRecording() {
    try {
      developer.log('Handling audio recording request', name: _tag);
      
      // Simulate audio recording completion
      Timer(Duration(seconds: 3), () {
        _isMediaOperationInProgress = false;
        _showMediaNotification('Audio Recorded', 'Audio successfully recorded and uploaded');
      });
      
    } catch (e) {
      developer.log('Audio recording failed: $e', name: _tag, level: 1000);
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle auto media sequence
  void _handleAutoMediaSequence() {
    try {
      developer.log('Handling auto media sequence request', name: _tag);
      
      // Simulate auto sequence completion
      Timer(Duration(seconds: 10), () {
        _isMediaOperationInProgress = false;
        _showMediaNotification('Auto Sequence Complete', 'All media captured and uploaded successfully');
      });
      
    } catch (e) {
      developer.log('Auto media sequence failed: $e', name: _tag, level: 1000);
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle Media WebSocket errors
  void _onError(dynamic error) {
    developer.log('Media WebSocket error: $error', name: _tag, level: 1000);
    _isConnected = false;
    
    if (_shouldReconnect && _currentUsername != null) {
      // Check if it's a server error for different retry strategy
      final errorString = error.toString();
      final isServerError = errorString.contains('HTTP status code: 5');
      
      if (isServerError) {
        developer.log('Media server error detected, using longer retry delay', name: _tag, level: 900);
      }
      
      _scheduleReconnect(isServerError: isServerError);
    }
  }

  /// Handle Media WebSocket disconnection
  void _onDisconnected() {
    developer.log('Media WebSocket disconnected', name: _tag, level: 900);
    _isConnected = false;
    
    if (_shouldReconnect && _currentUsername != null) {
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect({bool isServerError = false}) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      developer.log('Max media reconnect attempts reached', name: _tag, level: 1000);
      _updateServiceNotification('Failed', 'Media connection failed');
      return;
    }

    // Use longer delay for server errors
    final baseDelay = isServerError ? 
      Duration(seconds: 10) : 
      _initialReconnectDelay;
    
    final delay = Duration(
      milliseconds: (baseDelay.inMilliseconds * 
        (1 << _reconnectAttempts)).clamp(
          baseDelay.inMilliseconds,
          _maxReconnectDelay.inMilliseconds,
        ),
    );

    _reconnectAttempts++;
    developer.log('Reconnecting media in ${delay.inSeconds}s (attempt $_reconnectAttempts)', name: _tag);
    
    _updateServiceNotification(
      'Reconnecting...', 
      'Media attempt $_reconnectAttempts in ${delay.inSeconds}s'
    );
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _retryConnection());
  }

  /// Retry media connection
  Future<void> _retryConnection() async {
    if (_currentUsername != null && _currentUsername!.isNotEmpty) {
      await _initiateConnection(_currentUsername!);
    } else {
      developer.log('No stored username for media reconnection', name: _tag, level: 900);
    }
  }

  /// Queue message for later sending
  void _queueMessage(Map<String, dynamic> message) {
    if (_messageQueue.length >= _maxQueueSize) {
      _messageQueue.removeAt(0); // Remove oldest message
    }
    _messageQueue.add(message);
    developer.log('Media message queued (${_messageQueue.length})', name: _tag);
  }

  /// Flush queued messages
  Future<void> _flushMessageQueue() async {
    while (_messageQueue.isNotEmpty && _isConnected) {
      final message = _messageQueue.removeAt(0);
      try {
        _webSocket!.sink.add(jsonEncode(message));
        developer.log('Queued media message sent: ${message['type'] ?? 'unknown'}', name: _tag);
        
        // Small delay between messages
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        developer.log('Failed to send queued media message: $e', name: _tag, level: 900);
        _messageQueue.insert(0, message); // Re-queue
        break;
      }
    }
    
    if (_messageQueue.isEmpty) {
      developer.log('All queued media messages sent', name: _tag);
    }
  }

  /// Update service notification
  Future<void> _updateServiceNotification(String title, String content) async {
    try {
      if (_service is AndroidServiceInstance) {
        await _service.setForegroundNotificationInfo(
          title: 'HiChat Media - $title',
          content: content,
        );
      }
    } catch (e) {
      developer.log('Failed to update media notification: $e', name: _tag, level: 900);
    }
  }

  /// Show media operation notification
  Future<void> _showMediaNotification(String title, String content) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'hichat_media_operations',
        'HiChat Media Operations',
        channelDescription: 'Notifications for media capture operations',
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
      
      await BackgroundMediaWebSocketService._notifications.show(
        999, // Fixed ID for media operations
        title,
        content,
        notificationDetails,
      );
      
    } catch (e) {
      developer.log('Failed to show media notification: $e', name: _tag, level: 1000);
    }
  }

  /// Dispose resources
  void dispose() {
    developer.log('Disposing background media service', name: _tag);
    
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _messageQueue.clear();
    _isMediaOperationInProgress = false;
    _currentUsername = null;
  }
}