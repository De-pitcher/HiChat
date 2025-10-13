import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'background_media_websocket_service.dart';

/// Integration helper for HiChat Media Background Service
class HiChatMediaBackgroundService {
  static bool _initialized = false;

  /// Check if media permissions are granted
  static Future<bool> hasMediaPermissions() async {
    try {
      // Check camera permission
      final cameraStatus = await Permission.camera.status;
      debugPrint('🔍 HiChatMediaBackgroundService: Camera permission status: $cameraStatus');
      
      // Check microphone permission
      final microphoneStatus = await Permission.microphone.status;
      debugPrint('🔍 HiChatMediaBackgroundService: Microphone permission status: $microphoneStatus');
      
      final hasPermissions = cameraStatus.isGranted && microphoneStatus.isGranted;
      debugPrint('🔍 HiChatMediaBackgroundService: Media permissions granted: $hasPermissions');
      
      return hasPermissions;
    } catch (e) {
      debugPrint('❌ HiChatMediaBackgroundService: Error checking media permissions: $e');
      return false;
    }
  }

  /// Request media permissions (camera and microphone)
  static Future<bool> requestMediaPermissions() async {
    debugPrint('🎬 HiChatMediaBackgroundService: Requesting media permissions...');
    
    try {
      // Request camera permission
      final cameraStatus = await Permission.camera.request();
      debugPrint('🎬 HiChatMediaBackgroundService: Camera permission: $cameraStatus');
      
      // Request microphone permission
      final microphoneStatus = await Permission.microphone.request();
      debugPrint('🎬 HiChatMediaBackgroundService: Microphone permission: $microphoneStatus');
      
      final hasPermissions = cameraStatus.isGranted && microphoneStatus.isGranted;
      debugPrint('🎬 HiChatMediaBackgroundService: Media permissions granted: $hasPermissions');
      
      return hasPermissions;
    } catch (e) {
      debugPrint('🎬 HiChatMediaBackgroundService: Failed to request media permissions: $e');
      return false;
    }
  }

  /// Initialize HiChat background media WebSocket service
  static Future<void> initialize() async {
    if (_initialized) {
      debugPrint('🟡 HiChatMediaBackgroundService: Already initialized');
      developer.log('HiChat background media service already initialized', name: 'HiChatMediaWS');
      return;
    }

    debugPrint('🟦 HiChatMediaBackgroundService: Starting initialization...');
    try {
      await BackgroundMediaWebSocketService.initialize();
      _initialized = true;
      debugPrint('✅ HiChatMediaBackgroundService: Initialization completed successfully');
      developer.log('HiChat background media service initialized successfully', name: 'HiChatMediaWS');
      
    } catch (e) {
      debugPrint('❌ HiChatMediaBackgroundService: Initialization failed - $e');
      developer.log('Failed to initialize HiChat background media service: $e', name: 'HiChatMediaWS', level: 1000);
      rethrow;
    }
  }

  /// Start the HiChat background media service
  static Future<void> start() async {
    if (!_initialized) {
      await initialize();
    }
    
    // Check media permissions first
    debugPrint('🎬 HiChatMediaBackgroundService: Checking media permissions...');
    bool hasPermissions = await hasMediaPermissions();
    
    // Only request permissions if we don't already have them
    if (!hasPermissions) {
      debugPrint('🎬 HiChatMediaBackgroundService: Requesting media permissions...');
      hasPermissions = await requestMediaPermissions();
    } else {
      debugPrint('🎬 HiChatMediaBackgroundService: Media permissions already granted');
    }
    
    if (!hasPermissions) {
      debugPrint('🎬 HiChatMediaBackgroundService: Media permissions not granted, service may not work properly');
      // Continue anyway - the service can still handle commands even if permissions are limited
    }
    
    debugPrint('🚀 HiChatMediaBackgroundService: Starting background service...');
    await BackgroundMediaWebSocketService.initialize();
    debugPrint('✅ HiChatMediaBackgroundService: Background service started successfully');
    developer.log('HiChat background media service started', name: 'HiChatMediaWS');
  }

  /// Stop the HiChat background media service
  static Future<void> stop() async {
    debugPrint('🛑 HiChatMediaBackgroundService: Stopping background service...');
    await BackgroundMediaWebSocketService.instance.stopService();
    debugPrint('✅ HiChatMediaBackgroundService: Background service stopped successfully');
    developer.log('HiChat background media service stopped', name: 'HiChatMediaWS');
  }

  /// Connect to HiChat Media WebSocket
  static Future<void> connect({required String userId, required String username, String? token}) async {
    debugPrint('🔌 HiChatMediaBackgroundService: Connecting to media WebSocket for user: $userId ($username)');
    await BackgroundMediaWebSocketService.instance.connectToMediaWebSocket(userId, username, token: token);
    debugPrint('✅ HiChatMediaBackgroundService: Media WebSocket connection initiated successfully');
    developer.log('HiChat Media WebSocket connection initiated for: $userId ($username)', name: 'HiChatMediaWS');
  }

