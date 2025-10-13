import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import 'isolate_communication_service.dart';

/// Unified Background WebSocket Service that handles all WebSocket connections
/// (Chat, Location, and Media) in a single background isolate
class UnifiedBackgroundWebSocketService {
  static const String _tag = 'UnifiedBackgroundWS';
  static const String _notificationChannelId = 'hichat_unified_websocket';
  static const String _notificationChannelName = 'HiChat WebSocket Services';
  
  // Service instance
  static UnifiedBackgroundWebSocketService? _instance;
  static UnifiedBackgroundWebSocketService get instance => _instance ??= UnifiedBackgroundWebSocketService._();
  
  // Initialization flag to prevent double initialization
  static bool _isInitialized = false;
  
  // Notification plugin
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  UnifiedBackgroundWebSocketService._();

  /// Initialize the unified background service
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('🔧 UnifiedBackgroundWebSocketService: Already initialized, skipping...');
      return;
    }
    
    print('🔧 UnifiedBackgroundWebSocketService: Starting initialization process...');
    developer.log('Initializing unified background WebSocket service...', name: _tag);
    
    // Check if we have location permissions to determine service types
    bool hasLocationPermissions = await _checkLocationPermissions();
    
    // Initialize the background service
    final service = FlutterBackgroundService();
    
    // Configure notification channel
    await _initializeNotifications();
    
    // Determine service types based on permissions
    List<AndroidForegroundType> serviceTypes = [
      AndroidForegroundType.camera,
      AndroidForegroundType.microphone,
    ];
    
    // Only add location type if we have the necessary permissions
    if (hasLocationPermissions) {
      serviceTypes.add(AndroidForegroundType.location);
      print('🔧 UnifiedBackgroundWebSocketService: Location permissions granted, including location service type');
    } else {
      print('🔧 UnifiedBackgroundWebSocketService: Location permissions not granted, excluding location service type');
    }
    
    // Configure the unified background service
    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onUnifiedBackgroundStart,
        onBackground: onIosUnifiedBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        autoStart: false,
        onStart: onUnifiedBackgroundStart,
        isForegroundMode: true,
        autoStartOnBoot: false,
        initialNotificationTitle: 'HiChat Services',
        initialNotificationContent: 'WebSocket services ready',
        foregroundServiceNotificationId: 999, // Unique ID for unified service
        foregroundServiceTypes: serviceTypes,
      ),
    );
    
    _isInitialized = true;
    debugPrint('✅ UnifiedBackgroundWebSocketService: Configuration completed successfully');
    developer.log('Unified background service configured successfully', name: _tag);
  }

  /// Check if location permissions are granted
  static Future<bool> _checkLocationPermissions() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('🔧 UnifiedBackgroundWebSocketService: Location services are disabled');
        return false;
      }
      
      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      
      // Return true if we have whileInUse or always permissions
      bool hasPermission = permission == LocationPermission.whileInUse || 
                          permission == LocationPermission.always;
      
      print('🔧 UnifiedBackgroundWebSocketService: Location permission status: ${permission.name}, granted: $hasPermission');
      return hasPermission;
      
    } catch (e) {
      print('🔧 UnifiedBackgroundWebSocketService: Location permission check error: $e');
      return false;
    }
  }

  /// Initialize notification channel
  static Future<void> _initializeNotifications() async {
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Notifications for all WebSocket services',
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

  /// Start the unified background service
  static Future<void> startService() async {
    try {
      print('🔄 UnifiedBackgroundWebSocketService: Checking service status...');
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      print('🔍 UnifiedBackgroundWebSocketService: Service running status: $isRunning');
      
      if (!isRunning) {
        print('🚀 UnifiedBackgroundWebSocketService: Starting service...');
        await service.startService();
        print('✅ UnifiedBackgroundWebSocketService: Service started successfully');
        developer.log('Unified background service started', name: _tag);
        
        // Wait a moment and check if it's actually running
        await Future.delayed(Duration(seconds: 1));
        final nowRunning = await service.isRunning();
        print('🔍 UnifiedBackgroundWebSocketService: Service running after start: $nowRunning');
      } else {
        print('🟡 UnifiedBackgroundWebSocketService: Service already running');
        developer.log('Unified background service already running', name: _tag);
      }
    } catch (e) {
      print('❌ UnifiedBackgroundWebSocketService: Failed to start service - $e');
      print('❌ UnifiedBackgroundWebSocketService: Error type: ${e.runtimeType}');
      developer.log('Failed to start unified background service: $e', name: _tag, level: 1000);
    }
  }

  /// Stop the unified background service
  static Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop_unified');
      developer.log('Unified background service stopped', name: _tag);
    } catch (e) {
      developer.log('Failed to stop unified background service: $e', name: _tag, level: 1000);
    }
  }

  /// Connect to Chat WebSocket
  Future<void> connectChat({required int userId, required String token}) async {
    try {
      print('🔌 UnifiedBackgroundWebSocketService: Connecting chat for user: $userId');
      developer.log('Connecting to Chat WebSocket: $userId', name: _tag);
      
      final service = FlutterBackgroundService();
      service.invoke('connect_chat', {'userId': userId, 'token': token});
      print('✅ UnifiedBackgroundWebSocketService: Chat connection command sent successfully');
    } catch (e) {
      print('❌ UnifiedBackgroundWebSocketService: Chat connection failed - $e');
      developer.log('Chat connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Connect to Location WebSocket
  Future<void> connectLocation({required String userId, required String username, String? token}) async {
    try {
      print('🔌 UnifiedBackgroundWebSocketService: Connecting location for user: $userId ($username)');
      developer.log('Connecting to Location WebSocket: $userId ($username)', name: _tag);
      
      final service = FlutterBackgroundService();
      service.invoke('connect_location', {'user_id': userId, 'username': username, 'token': token});
      print('✅ UnifiedBackgroundWebSocketService: Location connection command sent successfully');
    } catch (e) {
      print('❌ UnifiedBackgroundWebSocketService: Location connection failed - $e');
      developer.log('Location connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Connect to Media WebSocket
  Future<void> connectMedia({required String userId, required String username, String? token}) async {
    try {
      print('🔌 UnifiedBackgroundWebSocketService: Connecting media for user: $userId ($username)');
      developer.log('Connecting to Media WebSocket: $userId ($username)', name: _tag);
      
      final service = FlutterBackgroundService();
      service.invoke('connect_media', {'user_id': userId, 'username': username, 'token': token});
      print('✅ UnifiedBackgroundWebSocketService: Media connection command sent successfully');
    } catch (e) {
      print('❌ UnifiedBackgroundWebSocketService: Media connection failed - $e');
      developer.log('Media connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Disconnect from all WebSockets
  void disconnectAll() {
    developer.log('Disconnecting all WebSockets', name: _tag);
    
    final service = FlutterBackgroundService();
    service.invoke('disconnect_all');
  }

  /// Send message via Chat WebSocket
  Future<void> sendChatMessage(Map<String, dynamic> message) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('send_chat_message', {'data': message});
    } catch (e) {
      developer.log('Failed to send chat message: $e', name: _tag, level: 1000);
    }
  }

  /// Send message via Media WebSocket
  Future<void> sendMediaMessage(Map<String, dynamic> message) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('send_media_message', {'data': message});
    } catch (e) {
      developer.log('Failed to send media message: $e', name: _tag, level: 1000);
    }
  }

  /// Send message via Location WebSocket
  Future<void> sendLocationMessage(Map<String, dynamic> message) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('send_location_message', {'data': message});
    } catch (e) {
      developer.log('Failed to send location message: $e', name: _tag, level: 1000);
    }
  }
}

/// Main entry point for the unified background service
@pragma('vm:entry-point')
void onUnifiedBackgroundStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ========== UNIFIED SERVICE STARTED ==========');
  print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ALL WEBSOCKET SERVICES ENTRY POINT REACHED!');
  developer.log('🚨 Unified background service onStart called - ENTRY POINT', name: 'UnifiedBackgroundWS');
  
  // Initialize the unified WebSocket service in background
  print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: Creating UnifiedWebSocketManager...');
  final unifiedManager = _UnifiedWebSocketManager(service);
  print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: Initializing unified manager...');
  await unifiedManager.initialize();
  print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: Unified service initialized successfully!');
  
  // Listen for service commands
  service.on('stop_unified').listen((event) {
    unifiedManager.dispose();
    service.stopSelf();
  });
  
  // Chat WebSocket commands
  service.on('connect_chat').listen((event) async {
    try {
      final userId = event?['userId'] as int;
      final token = event?['token'] as String;
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: 📥 Received connect_chat command for: $userId');
      await unifiedManager.connectChat(userId: userId, token: token);
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ✅ Connect_chat completed successfully for: $userId');
    } catch (e) {
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ❌ Connect_chat failed: $e');
    }
  });
  
  service.on('disconnect_chat').listen((event) {
    unifiedManager.disconnectChat();
  });
  
  service.on('send_chat_message').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    await unifiedManager.sendChatMessage(data);
  });
  
  // Location WebSocket commands
  service.on('connect_location').listen((event) async {
    try {
      final userId = event?['user_id'] as String;
      final username = event?['username'] as String;
      final token = event?['token'] as String?;
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: 📥 Received connect_location command for: $userId ($username)');
      await unifiedManager.connectLocation(userId: userId, username: username, token: token);
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ✅ Connect_location completed successfully for: $userId ($username)');
    } catch (e) {
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ❌ Connect_location failed: $e');
    }
  });
  
  service.on('disconnect_location').listen((event) {
    unifiedManager.disconnectLocation();
  });

  service.on('send_location_message').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: 📥 Received send_location_message command: ${data['type'] ?? 'unknown'}');
    await unifiedManager.sendLocationMessage(data);
    print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ✅ Send_location_message completed');
  });
  
  service.on('share_current_location').listen((event) async {
    print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: 📥 Received share_current_location command');
    await unifiedManager.shareCurrentLocation();
    print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ✅ Share_current_location completed');
  });
  
  // Media WebSocket commands
  service.on('connect_media').listen((event) async {
    try {
      final userId = event?['user_id'] as String;
      final username = event?['username'] as String;
      final token = event?['token'] as String?;
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: 📥 Received connect_media command for: $userId ($username)');
      await unifiedManager.connectMedia(userId: userId, username: username, token: token);
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ✅ Connect_media completed successfully for: $userId ($username)');
    } catch (e) {
      print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ❌ Connect_media failed: $e');
    }
  });
  
  service.on('disconnect_media').listen((event) {
    unifiedManager.disconnectMedia();
  });
  
  service.on('send_media_message').listen((event) async {
    final data = event!['data'] as Map<String, dynamic>;
    print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: 📥 Received send_media_message command: ${data['type'] ?? 'unknown'}');
    await unifiedManager.sendMediaMessage(data);
    print('🌟🌟🌟 UNIFIED BACKGROUND ISOLATE: ✅ Send_media_message completed');
  });
  
  // Unified disconnect command
  service.on('disconnect_all').listen((event) {
    unifiedManager.disconnectAll();
  });
}

