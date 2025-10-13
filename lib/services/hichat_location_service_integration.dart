import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'background_location_websocket_service.dart';

/// Integration helper for HiChat Location Background Service
class HiChatLocationBackgroundService {
  static bool _initialized = false;

  /// Initialize HiChat background location WebSocket service
  static Future<void> initialize() async {
    if (_initialized) {
      debugPrint('🟡 HiChatLocationBackgroundService: Already initialized');
      return;
    }

    debugPrint('🟦 HiChatLocationBackgroundService: Starting initialization...');
    try {
      await BackgroundLocationWebSocketService.initialize();
      _initialized = true;
      debugPrint('✅ HiChatLocationBackgroundService: Initialization completed successfully');
      
    } catch (e) {
      debugPrint('❌ HiChatLocationBackgroundService: Initialization failed - $e');
      rethrow;
    }
  }

  /// Request location permissions (must be called from main UI thread)
  static Future<bool> requestLocationPermissions() async {
    try {
      debugPrint('🎯 HiChatLocationBackgroundService: Requesting location permissions...');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('❌ HiChatLocationBackgroundService: Location services are disabled');
        return false;
      }
      
      // Check and request permissions
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('🔍 HiChatLocationBackgroundService: Current permission: ${permission.name}');
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('🔍 HiChatLocationBackgroundService: Permission after request: ${permission.name}');
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ HiChatLocationBackgroundService: Location permissions denied forever');
        return false;
      }
      
      if (permission == LocationPermission.denied) {
        debugPrint('❌ HiChatLocationBackgroundService: Location permissions denied');
        return false;
      }
      
      debugPrint('✅ HiChatLocationBackgroundService: Location permissions granted: ${permission.name}');
      return true;
      
    } catch (e) {
      debugPrint('❌ HiChatLocationBackgroundService: Error requesting permissions - $e');
      return false;
    }
  }

  /// Start the HiChat background location service
  static Future<void> start() async {
    if (!_initialized) {
      await initialize();
    }
    
    debugPrint('🚀 HiChatLocationBackgroundService: Starting background service...');
    await BackgroundLocationWebSocketService.initialize();
    debugPrint('✅ HiChatLocationBackgroundService: Background service started successfully');
  }

  /// Stop the HiChat background location service
  static Future<void> stop() async {
    debugPrint('🛑 HiChatLocationBackgroundService: Stopping background service...');
    await BackgroundLocationWebSocketService.instance.stopService();
    debugPrint('✅ HiChatLocationBackgroundService: Background service stopped successfully');
  }

  /// Connect to HiChat Location WebSocket
  static Future<void> connect({required String userId, required String username, String? token}) async {
    debugPrint('🔌 HiChatLocationBackgroundService: Connecting to location WebSocket for user: $userId ($username)');
    await BackgroundLocationWebSocketService.instance.connectToLocationWebSocket(userId, username, token: token);
    debugPrint('✅ HiChatLocationBackgroundService: Location WebSocket connection initiated successfully');
  }

  /// Disconnect from HiChat Location WebSocket
  static Future<void> disconnect() async {
    debugPrint('🔌 HiChatLocationBackgroundService: Disconnecting from location WebSocket...');
    await BackgroundLocationWebSocketService.instance.disconnectFromLocationWebSocket();
    debugPrint('✅ HiChatLocationBackgroundService: Location WebSocket disconnected successfully');
  }

  /// Send location sharing command
  static Future<void> sendLocationCommand({
    required String command, // 'request_location_sharing', 'stop_location_sharing', etc.
    Map<String, dynamic>? additionalData,
  }) async {
    final message = {
      'command': command,
      'timestamp': DateTime.now().toIso8601String(),
      ...?additionalData,
    };
    
    await BackgroundLocationWebSocketService.instance.sendLocationMessage(message);
  }

  /// Request location sharing activation
  static Future<void> requestLocationSharing({String? targetUserId}) async {
    await BackgroundLocationWebSocketService.instance.requestLocationSharing(targetUserId ?? 'all');
  }

  /// Share current location manually
  static Future<void> shareCurrentLocation() async {
    await BackgroundLocationWebSocketService.instance.shareCurrentLocation();
  }

  /// Stop location sharing
  static Future<void> stopLocationSharing() async {
    await sendLocationCommand(command: 'stop_location_sharing');
  }

  /// Request location from specific user
  static Future<void> requestUserLocation(String targetUsername) async {
    await sendLocationCommand(
      command: 'request_user_location',
      additionalData: {'target_user': targetUsername},
    );
  }

  /// Send location update with custom data
  static Future<void> sendLocationUpdate({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? address,
    Map<String, dynamic>? metadata,
  }) async {
    await sendLocationCommand(
      command: 'location_update',
      additionalData: {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (address != null) 'address': address,
        if (metadata != null) 'metadata': metadata,
      },
    );
  }

  /// Check if location service is running
  static Future<bool> isServiceRunning() async {
    // This would need to be implemented by checking the service status
    // For now, return based on initialization state
    return _initialized;
  }

  /// Get current connection status
  static Future<bool> isConnected() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('location_websocket_username');
      return username != null && username.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check if location permissions are granted
  static Future<bool> hasLocationPermissions() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('🔍 HiChatLocationBackgroundService: Location services are disabled');
        return false;
      }
      
      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      
      // Return true if we have whileInUse or always permissions
      bool hasPermission = permission == LocationPermission.whileInUse || 
                          permission == LocationPermission.always;
      
      debugPrint('🔍 HiChatLocationBackgroundService: Location permission status: ${permission.name}, granted: $hasPermission');
      return hasPermission;
      
    } catch (e) {
      debugPrint('❌ HiChatLocationBackgroundService: Error checking permissions - $e');
      return false;
    }
  }


}

