import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_websocket_service.dart';

/// Manager for coordinating between foreground app and background WebSocket service
class WebSocketServiceManager {
  static const String _tag = 'WebSocketManager';
  
  // Singleton instance
  static WebSocketServiceManager? _instance;
  static WebSocketServiceManager get instance => _instance ??= WebSocketServiceManager._();
  
  // Service state
  bool _isInitialized = false;
  bool _isServiceRunning = false;
  String? _currentUsername;
  String? _currentToken;
  
  // Stream controllers for forwarding background messages to UI
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionController = 
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  // Subscription to background service
  StreamSubscription? _serviceSubscription;
  
  WebSocketServiceManager._();

  /// Stream of messages from background service
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  /// Stream of connection status changes
  Stream<bool> get connectionStream => _connectionController.stream;
  
  /// Stream of typing indicators
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  
  /// Whether the service is currently running
  bool get isServiceRunning => _isServiceRunning;
  
  /// Current connected username
  String? get currentUsername => _currentUsername;

  /// Initialize the WebSocket service manager
  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log('Service manager already initialized', name: _tag);
      return;
    }
    
    try {
      developer.log('Initializing WebSocket service manager...', name: _tag);
      
      // Initialize background service
      await BackgroundWebSocketService.initialize();
      
      // Setup service message listener
      _setupServiceListener();
      
      // Load saved connection info
      await _loadConnectionInfo();
      
      _isInitialized = true;
      developer.log('WebSocket service manager initialized successfully', name: _tag);
      
    } catch (e) {
      developer.log('Failed to initialize service manager: $e', name: _tag, level: 1000);
      throw Exception('Failed to initialize WebSocket service manager: $e');
    }
  }

  /// Start the background WebSocket service
  Future<bool> startService({required String username, String? token}) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      
      developer.log('Starting WebSocket service for user: $username', name: _tag);
      
      // Save connection info
      await _saveConnectionInfo(username, token);
      
      // Start background service
      await BackgroundWebSocketService.startService();
      
      // Connect to WebSocket in background
      await BackgroundWebSocketService.sendToService('connect', {
        'data': {
          'username': username,
          'token': token,
        }
      });
      
      _currentUsername = username;
      _currentToken = token;
      _isServiceRunning = true;
      
      developer.log('WebSocket service started successfully', name: _tag);
      _connectionController.add(true);
      
      return true;
    } catch (e) {
      developer.log('Failed to start WebSocket service: $e', name: _tag, level: 1000);
      _connectionController.add(false);
      return false;
    }
  }

  /// Stop the background WebSocket service
  Future<void> stopService() async {
    try {
      developer.log('Stopping WebSocket service', name: _tag);
      
      // Disconnect WebSocket
      await BackgroundWebSocketService.sendToService('disconnect', {});
      
      // Stop background service
      await BackgroundWebSocketService.stopService();
      
      // Clear connection info
      await _clearConnectionInfo();
      
      _currentUsername = null;
      _currentToken = null;
      _isServiceRunning = false;
      
      developer.log('WebSocket service stopped', name: _tag);
      _connectionController.add(false);
      
    } catch (e) {
      developer.log('Failed to stop WebSocket service: $e', name: _tag, level: 1000);
    }
  }

  /// Send message through background service
  Future<bool> sendMessage(Map<String, dynamic> message) async {
    try {
      if (!_isServiceRunning) {
        developer.log('Service not running, cannot send message', name: _tag, level: 900);
        return false;
      }
      
      await BackgroundWebSocketService.sendToService('send_message', {
        'data': message,
      });
      
      developer.log('Message sent to background service: ${message['type']}', name: _tag);
      return true;
    } catch (e) {
      developer.log('Failed to send message: $e', name: _tag, level: 1000);
      return false;
    }
  }

  /// Check if background service is running
  Future<bool> checkServiceStatus() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      _isServiceRunning = isRunning;
      return isRunning;
    } catch (e) {
      developer.log('Failed to check service status: $e', name: _tag, level: 1000);
      return false;
    }
  }

  /// Restart service with current credentials
  Future<bool> restartService() async {
    try {
      if (_currentUsername != null) {
        developer.log('Restarting WebSocket service', name: _tag);
        await stopService();
        await Future.delayed(const Duration(seconds: 2));
        return await startService(username: _currentUsername!, token: _currentToken);
      } else {
        developer.log('No stored credentials for restart', name: _tag, level: 900);
        return false;
      }
    } catch (e) {
      developer.log('Failed to restart service: $e', name: _tag, level: 1000);
      return false;
    }
  }

  /// Setup listener for background service messages
  void _setupServiceListener() {
    try {
      final service = FlutterBackgroundService();
      
      _serviceSubscription = service.on('websocket_message').listen((event) {
        try {
          final data = event!['data'] as Map<String, dynamic>;
          developer.log('Received message from background service: ${data['type']}', name: _tag);
          
          // Forward to appropriate stream
          switch (data['type']) {
            case 'new_message':
            case 'message_status':
              _messageController.add(data);
              break;
            case 'typing':
              _typingController.add(data);
              break;
            case 'connection_status':
              final isConnected = data['connected'] as bool? ?? false;
              _connectionController.add(isConnected);
              break;
            default:
              _messageController.add(data);
          }
        } catch (e) {
          developer.log('Error processing service message: $e', name: _tag, level: 1000);
        }
      });
      
      developer.log('Service listener setup complete', name: _tag);
    } catch (e) {
      developer.log('Failed to setup service listener: $e', name: _tag, level: 1000);
    }
  }

  /// Save connection info to persistent storage
  Future<void> _saveConnectionInfo(String username, String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('websocket_username', username);
      if (token != null) {
        await prefs.setString('websocket_token', token);
      } else {
        await prefs.remove('websocket_token');
      }
      developer.log('Connection info saved', name: _tag);
    } catch (e) {
      developer.log('Failed to save connection info: $e', name: _tag, level: 1000);
    }
  }

  /// Load connection info from persistent storage
  Future<void> _loadConnectionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUsername = prefs.getString('websocket_username');
      _currentToken = prefs.getString('websocket_token');
      
      if (_currentUsername != null) {
        developer.log('Loaded connection info for: $_currentUsername', name: _tag);
      }
    } catch (e) {
      developer.log('Failed to load connection info: $e', name: _tag, level: 1000);
    }
  }

  /// Clear stored connection info
  Future<void> _clearConnectionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('websocket_username');
      await prefs.remove('websocket_token');
      developer.log('Connection info cleared', name: _tag);
    } catch (e) {
      developer.log('Failed to clear connection info: $e', name: _tag, level: 1000);
    }
  }

  /// Auto-start service if credentials are available
  Future<void> autoStartIfAvailable() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      
      await _loadConnectionInfo();
      
      if (_currentUsername != null) {
        final isRunning = await checkServiceStatus();
        if (!isRunning) {
          developer.log('Auto-starting service for: $_currentUsername', name: _tag);
          await startService(username: _currentUsername!, token: _currentToken);
        } else {
          developer.log('Service already running for: $_currentUsername', name: _tag);
          _isServiceRunning = true;
        }
      }
    } catch (e) {
      developer.log('Failed to auto-start service: $e', name: _tag, level: 1000);
    }
  }

  /// Handle app lifecycle changes
  void handleAppLifecycle(AppLifecycleState state) {
    developer.log('App lifecycle changed: $state', name: _tag);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // App going to background - ensure service is running
        if (_currentUsername != null && !_isServiceRunning) {
          startService(username: _currentUsername!, token: _currentToken);
        }
        break;
      case AppLifecycleState.resumed:
        // App returning to foreground - check service status
        checkServiceStatus();
        break;
      default:
        break;
    }
  }

  /// Send typing indicator
  Future<void> sendTyping({required String chatId, required bool isTyping}) async {
    await sendMessage({
      'type': 'typing',
      'chat_id': chatId,
      'is_typing': isTyping,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send chat message
  Future<void> sendChatMessage({
    required String chatId,
    required String content,
    String? messageType,
    Map<String, dynamic>? metadata,
  }) async {
    await sendMessage({
      'type': 'chat_message',
      'chat_id': chatId,
      'content': content,
      'message_type': messageType ?? 'text',
      'metadata': metadata ?? {},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send media message
  Future<void> sendMediaMessage({
    required String chatId,
    required String mediaType,
    required String mediaData,
    String? caption,
    Map<String, dynamic>? metadata,
  }) async {
    await sendMessage({
      'type': 'media_message',
      'chat_id': chatId,
      'media_type': mediaType,
      'media_data': mediaData,
      'caption': caption,
      'metadata': metadata ?? {},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Mark message as read
  Future<void> markMessageRead({required String messageId}) async {
    await sendMessage({
      'type': 'mark_read',
      'message_id': messageId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Join chat room
  Future<void> joinChat({required String chatId}) async {
    await sendMessage({
      'type': 'join_chat',
      'chat_id': chatId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Leave chat room
  Future<void> leaveChat({required String chatId}) async {
    await sendMessage({
      'type': 'leave_chat',
      'chat_id': chatId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Dispose the service manager
  void dispose() {
    developer.log('Disposing WebSocket service manager', name: _tag);
    
    _serviceSubscription?.cancel();
    _messageController.close();
    _connectionController.close();
    _typingController.close();
  }
}