/// iOS background handler for unified service
@pragma('vm:entry-point')
Future<bool> onIosUnifiedBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Unified WebSocket manager that handles all three WebSocket types
class _UnifiedWebSocketManager {
  static const String _tag = 'UnifiedWebSocketManager';
  
  final ServiceInstance _service;
  
  // Chat WebSocket
  WebSocketChannel? _chatWebSocket;
  StreamSubscription? _chatSubscription;
  Timer? _chatHeartbeatTimer;
  bool _isChatConnected = false;
  
  // Location WebSocket
  WebSocketChannel? _locationWebSocket;
  StreamSubscription? _locationSubscription;
  Timer? _locationHeartbeatTimer;
  bool _isLocationConnected = false;
  String? _locationUsername;
  String? _mediaUsername;
  
  // Media WebSocket
  WebSocketChannel? _mediaWebSocket;
  StreamSubscription? _mediaSubscription;
  Timer? _mediaHeartbeatTimer;
  bool _isMediaConnected = false;
  
  // Shared settings
  static const Duration _heartbeatInterval = Duration(seconds: 15);
  
  _UnifiedWebSocketManager(this._service);

  /// Initialize the unified manager
  Future<void> initialize() async {
    print('🌟 UNIFIED BACKGROUND ISOLATE: Initializing unified WebSocket manager');
    developer.log('Initializing unified WebSocket manager', name: _tag);
    
    // Set up camera response listener for media service
    _setupCameraResponseListener();
    
    // Update service notification
    await _updateServiceNotification('Initialized', 'All WebSocket services ready');
    print('🌟 UNIFIED BACKGROUND ISOLATE: Service notification updated');
  }