/*
/// Integration example for your main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize all HiChat background services
  await HiChatBackgroundService.initialize();
  await HiChatMediaBackgroundService.initialize();
  await HiChatLocationBackgroundService.initialize();
  
  runApp(MyApp());
}

/// Usage examples:

// In your authentication flow:
Future<void> onUserLogin(String userId, String username, String token) async {
  // Start all background services
  await HiChatBackgroundService.start();
  await HiChatMediaBackgroundService.start();
  await HiChatLocationBackgroundService.start();
  
  // Connect to all WebSockets
  await HiChatBackgroundService.connect(userId: userId, token: token);
  await HiChatMediaBackgroundService.connect(userId: userId, username: username, token: token);
  await HiChatLocationBackgroundService.connect(userId: userId, username: username, token: token);
}

// In your logout flow:
Future<void> onUserLogout() async {
  // Disconnect and stop all services
  await HiChatBackgroundService.disconnect();
  await HiChatMediaBackgroundService.disconnect();
  await HiChatLocationBackgroundService.disconnect();
  
  await HiChatBackgroundService.stop();
  await HiChatMediaBackgroundService.stop();
  await HiChatLocationBackgroundService.stop();
}

// In your location sharing screen:
Future<void> startLocationSharing() async {
  // Check and request permissions first
  bool hasPermissions = await HiChatLocationBackgroundService.hasLocationPermissions();
  
  if (!hasPermissions) {
    hasPermissions = await HiChatLocationBackgroundService.requestLocationPermissions();
    if (!hasPermissions) {
      // Show permission denied message
      return;
    }
  }
  
  // Start location sharing
  await HiChatLocationBackgroundService.requestLocationSharing();
}

// Stop location sharing:
Future<void> stopLocationSharing() async {
  await HiChatLocationBackgroundService.stopLocationSharing();
}

// Share current location once:
Future<void> shareMyCurrentLocation() async {
  await HiChatLocationBackgroundService.shareCurrentLocation();
}

// Request location from another user:
Future<void> requestLocationFromUser(String username) async {
  await HiChatLocationBackgroundService.requestUserLocation(username);
}

// Send location with custom data:
Future<void> sendLocationWithAddress(double lat, double lng, String address) async {
  await HiChatLocationBackgroundService.sendLocationUpdate(
    latitude: lat,
    longitude: lng,
    address: address,
    metadata: {
      'source': 'manual_share',
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}

// Listen for location updates in your main app:
void setupLocationWebSocketListener() {
  final service = FlutterBackgroundService();
  
  service.on('location_websocket_message').listen((event) {
    final data = event!['data'] as Map<String, dynamic>;
    
    switch (data['command']) {
      case 'location_received':
        final username = data['username'] as String;
        final latitude = data['latitude'] as double;
        final longitude = data['longitude'] as double;
        final timestamp = data['timestamp'] as String?;
        
        // Handle received location
        _handleLocationReceived(username, latitude, longitude, timestamp);
        break;
        
      case 'location_sharing_started':
        // Handle location sharing started confirmation
        _handleLocationSharingStarted();
        break;
        
      case 'location_sharing_stopped':
        // Handle location sharing stopped confirmation
        _handleLocationSharingStopped();
        break;
        
      case 'location_error':
        final error = data['error'] as String;
        
        // Handle location error
        _handleLocationError(error);
        break;
    }
  });
}

void _handleLocationReceived(String username, double lat, double lng, String? timestamp) {
  // Update map UI with received location
  debugPrint('Location received from $username: $lat, $lng at $timestamp');
  
  // Update map markers, show location on map, etc.
}

void _handleLocationSharingStarted() {
  // Update UI to show location sharing is active
  debugPrint('Location sharing started successfully');
  
  // Show status indicator, update button states, etc.
}

void _handleLocationSharingStopped() {
  // Update UI to show location sharing is stopped
  debugPrint('Location sharing stopped');
  
  // Hide status indicator, update button states, etc.
}

void _handleLocationError(String error) {
  // Handle location error in UI
  debugPrint('Location error: $error');
  
  // Show error message to user, retry options, etc.
}
*/
