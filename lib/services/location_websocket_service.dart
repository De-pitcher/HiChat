import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Callback function type for location updates
typedef LocationCallback = void Function(Position? location);

/// WebSocket service for sharing location data
class LocationWebSocketService {
  static const String _tag = 'LocationWebSocketService';
  static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/location/?username=';
  
  // WebSocket connection
  WebSocketChannel? _webSocketChannel;
  StreamSubscription? _webSocketSubscription;
  
  // Auto reconnect configuration
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  Timer? _reconnectTimer;
  
  // Current connection state
  bool _isConnected = false;
  String? _currentUsername;
  
  /// Singleton instance
  static final LocationWebSocketService _instance = LocationWebSocketService._internal();
  factory LocationWebSocketService() => _instance;
  LocationWebSocketService._internal();
  
  /// Get singleton instance
  static LocationWebSocketService get instance => _instance;
  
  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;
  
  /// Connect to the location WebSocket
  Future<void> connectWebSocket(String username) async {
    try {
      _currentUsername = username;
      _shouldReconnect = true;
      await _initiateConnection(username);
    } catch (e) {
      developer.log('Error connecting WebSocket: $e', name: _tag);
    }
  }
  
  /// Internal method to initiate WebSocket connection
  Future<void> _initiateConnection(String username) async {
    try {
      final wsUrl = '$_wsUrl$username';
      developer.log('Connecting Location WebSocket... attempt ${_reconnectAttempts + 1}', name: _tag);
      
      // Close existing connection if any
      await _closeWebSocketInternal();
      
      // Create new WebSocket connection
      _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // Listen to WebSocket messages
      _webSocketSubscription = _webSocketChannel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onClosed,
      );
      
      // Connection successful
      _isConnected = true;
      _reconnectAttempts = 0; // Reset on success
      developer.log('Location WebSocket connected', name: _tag);
      
    } catch (e) {
      developer.log('WebSocket connection failed: $e', name: _tag);
      _isConnected = false;
      if (_shouldReconnect) {
        _scheduleReconnect(username);
      }
    }
  }
  
  /// Handle incoming WebSocket messages
  void _onMessage(dynamic message) {
    try {
      developer.log('Received: $message', name: _tag);
      
      final data = jsonDecode(message.toString());
      
      if (data is Map<String, dynamic> && 
          data.containsKey('command') && 
          data['command'] == 'send_location') {
        
        // Server requesting location
        _getLastLocation((location) {
          if (location != null) {
            _sendLocation(_currentUsername!, location);
          } else {
            developer.log('Location is null or permission not granted.', name: _tag);
          }
        });
      }
    } catch (e) {
      developer.log('Error parsing message: $e', name: _tag);
    }
  }
  
  /// Handle WebSocket errors
  void _onError(dynamic error) {
    developer.log('Location WebSocket failure: $error', name: _tag);
    _isConnected = false;
    if (_shouldReconnect && _currentUsername != null) {
      _scheduleReconnect(_currentUsername!);
    }
  }
  
  /// Handle WebSocket closure
  void _onClosed() {
    developer.log('Location WebSocket closed', name: _tag);
    _isConnected = false;
    if (_shouldReconnect && _currentUsername != null) {
      _scheduleReconnect(_currentUsername!);
    }
  }
  
  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect(String username) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      developer.log('Max reconnect attempts reached for Location WebSocket. Stopping.', name: _tag);
      return;
    }
    
    // Calculate delay with exponential backoff
    final delayMs = min(
      _initialReconnectDelay.inMilliseconds * (1 << _reconnectAttempts),
      _maxReconnectDelay.inMilliseconds,
    );
    
    final delay = Duration(milliseconds: delayMs);
    _reconnectAttempts++;
    
    developer.log('Reconnecting Location WebSocket in ${delay.inMilliseconds} ms (attempt $_reconnectAttempts)', name: _tag);
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _initiateConnection(username));
  }
  
  /// Send location data to the server
  void _sendLocation(String username, Position location) {
    try {
      final locationData = {
        'owner': username,
        'latitude': location.latitude,
        'longitude': location.longitude,
      };
      
      final message = {
        'locations': [locationData],
      };
      
      if (_webSocketChannel != null && _isConnected) {
        _webSocketChannel!.sink.add(jsonEncode(message));
        developer.log('Location sent: $message', name: _tag);
      } else {
        developer.log('WebSocket not connected, cannot send location', name: _tag);
      }
    } catch (e) {
      developer.log('Error sending location: $e', name: _tag);
    }
  }
  
  /// Get the last known location
  void _getLastLocation(LocationCallback callback) async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log('Location services are disabled.', name: _tag);
        callback(null);
        return;
      }
      
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          developer.log('Location permissions are denied', name: _tag);
          callback(null);
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        developer.log('Location permissions are permanently denied', name: _tag);
        callback(null);
        return;
      }
      
      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      developer.log('getLastLocation: ${position.latitude}, ${position.longitude}', name: _tag);
      callback(position);
      
    } catch (e) {
      developer.log('Error getting location: $e', name: _tag);
      callback(null);
    }
  }
  
  /// Manually send current location
  Future<void> shareCurrentLocation() async {
    if (_currentUsername == null || !_isConnected) {
      developer.log('WebSocket not connected or username not set', name: _tag);
      return;
    }
    
    _getLastLocation((location) {
      if (location != null) {
        _sendLocation(_currentUsername!, location);
      } else {
        developer.log('Could not get current location', name: _tag);
      }
    });
  }
  
  /// Internal method to close WebSocket connection
  Future<void> _closeWebSocketInternal() async {
    try {
      await _webSocketSubscription?.cancel();
      _webSocketSubscription = null;
      
      if (_webSocketChannel != null) {
        await _webSocketChannel!.sink.close(status.normalClosure, 'App closed');
        _webSocketChannel = null;
      }
      
      _isConnected = false;
    } catch (e) {
      developer.log('Error closing WebSocket: $e', name: _tag);
    }
  }
  
  /// Close the WebSocket connection
  Future<void> closeWebSocket() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _currentUsername = null;
    
    await _closeWebSocketInternal();
    developer.log('Location WebSocket closed by user', name: _tag);
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await closeWebSocket();
  }
}