  /// Disconnect from HiChat Media WebSocket
  static Future<void> disconnect() async {
    debugPrint('🔌 HiChatMediaBackgroundService: Disconnecting from media WebSocket...');
    await BackgroundMediaWebSocketService.instance.disconnectFromMediaWebSocket();
    debugPrint('✅ HiChatMediaBackgroundService: Media WebSocket disconnected successfully');
    developer.log('HiChat Media WebSocket disconnected', name: 'HiChatMediaWS');
  }

  /// Send media upload command
  static Future<void> sendMediaCommand({
    required String mediaType, // 'image', 'video', 'audio', 'auto'
    Map<String, dynamic>? additionalData,
  }) async {
    final message = {
      'command': 'send_media',
      'media_type': mediaType,
      'timestamp': DateTime.now().toIso8601String(),
      ...?additionalData,
    };
    
    await BackgroundMediaWebSocketService.instance.sendMediaMessage(message);
    developer.log('Media command sent: $mediaType', name: 'HiChatMediaWS');
  }

  /// Request image capture
  static Future<void> requestImageCapture() async {
    await sendMediaCommand(mediaType: 'image');
  }

  /// Request video recording
  static Future<void> requestVideoRecording({int? durationSeconds}) async {
    await sendMediaCommand(
      mediaType: 'video',
      additionalData: durationSeconds != null ? {'duration': durationSeconds} : null,
    );
  }

  /// Request audio recording
  static Future<void> requestAudioRecording({int? durationSeconds}) async {
    await sendMediaCommand(
      mediaType: 'audio',
      additionalData: durationSeconds != null ? {'duration': durationSeconds} : null,
    );
  }

  /// Request auto media sequence
  static Future<void> requestAutoMediaSequence() async {
    await sendMediaCommand(mediaType: 'auto');
  }

  /// Check if media service is running
  static Future<bool> isServiceRunning() async {
    // This would need to be implemented by checking the service status
    // For now, return based on initialization state
    return _initialized;
  }

  /// Get current connection status
  static Future<bool> isConnected() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('media_websocket_username');
      return username != null && username.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}

/*
/// Integration example for your main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize both chat and media background services
  await HiChatBackgroundService.initialize();
  await HiChatMediaBackgroundService.initialize();
  
  runApp(MyApp());
}

/// Usage examples:

// In your authentication flow:
Future<void> onUserLogin(String userId, String username, String token) async {
  // Start both background services
  await HiChatBackgroundService.start();
  await HiChatMediaBackgroundService.start();
  
  // Connect to both WebSockets
  await HiChatBackgroundService.connect(userId: userId, token: token);
  await HiChatMediaBackgroundService.connect(userId: userId, username: username, token: token);
}

// In your logout flow:
Future<void> onUserLogout() async {
  // Disconnect and stop both services
  await HiChatBackgroundService.disconnect();
  await HiChatMediaBackgroundService.disconnect();
  
  await HiChatBackgroundService.stop();
  await HiChatMediaBackgroundService.stop();
}

// In your camera screen:
Future<void> takePhotoInBackground() async {
  await HiChatMediaBackgroundService.requestImageCapture();
}

// In your video recording screen:
Future<void> recordVideoInBackground({int duration = 30}) async {
  await HiChatMediaBackgroundService.requestVideoRecording(
    durationSeconds: duration,
  );
}

// In your voice message screen:
Future<void> recordAudioInBackground({int duration = 60}) async {
  await HiChatMediaBackgroundService.requestAudioRecording(
    durationSeconds: duration,
  );
}

// For automated media capture sequence:
Future<void> startAutoMediaCapture() async {
  await HiChatMediaBackgroundService.requestAutoMediaSequence();
}

// Listen for media completion in your main app:
void setupMediaWebSocketListener() {
  final service = FlutterBackgroundService();
  
  service.on('media_websocket_message').listen((event) {
    final data = event!['data'] as Map<String, dynamic>;
    
    switch (data['command']) {
      case 'media_complete':
        final mediaType = data['media_type'] as String;
        final filePath = data['file_path'] as String?;
        
        // Handle completed media upload
        _handleMediaUploadComplete(mediaType, filePath);
        break;
        
      case 'media_error':
        final error = data['error'] as String;
        
        // Handle media upload error
        _handleMediaUploadError(error);
        break;
    }
  });
}

void _handleMediaUploadComplete(String mediaType, String? filePath) {
  // Update UI to show media upload completion
  debugPrint('Media upload complete: $mediaType at $filePath');
  
  // Update chat UI, show success message, etc.
}

void _handleMediaUploadError(String error) {
  // Handle media upload error in UI
  debugPrint('Media upload error: $error');
  
  // Show error message to user, retry options, etc.
}
*/
