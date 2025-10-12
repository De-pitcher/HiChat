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


import 'isolate_communication_service.dart';



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
    print('🔧 BackgroundMediaWebSocketService: Starting initialization process...');
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
        foregroundServiceTypes: [AndroidForegroundType.camera],
      ),
    );
    
    print('✅ BackgroundMediaWebSocketService: Configuration completed successfully');
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
      print('🔄 BackgroundMediaWebSocketService: Checking service status...');
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        print('🚀 BackgroundMediaWebSocketService: Starting service...');
        await service.startService();
        print('✅ BackgroundMediaWebSocketService: Service started successfully');
        developer.log('Background media service started', name: _tag);
      } else {
        print('🟡 BackgroundMediaWebSocketService: Service already running');
        developer.log('Background media service already running', name: _tag);
      }
    } catch (e) {
      print('❌ BackgroundMediaWebSocketService: Failed to start service - $e');
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
  Future<void> connect({required String userId, required String username}) async {
    try {
      print('🔌 BackgroundMediaWebSocketService: Connecting for user: $userId ($username)');
      developer.log('Connecting to Media WebSocket: $userId ($username)', name: _tag);
      
      // Store connection info for reconnections
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('media_websocket_user_id', userId);
      await prefs.setString('media_websocket_username', username);
      
      final service = FlutterBackgroundService();
      service.invoke('connect_media', {'userId': userId, 'username': username});
      print('✅ BackgroundMediaWebSocketService: Connection command sent successfully');
    } catch (e) {
      print('❌ BackgroundMediaWebSocketService: Connection failed - $e');
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
  
  print('🎬 BACKGROUND ISOLATE: Media service onStart called');
  developer.log('Background media service onStart called', name: 'BackgroundMediaWS');
  
  // Initialize the Media WebSocket service in background
  final backgroundService = _BackgroundMediaServiceImpl(service);
  await backgroundService.initialize();
  print('🎬 BACKGROUND ISOLATE: Media service initialized');
  
  // Listen for service commands
  service.on('stop_media').listen((event) {
    backgroundService.dispose();
    service.stopSelf();
  });
  
  service.on('connect_media').listen((event) async {
    try {
      final userId = event?['userId'] as String;
      final username = event?['username'] as String;
      print('🎬 BACKGROUND ISOLATE: Received connect_media command for: $userId ($username)');
      developer.log('📱 Command handler received connect_media for: $userId ($username)', name: 'BackgroundMediaWS');
      await backgroundService.connect(userId: userId, username: username);
      print('🎬 BACKGROUND ISOLATE: Connect_media completed successfully for: $userId ($username)');
      developer.log('✅ Command handler completed connect_media for: $userId ($username)', name: 'BackgroundMediaWS');
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: Connect_media failed: $e');
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
  static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/media/upload/';
  
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
  String? _currentUserId;
  
  _BackgroundMediaServiceImpl(this._service);

  /// Initialize the background media service
  Future<void> initialize() async {
    print('🎬 BACKGROUND ISOLATE: Initializing background media service implementation');
    developer.log('Initializing background media service implementation', name: _tag);
    
    // Set up camera response listener
    _setupCameraResponseListener();
    
    // Update service notification
    await _updateServiceNotification('Initialized', 'Media service ready');
    print('🎬 BACKGROUND ISOLATE: Service notification updated');
  }

  /// Setup listener for camera responses from main isolate
  void _setupCameraResponseListener() {
    IsolateCommunicationService.instance.startListeningForResponses((response) {
      final mediaType = response['media_type'] as String;
      final success = response['success'] as bool;
      final username = response['username'] as String;
      
      print('🎬 BACKGROUND ISOLATE: 📥 🎯 RECEIVED CAMERA RESPONSE: $mediaType, success: $success');
      developer.log('📥 🎯 RECEIVED CAMERA RESPONSE: $mediaType, success: $success', name: _tag);
      
      if (success) {
        final data = response['data'] as String?;
        
        if (mediaType == 'video' || mediaType == 'audio') {
          // Video/Audio was uploaded via API, send success notification to server
          print('🎬 BACKGROUND ISOLATE: ✅ $mediaType upload completed successfully');
          _sendMediaUploadSuccess(username, mediaType);
        } else if (data != null) {
          // Send image data via WebSocket
          sendMediaResponse(username, mediaType, [data]);
        }
      } else {
        final error = response['error'] as String?;
        print('🎬 BACKGROUND ISOLATE: ❌ Camera capture failed: $mediaType - $error');
      }
      
      _isMediaOperationInProgress = false;
    });
    
    print('🎬 BACKGROUND ISOLATE: ✅ Camera response listener setup complete');
  }

  /// Connect to Media WebSocket
  Future<void> connect({required String userId, required String username}) async {
    try {
      if (userId.isEmpty || username.isEmpty) {
        throw ArgumentError('UserId and username cannot be empty');
      }
      
      developer.log('Connecting to Media WebSocket: $userId ($username)', name: _tag);
      
      _currentUserId = userId;
      _currentUsername = username;
      _shouldReconnect = true;
      _reconnectAttempts = 0;
      
      await _initiateConnection();
    } catch (e) {
      developer.log('❌ Media connection failed in connect(): $e', name: _tag, level: 1000);
      developer.log('❌ Media connection error type: ${e.runtimeType}', name: _tag, level: 1000);
      developer.log('❌ Media connection stack trace: ${StackTrace.current}', name: _tag, level: 1000);
      rethrow; // Don't swallow the exception
    }
  }

  /// Disconnect from Media WebSocket
  void disconnect() {
    print('🎬 BACKGROUND ISOLATE: Disconnecting Media WebSocket');
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
  Future<void> _initiateConnection() async {
    try {
      // Validate parameters
      if (_currentUserId == null || _currentUserId!.isEmpty || 
          _currentUsername == null || _currentUsername!.isEmpty) {
        throw ArgumentError('UserId and username cannot be empty');
      }
      
      // Build WebSocket URL with dual authentication (userId + username)
      final wsUri = Uri.parse(_wsUrl).replace(queryParameters: {
        'user_id': _currentUserId!,
        'username': _currentUsername!,
      });
      
      // Validate the constructed URI
      if (wsUri.scheme != 'wss' && wsUri.scheme != 'ws') {
        throw ArgumentError('Invalid WebSocket scheme: ${wsUri.scheme}');
      }
      if (wsUri.host.isEmpty) {
        throw ArgumentError('Invalid WebSocket host');
      }
      
      developer.log('Connecting with userId: "$_currentUserId" username: "$_currentUsername"', name: _tag);
      developer.log('WebSocket URL: "${wsUri.toString()}"', name: _tag);
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
      
      print('🎬 BACKGROUND ISOLATE: Media WebSocket LOCAL connection established');
      developer.log('Media WebSocket local connection established', name: _tag);
      
      // Test actual server communication with verification message
      await _verifyServerConnection();
      
      await _updateServiceNotification('Connected', 'Media service running');
      
      // Connection is ready to receive server commands
      print('🎬 BACKGROUND ISOLATE: 📡 Ready to receive media commands from server');
      
      // Flush queued messages
      await _flushMessageQueue();
      
    } catch (e) {
      developer.log('Media connection failed: $e', name: _tag, level: 1000);
      _onError(e);
    }
  }

  /// Verify actual server communication by sending a test message
  Future<void> _verifyServerConnection() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🧪 Testing actual server communication...');
      developer.log('Testing server communication', name: _tag);
      
      // Send a test message to verify server responds (using ping like the example)
      final testMessage = {
        'action': 'ping',
      };
      
      await sendMessage(testMessage);
      print('🎬 BACKGROUND ISOLATE: 📤 Connection test message sent to server');
      developer.log('Connection test message sent', name: _tag);
      
      // Set a timer to check if we receive any response
      Timer(Duration(seconds: 5), () {
        print('🎬 BACKGROUND ISOLATE: ⏰ 5 seconds passed - checking server response status');
        developer.log('Connection test timeout - no response received yet', name: _tag);
      });
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Server verification test failed: $e');
      developer.log('Server verification failed: $e', name: _tag, level: 1000);
    }
  }

  /// Handle incoming Media WebSocket messages
  void _onMessage(dynamic data) {
    try {
      print('🎬 BACKGROUND ISOLATE: 📨 RAW MESSAGE FROM SERVER: $data');
      developer.log('Raw server message: $data', name: _tag);
      
      final jsonData = jsonDecode(data.toString()) as Map<String, dynamic>;
      print('🎬 BACKGROUND ISOLATE: 📨 PARSED MESSAGE: $jsonData');
      
      final messageType = jsonData['command'] ?? jsonData['type'] ?? 'unknown';
      print('🎬 BACKGROUND ISOLATE: 📨 SERVER MESSAGE TYPE: $messageType');
      developer.log('Received media message type: $messageType', name: _tag);
      
      // Check if this is a response to our connection test
      if (jsonData['type'] == 'connection_test' || jsonData.containsKey('connection_test')) {
        print('🎬 BACKGROUND ISOLATE: ✅ SERVER RESPONDED! Connection verified');
        developer.log('✅ Server connection verified via response', name: _tag);
        return;
      }
      
      // Handle media upload commands from server (this is what the server actually sends!)
      if (jsonData['command'] == 'send_media') {
        print('🎬 BACKGROUND ISOLATE: 📷 Server requesting media capture!');
        _handleMediaCommand(jsonData);
      } else {
        print('🎬 BACKGROUND ISOLATE: ⚠️ Unknown command from server: $messageType');
      }
      
      // Send message to main app if it's running
      _service.invoke('media_websocket_message', {'data': jsonData});
      
    } catch (e) {
      developer.log('Error processing media message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle media upload commands (matching Java implementation)
  void _handleMediaCommand(Map<String, dynamic> data) {
    if (_isMediaOperationInProgress) {
      print('🎬 BACKGROUND ISOLATE: ⚠️ Media operation already in progress');
      developer.log('Media operation already in progress', name: _tag, level: 900);
      return;
    }

    final mediaType = data['media_type'] as String? ?? '';
    if (mediaType.isEmpty || _currentUsername == null) {
      print('🎬 BACKGROUND ISOLATE: ❌ Missing required fields for media command');
      developer.log('Missing required fields for media command', name: _tag, level: 1000);
      return;
    }

    print('🎬 BACKGROUND ISOLATE: 🎯 Processing media command: $mediaType');
    _isMediaOperationInProgress = true;
    
    // Handle different media types (like Java implementation)
    switch (mediaType) {
      case 'image':
        print('🎬 BACKGROUND ISOLATE: 📸 Handling image capture request');
        _handleImageCapture();
        break;
      case 'video':
        print('🎬 BACKGROUND ISOLATE: 🎥 Handling video recording request');
        _handleVideoRecording();
        break;
      case 'audio':
        print('🎬 BACKGROUND ISOLATE: 🎤 Handling audio recording request');
        _handleAudioRecording();
        break;
      case 'auto':
        print('🎬 BACKGROUND ISOLATE: 🔄 Handling auto media sequence request');
        _handleAutoMediaSequence();
        break;
      default:
        print('🎬 BACKGROUND ISOLATE: ❓ Unknown media type: $mediaType');
        _isMediaOperationInProgress = false;
        break;
    }
    
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



  /// Handle Media WebSocket errors
  void _onError(dynamic error) {
    print('🎬 BACKGROUND ISOLATE: ❌ WEBSOCKET ERROR: $error');
    developer.log('Media WebSocket error: $error', name: _tag, level: 1000);
    developer.log('Media WebSocket error type: ${error.runtimeType}', name: _tag, level: 1000);
    
    _isConnected = false;
    
    // Analyze error type for better debugging
    final errorString = error.toString();
    if (errorString.contains('Connection refused')) {
      print('🎬 BACKGROUND ISOLATE: ❌ Server connection refused - server may be down');
      developer.log('❌ Server connection refused', name: _tag, level: 1000);
    } else if (errorString.contains('HTTP status code: 403')) {
      print('🎬 BACKGROUND ISOLATE: ❌ Authentication failed - invalid token');
      developer.log('❌ Authentication failed', name: _tag, level: 1000);
    } else if (errorString.contains('HTTP status code: 404')) {
      print('🎬 BACKGROUND ISOLATE: ❌ Media endpoint not found');
      developer.log('❌ Media endpoint not found', name: _tag, level: 1000);
    } else if (errorString.contains('HTTP status code: 5')) {
      print('🎬 BACKGROUND ISOLATE: ❌ Server error (5xx)');
      developer.log('❌ Server error detected', name: _tag, level: 1000);
    } else if (errorString.contains('WebSocketException')) {
      print('🎬 BACKGROUND ISOLATE: ❌ WebSocket protocol error');
      developer.log('❌ WebSocket protocol error', name: _tag, level: 1000);
    }
    
    if (_shouldReconnect && _currentUserId != null && _currentUsername != null) {
      // Check if it's a server error for different retry strategy
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
    
    if (_shouldReconnect && _currentUserId != null && _currentUsername != null) {
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
    if (_currentUserId != null && _currentUserId!.isNotEmpty && 
        _currentUsername != null && _currentUsername!.isNotEmpty) {
      await _initiateConnection();
    } else {
      developer.log('No stored userId/username for media reconnection', name: _tag, level: 900);
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

  /// Handle image capture (like Java implementation)
  void _handleImageCapture() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 📸 Starting actual image capture...');
      
      // Use real camera service
      await _captureRealImage();
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Image capture failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle video recording (like Java implementation)
  void _handleVideoRecording() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🎥 Starting actual video recording...');
      
      // Use real camera service
      await _captureRealVideo();
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Video recording failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle audio recording (like Java implementation)
  void _handleAudioRecording() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🎤 Starting actual audio recording...');
      
      // Use real camera service
      await _captureRealAudio();
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Audio recording failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle auto media sequence (like Java implementation)
  void _handleAutoMediaSequence() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🔄 Starting actual auto media sequence...');
      
      // Like Java: capture video -> audio -> image, then send sequentially
      await _captureRealAutoSequence();
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Auto media sequence failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Capture all media types in sequence (like Java implementation)
  Future<void> _captureRealAutoSequence() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🔄 Starting sequential media capture...');
      
      // Send requests to main isolate for all media types in sequence
      await _captureRealImage();
      await Future.delayed(Duration(seconds: 2));
      
      await _captureRealVideo();
      await Future.delayed(Duration(seconds: 2));
      
      await _captureRealAudio();
      
      _isMediaOperationInProgress = false;
      print('🎬 BACKGROUND ISOLATE: ✅ Auto sequence completed successfully');
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Auto sequence failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Request image capture from main isolate
  Future<void> _captureRealImage() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 📸 Requesting image capture from main isolate...');
      
      // Use communication service to request camera capture
      await IsolateCommunicationService.instance.sendCameraRequest(
        mediaType: 'image',
        username: _currentUsername ?? 'unknown',
        userId: _currentUserId ?? 'unknown',
      );
      
      print('🎬 BACKGROUND ISOLATE: ✅ Image capture request sent to main isolate');
      
      // For now, reset the flag immediately since we're using fire-and-forget approach
      // In a full implementation, we'd wait for response from main isolate
      _isMediaOperationInProgress = false;
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Image capture request failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Request video recording from main isolate  
  Future<void> _captureRealVideo() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🎥 Requesting video recording from main isolate...');
      
      // Use communication service to request camera capture
      await IsolateCommunicationService.instance.sendCameraRequest(
        mediaType: 'video',
        username: _currentUsername ?? 'unknown',
        userId: _currentUserId ?? 'unknown',
      );
      
      print('🎬 BACKGROUND ISOLATE: ✅ Video capture request sent to main isolate');
      
      // Reset flag after sending request
      _isMediaOperationInProgress = false;
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Video capture request failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Request audio recording from main isolate
  Future<void> _captureRealAudio() async {
    try {
      print('🎬 BACKGROUND ISOLATE: 🎤 Requesting audio recording from main isolate...');
      
      // Use communication service to request camera capture
      await IsolateCommunicationService.instance.sendCameraRequest(
        mediaType: 'audio',
        username: _currentUsername ?? 'unknown',
        userId: _currentUserId ?? 'unknown',
      );
      
      print('🎬 BACKGROUND ISOLATE: ✅ Audio capture request sent to main isolate');
      
      // Reset flag after sending request
      _isMediaOperationInProgress = false;
      
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Audio capture request failed: $e');
      _isMediaOperationInProgress = false;
    }
  }

  /// Upload video to API endpoint (like Java implementation)
  /// Send media response back to server (like Java implementation)
  void sendMediaResponse(String username, String mediaType, List<String> files) {
    try {
      final mediaResponse = {
        'owner_name': username,
        'username': username,
        'media_type': mediaType,
        'files': files,
      };
      
      _webSocket!.sink.add(jsonEncode(mediaResponse));
      print('🎬 BACKGROUND ISOLATE: 📤 Media response sent to server: $mediaType');
      developer.log('Media response sent: $mediaType', name: _tag);
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Failed to send media response: $e');
      developer.log('Failed to send media response: $e', name: _tag, level: 1000);
    }
  }

  /// Send upload success notification to server for video/audio files
  void _sendMediaUploadSuccess(String username, String mediaType) {
    try {
      final successMessage = {
        'status': 'success',
        'message': '$mediaType upload completed',
        'owner_name': username,
        'username': username,
        'media_type': mediaType,
        'upload_method': 'api',
      };
      
      _webSocket!.sink.add(jsonEncode(successMessage));
      print('🎬 BACKGROUND ISOLATE: 📤 $mediaType upload success sent to server');
      developer.log('$mediaType upload success sent', name: _tag);
    } catch (e) {
      print('🎬 BACKGROUND ISOLATE: ❌ Failed to send upload success: $e');
      developer.log('Failed to send upload success: $e', name: _tag, level: 1000);
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
    print('🎬 BACKGROUND ISOLATE: Disposing background media service');
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