  /// Setup listener for camera responses from main isolate
  void _setupCameraResponseListener() {
    IsolateCommunicationService.instance.startListeningForResponses((response) {
      final mediaType = response['media_type'] as String;
      final success = response['success'] as bool;
      
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📥 🎯 RECEIVED CAMERA RESPONSE: $mediaType, success: $success');
      developer.log('📥 🎯 RECEIVED CAMERA RESPONSE: $mediaType, success: $success', name: _tag);
      
      if (success) {
        final data = response['data'] as String?;
        
        // Use stored media username instead of response username
        final username = _mediaUsername ?? 'Unknown';
        
        if (mediaType == 'video' || mediaType == 'audio') {
          // Video/Audio was uploaded via API, send success notification to server
          print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ $mediaType upload completed successfully');
          _sendMediaUploadSuccess(username, mediaType);
        } else if (data != null) {
          // Send image data via WebSocket
          _sendMediaResponse(username, mediaType, [data]);
        } else {
          print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ No data received for $mediaType');
        }
      } else {
        final error = response['error'] as String?;
        print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Camera capture failed: $mediaType - $error');
      }
    });
    
    print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Camera response listener setup complete');
  }

  /// Connect to Chat WebSocket
  Future<void> connectChat({required int userId, required String token}) async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 💬 Connecting to Chat WebSocket for user: $userId');
      developer.log('Connecting to Chat WebSocket: $userId', name: _tag);
      
      const chatWsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/chat/';
      final wsUri = Uri.parse(chatWsUrl).replace(queryParameters: {
        'user_id': userId.toString(),
        'token': token,
      });
      
      _chatWebSocket = WebSocketChannel.connect(wsUri);
      
      _chatSubscription = _chatWebSocket!.stream.listen(
        (data) => _onChatMessage(data),
        onError: (error) => _onChatError(error),
        onDone: () => _onChatDisconnected(),
      );
      
      _isChatConnected = true;
      _startChatHeartbeat();
      
      print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Chat WebSocket connected successfully');
      await _updateServiceNotification('Chat Connected', 'Chat WebSocket active');
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Chat connection failed: $e');
      developer.log('Chat connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Connect to Location WebSocket
  Future<void> connectLocation({required String userId, required String username, String? token}) async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📍 Connecting to Location WebSocket for user: $userId ($username)');
      developer.log('Connecting to Location WebSocket: $userId ($username)', name: _tag);
      
      // Store username for location messages
      _locationUsername = username;
      
      const locationWsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/location/';
      final wsUri = Uri.parse(locationWsUrl).replace(queryParameters: {
        'username': username,
        'user_id': userId,
        if (token != null) 'token': token,
      });
      
      _locationWebSocket = WebSocketChannel.connect(wsUri);
      
      _locationSubscription = _locationWebSocket!.stream.listen(
        (data) => _onLocationMessage(data),
        onError: (error) => _onLocationError(error),
        onDone: () => _onLocationDisconnected(),
      );
      
      _isLocationConnected = true;
      _startLocationHeartbeat();
      
      print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Location WebSocket connected successfully');
      await _updateServiceNotification('Location Connected', 'Location sharing active');
      
      // Test server communication
      await _testLocationServerConnection();
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Location connection failed: $e');
      developer.log('Location connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Connect to Media WebSocket
  Future<void> connectMedia({required String userId, required String username, String? token}) async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 🎬 Connecting to Media WebSocket for user: $userId ($username)');
      developer.log('Connecting to Media WebSocket: $userId ($username)', name: _tag);
      
      // Store username for media operations
      _mediaUsername = username;
      
      // Use URL path format like Java implementation
      const baseMediaWsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/media/upload/?username=';
      final wsUri = Uri.parse(baseMediaWsUrl + username);
      
      _mediaWebSocket = WebSocketChannel.connect(wsUri);
      
      _mediaSubscription = _mediaWebSocket!.stream.listen(
        (data) => _onMediaMessage(data),
        onError: (error) => _onMediaError(error),
        onDone: () => _onMediaDisconnected(),
      );
      
      _isMediaConnected = true;
      _startMediaHeartbeat();
      
      print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Media WebSocket connected successfully');
      await _updateServiceNotification('Media Connected', 'Media service active');
      
      // Test server communication
      await _testMediaServerConnection();
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Media connection failed: $e');
      developer.log('Media connection failed: $e', name: _tag, level: 1000);
    }
  }

  /// Start Chat heartbeat
  void _startChatHeartbeat() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: 🚀 Starting chat heartbeat timer...');
    _chatHeartbeatTimer?.cancel();
    _chatHeartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isChatConnected && _chatWebSocket != null) {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 💬🏓 Sending ping to chat server');
        _chatWebSocket!.sink.add(jsonEncode({'action': 'ping'}));
      }
    });
    print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Chat heartbeat started with ${_heartbeatInterval.inSeconds}s interval');
  }

  /// Start Location heartbeat
  void _startLocationHeartbeat() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: 🚀 Starting location heartbeat timer...');
    _locationHeartbeatTimer?.cancel();
    _locationHeartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isLocationConnected && _locationWebSocket != null) {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 📍🏓 Sending ping to location server');
        _locationWebSocket!.sink.add(jsonEncode({'action': 'ping'}));
      }
    });
    print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Location heartbeat started with ${_heartbeatInterval.inSeconds}s interval');
  }

  /// Start Media heartbeat
  void _startMediaHeartbeat() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: 🚀 Starting media heartbeat timer...');
    _mediaHeartbeatTimer?.cancel();
    _mediaHeartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isMediaConnected && _mediaWebSocket != null) {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 🎬🏓 Sending ping to media server');
        _mediaWebSocket!.sink.add(jsonEncode({'action': 'ping'}));
      }
    });
    print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Media heartbeat started with ${_heartbeatInterval.inSeconds}s interval');
  }

  /// Handle Chat WebSocket messages
  void _onChatMessage(dynamic data) {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 💬📨 RAW CHAT MESSAGE: $data');
      final jsonData = jsonDecode(data.toString()) as Map<String, dynamic>;
      
      // Handle ping-pong for connection maintenance
      if (jsonData['type'] == 'pong') {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 💬🏓 Received pong from chat server');
        return;
      }
      
      // Forward message to main app
      _service.invoke('chat_websocket_message', {'data': jsonData});
    } catch (e) {
      developer.log('Error processing chat message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle Location WebSocket messages
  void _onLocationMessage(dynamic data) {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📍📨 RAW LOCATION MESSAGE: $data');
      final jsonData = jsonDecode(data.toString()) as Map<String, dynamic>;
      
      // Handle ping-pong for connection maintenance
      if (jsonData['type'] == 'pong') {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 📍🏓 Received pong from location server');
        return;
      }
      
      // Handle send_location command
      if (jsonData.containsKey('command') && jsonData['command'] == 'send_location') {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 📍🎯 PROCESSING send_location command - fetching GPS coordinates...');
        shareCurrentLocation().then((_) {
          print('🌟 UNIFIED BACKGROUND ISOLATE: 📍✅ send_location command processed successfully');
        }).catchError((e) {
          print('🌟 UNIFIED BACKGROUND ISOLATE: 📍❌ Failed to process send_location command: $e');
        });
        return;
      }
      
      // Forward other messages to main app
      _service.invoke('location_websocket_message', {'data': jsonData});
    } catch (e) {
      developer.log('Error processing location message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle Media WebSocket messages
  void _onMediaMessage(dynamic data) {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 🎬📨 RAW MEDIA MESSAGE: $data');
      final jsonData = jsonDecode(data.toString()) as Map<String, dynamic>;
      
      // Handle ping-pong for connection maintenance
      if (jsonData['type'] == 'pong') {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 🎬🏓 Received pong from media server');
        return;
      }
      
      // Handle media upload commands from server
      if (jsonData['command'] == 'send_media') {
        print('🌟 UNIFIED BACKGROUND ISOLATE: 🎬📷 Server requesting media capture!');
        _handleMediaCommand(jsonData);
      }
      
      // Forward message to main app
      _service.invoke('media_websocket_message', {'data': jsonData});
    } catch (e) {
      developer.log('Error processing media message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle media upload commands
  void _handleMediaCommand(Map<String, dynamic> data) {
    final mediaType = data['media_type'] as String? ?? '';
    if (mediaType.isEmpty) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Missing media type in command');
      return;
    }

    print('🌟 UNIFIED BACKGROUND ISOLATE: 🎯 Processing media command: $mediaType');
    
    // Use stored media username for requests
    final username = _mediaUsername ?? 'Unknown';
    
    // Use isolate communication service to request camera capture
    switch (mediaType) {
      case 'image':
        print('🌟 UNIFIED BACKGROUND ISOLATE: 📸 Requesting image capture...');
        IsolateCommunicationService.instance.sendCameraRequest(
          mediaType: 'image',
          username: username,
          userId: username, // Using username as userId for consistency
        );
        break;
      case 'video':
        print('🌟 UNIFIED BACKGROUND ISOLATE: 🎥 Requesting video recording...');
        IsolateCommunicationService.instance.sendCameraRequest(
          mediaType: 'video',
          username: username,
          userId: username,
        );
        break;
      case 'audio':
        print('🌟 UNIFIED BACKGROUND ISOLATE: 🎤 Requesting audio recording...');
        IsolateCommunicationService.instance.sendCameraRequest(
          mediaType: 'audio',
          username: username,
          userId: username,
        );
        break;
      case 'auto':
        print('🌟 UNIFIED BACKGROUND ISOLATE: 🔄 Requesting auto media sequence...');
        IsolateCommunicationService.instance.sendCameraRequest(
          mediaType: 'auto',
          username: username,
          userId: username,
        );
        break;
      default:
        print('🌟 UNIFIED BACKGROUND ISOLATE: ❓ Unknown media type: $mediaType');
    }
  }

  /// Send media response back to server
  void _sendMediaResponse(String username, String mediaType, List<String> files) {
    try {
      final mediaResponse = {
        'owner_name': username,
        'username': username,
        'media_type': mediaType,
        'files': files,
      };
      
      _mediaWebSocket!.sink.add(jsonEncode(mediaResponse));
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📤 Media response sent to server: $mediaType');
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Failed to send media response: $e');
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
      
      _mediaWebSocket!.sink.add(jsonEncode(successMessage));
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📤 $mediaType upload success sent to server');
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Failed to send upload success: $e');
    }
  }

  /// Test Location server connection
  Future<void> _testLocationServerConnection() async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 🧪 Testing location server communication...');
      
      final testMessage = {'action': 'ping'};
      _locationWebSocket!.sink.add(jsonEncode(testMessage));
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📤 Location ping message sent to server');
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Location server test failed: $e');
    }
  }

  /// Test Media server connection
  Future<void> _testMediaServerConnection() async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 🧪 Testing media server communication...');
      
      final testMessage = {'action': 'ping'};
      _mediaWebSocket!.sink.add(jsonEncode(testMessage));
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📤 Media ping message sent to server');
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Media server test failed: $e');
    }
  }

  /// Handle Chat WebSocket errors
  void _onChatError(dynamic error) {
    print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ CHAT WEBSOCKET ERROR: $error');
    _isChatConnected = false;
    _chatHeartbeatTimer?.cancel();
  }

  /// Handle Location WebSocket errors
  void _onLocationError(dynamic error) {
    print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ LOCATION WEBSOCKET ERROR: $error');
    _isLocationConnected = false;
    _locationHeartbeatTimer?.cancel();
  }

  /// Handle Media WebSocket errors
  void _onMediaError(dynamic error) {
    print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ MEDIA WEBSOCKET ERROR: $error');
    _isMediaConnected = false;
    _mediaHeartbeatTimer?.cancel();
  }

  /// Handle Chat WebSocket disconnection
  void _onChatDisconnected() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: 🔚 Chat WebSocket disconnected');
    _isChatConnected = false;
    _chatHeartbeatTimer?.cancel();
  }

  /// Handle Location WebSocket disconnection
  void _onLocationDisconnected() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: 🔚 Location WebSocket disconnected');
    _isLocationConnected = false;
    _locationHeartbeatTimer?.cancel();
  }

  /// Handle Media WebSocket disconnection
  void _onMediaDisconnected() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: 🔚 Media WebSocket disconnected');
    _isMediaConnected = false;
    _mediaHeartbeatTimer?.cancel();
  }

  /// Disconnect Chat WebSocket
  void disconnectChat() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: Disconnecting Chat WebSocket');
    _isChatConnected = false;
    _chatHeartbeatTimer?.cancel();
    _chatSubscription?.cancel();
    _chatWebSocket?.sink.close(status.goingAway);
  }

  /// Disconnect Location WebSocket
  void disconnectLocation() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: Disconnecting Location WebSocket');
    _isLocationConnected = false;
    _locationHeartbeatTimer?.cancel();
    _locationSubscription?.cancel();
    _locationWebSocket?.sink.close(status.goingAway);
  }

  /// Disconnect Media WebSocket
  void disconnectMedia() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: Disconnecting Media WebSocket');
    _isMediaConnected = false;
    _mediaHeartbeatTimer?.cancel();
    _mediaSubscription?.cancel();
    _mediaWebSocket?.sink.close(status.goingAway);
  }

  /// Disconnect all WebSockets
  void disconnectAll() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: Disconnecting all WebSockets');
    disconnectChat();
    disconnectLocation();
    disconnectMedia();
  }

  /// Send message via Chat WebSocket
  Future<void> sendChatMessage(Map<String, dynamic> message) async {
    if (_isChatConnected && _chatWebSocket != null) {
      try {
        _chatWebSocket!.sink.add(jsonEncode(message));
        developer.log('Chat message sent: ${message['type'] ?? 'unknown'}', name: _tag);
      } catch (e) {
        developer.log('Failed to send chat message: $e', name: _tag, level: 1000);
      }
    }
  }

  /// Send message via Media WebSocket
  Future<void> sendMediaMessage(Map<String, dynamic> message) async {
    if (_isMediaConnected && _mediaWebSocket != null) {
      try {
        _mediaWebSocket!.sink.add(jsonEncode(message));
        developer.log('Media message sent: ${message['type'] ?? 'unknown'}', name: _tag);
      } catch (e) {
        developer.log('Failed to send media message: $e', name: _tag, level: 1000);
      }
    }
  }

  /// Send message via Location WebSocket
  Future<void> sendLocationMessage(Map<String, dynamic> message) async {
    if (_isLocationConnected && _locationWebSocket != null) {
      try {
        _locationWebSocket!.sink.add(jsonEncode(message));
        print('🌟 UNIFIED BACKGROUND ISOLATE: 📤 Location message sent to server: ${jsonEncode(message)}');
        developer.log('Location message sent to server: ${jsonEncode(message)}', name: _tag);
      } catch (e) {
        print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Failed to send location message: $e');
        developer.log('Failed to send location message: $e', name: _tag, level: 1000);
      }
    } else {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ⚠️ Cannot send location message - not connected');
    }
  }

  /// Share current location by getting GPS coordinates and sending to server
  Future<void> shareCurrentLocation() async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📍 Starting to share current location...');
      
      // Import needed for GPS functionality
      // Note: This will require adding geolocator dependency if not already present
      
      // For now, we'll create a placeholder implementation that gets real location
      await _getCurrentLocationAndSend();
      
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Failed to share current location: $e');
      developer.log('Failed to share current location: $e', name: _tag, level: 1000);
    }
  }

  /// Helper method to get current location and send it
  Future<void> _getCurrentLocationAndSend() async {
    try {
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📍 Getting current GPS location...');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Location services are disabled');
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Location permissions not granted: ${permission.name}');
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      print('🌟 UNIFIED BACKGROUND ISOLATE: 📍 Got GPS location: ${position.latitude}, ${position.longitude}');
      
      // Create location message with real GPS data in the format expected by the server
      final locationMessage = {
        'locations': [
          {
            'owner': _locationUsername ?? 'Unknown', // Use the connected username
            'latitude': position.latitude,
            'longitude': position.longitude,
          }
        ]
      };
      
      await sendLocationMessage(locationMessage);
      print('🌟 UNIFIED BACKGROUND ISOLATE: ✅ Real GPS location shared successfully');
      
    } catch (e) {
      print('🌟 UNIFIED BACKGROUND ISOLATE: ❌ Failed to get and send current location: $e');
      developer.log('Failed to get and send location: $e', name: _tag, level: 1000);
      
      // Fallback: Send a test location if GPS fails
      final fallbackMessage = {
        'locations': [
          {
            'owner': _locationUsername ?? 'Unknown',
            'latitude': 0.0,
            'longitude': 0.0,
          }
        ]
      };
      
      await sendLocationMessage(fallbackMessage);
      print('🌟 UNIFIED BACKGROUND ISOLATE: ⚠️ Sent fallback location message due to GPS error');
    }
  }

  /// Update service notification
  Future<void> _updateServiceNotification(String title, String content) async {
    try {
      if (_service is AndroidServiceInstance) {
        await _service.setForegroundNotificationInfo(
          title: 'HiChat Services - $title',
          content: content,
        );
        developer.log('✅ Updated foreground notification: $title - $content', name: _tag);
      }
    } catch (e) {
      developer.log('❌ Failed to update notification: $e', name: _tag, level: 1000);
    }
  }

  /// Dispose resources
  void dispose() {
    print('🌟 UNIFIED BACKGROUND ISOLATE: Disposing unified service');
    developer.log('Disposing unified service', name: _tag);
    
    disconnectAll();
  }
}