import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'websocket_service_manager.dart';

/// Provider for managing background WebSocket service state
class BackgroundServiceProvider extends ChangeNotifier {
  static const String _tag = 'BackgroundServiceProvider';
  
  // Service manager instance
  final WebSocketServiceManager _serviceManager = WebSocketServiceManager.instance;
  
  // Service state
  bool _isServiceRunning = false;
  bool _isConnected = false;
  String? _currentUsername;
  String _connectionStatus = 'Disconnected';
  
  // Stream subscriptions
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  
  // Message and typing data
  final List<Map<String, dynamic>> _recentMessages = [];
  final Map<String, bool> _typingUsers = {};
  
  BackgroundServiceProvider() {
    _initialize();
  }

  /// Getters
  bool get isServiceRunning => _isServiceRunning;
  bool get isConnected => _isConnected;
  String? get currentUsername => _currentUsername;
  String get connectionStatus => _connectionStatus;
  List<Map<String, dynamic>> get recentMessages => List.unmodifiable(_recentMessages);
  Map<String, bool> get typingUsers => Map.unmodifiable(_typingUsers);

  /// Initialize the provider
  Future<void> _initialize() async {
    try {
      developer.log('Initializing background service provider', name: _tag);
      
      // Initialize service manager
      await _serviceManager.initialize();
      
      // Setup stream listeners
      _setupStreamListeners();
      
      // Check current service status
      await _updateServiceStatus();
      
      // Auto-start if credentials available
      await _serviceManager.autoStartIfAvailable();
      
      developer.log('Background service provider initialized', name: _tag);
    } catch (e) {
      developer.log('Failed to initialize provider: $e', name: _tag, level: 1000);
    }
  }

  /// Setup stream listeners for service events
  void _setupStreamListeners() {
    // Connection status stream
    _connectionSubscription = _serviceManager.connectionStream.listen((isConnected) {
      _isConnected = isConnected;
      _connectionStatus = isConnected ? 'Connected' : 'Disconnected';
      developer.log('Connection status changed: $isConnected', name: _tag);
      notifyListeners();
    });
    
    // Message stream
    _messageSubscription = _serviceManager.messageStream.listen((message) {
      _handleMessage(message);
    });
    
    // Typing stream
    _typingSubscription = _serviceManager.typingStream.listen((typingData) {
      _handleTyping(typingData);
    });
  }

  /// Start the background service
  Future<bool> startService({required String username, String? token}) async {
    try {
      developer.log('Starting background service for: $username', name: _tag);
      _connectionStatus = 'Connecting...';
      notifyListeners();
      
      final success = await _serviceManager.startService(username: username, token: token);
      
      if (success) {
        _isServiceRunning = true;
        _currentUsername = username;
        _connectionStatus = 'Connected';
        developer.log('Background service started successfully', name: _tag);
      } else {
        _connectionStatus = 'Failed to connect';
        developer.log('Failed to start background service', name: _tag, level: 1000);
      }
      
      notifyListeners();
      return success;
    } catch (e) {
      _connectionStatus = 'Error: ${e.toString()}';
      developer.log('Error starting service: $e', name: _tag, level: 1000);
      notifyListeners();
      return false;
    }
  }

  /// Stop the background service
  Future<void> stopService() async {
    try {
      developer.log('Stopping background service', name: _tag);
      _connectionStatus = 'Disconnecting...';
      notifyListeners();
      
      await _serviceManager.stopService();
      
      _isServiceRunning = false;
      _isConnected = false;
      _currentUsername = null;
      _connectionStatus = 'Disconnected';
      _recentMessages.clear();
      _typingUsers.clear();
      
      developer.log('Background service stopped', name: _tag);
      notifyListeners();
    } catch (e) {
      developer.log('Error stopping service: $e', name: _tag, level: 1000);
    }
  }

  /// Restart the service
  Future<bool> restartService() async {
    try {
      developer.log('Restarting background service', name: _tag);
      _connectionStatus = 'Restarting...';
      notifyListeners();
      
      final success = await _serviceManager.restartService();
      
      if (success) {
        _connectionStatus = 'Connected';
      } else {
        _connectionStatus = 'Restart failed';
      }
      
      notifyListeners();
      return success;
    } catch (e) {
      _connectionStatus = 'Restart error: ${e.toString()}';
      developer.log('Error restarting service: $e', name: _tag, level: 1000);
      notifyListeners();
      return false;
    }
  }

  /// Send chat message
  Future<bool> sendChatMessage({
    required String chatId,
    required String content,
    String? messageType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _serviceManager.sendChatMessage(
        chatId: chatId,
        content: content,
        messageType: messageType,
        metadata: metadata,
      );
      return true;
    } catch (e) {
      developer.log('Failed to send chat message: $e', name: _tag, level: 1000);
      return false;
    }
  }

  /// Send media message
  Future<bool> sendMediaMessage({
    required String chatId,
    required String mediaType,
    required String mediaData,
    String? caption,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _serviceManager.sendMediaMessage(
        chatId: chatId,
        mediaType: mediaType,
        mediaData: mediaData,
        caption: caption,
        metadata: metadata,
      );
      return true;
    } catch (e) {
      developer.log('Failed to send media message: $e', name: _tag, level: 1000);
      return false;
    }
  }

  /// Send typing indicator
  Future<void> sendTyping({required String chatId, required bool isTyping}) async {
    await _serviceManager.sendTyping(chatId: chatId, isTyping: isTyping);
  }

  /// Mark message as read
  Future<void> markMessageRead({required String messageId}) async {
    await _serviceManager.markMessageRead(messageId: messageId);
  }

  /// Join chat room
  Future<void> joinChat({required String chatId}) async {
    await _serviceManager.joinChat(chatId: chatId);
  }

  /// Leave chat room
  Future<void> leaveChat({required String chatId}) async {
    await _serviceManager.leaveChat(chatId: chatId);
  }

  /// Handle app lifecycle changes
  void handleAppLifecycle(AppLifecycleState state) {
    developer.log('App lifecycle: $state', name: _tag);
    _serviceManager.handleAppLifecycle(state);
    
    // Update UI based on lifecycle
    switch (state) {
      case AppLifecycleState.resumed:
        _updateServiceStatus();
        break;
      case AppLifecycleState.paused:
        // App going to background
        break;
      default:
        break;
    }
  }

  /// Update service status
  Future<void> _updateServiceStatus() async {
    try {
      _isServiceRunning = await _serviceManager.checkServiceStatus();
      _currentUsername = _serviceManager.currentUsername;
      
      if (_isServiceRunning && _currentUsername != null) {
        _connectionStatus = _isConnected ? 'Connected' : 'Service running';
      } else {
        _connectionStatus = 'Disconnected';
      }
      
      notifyListeners();
    } catch (e) {
      developer.log('Error updating service status: $e', name: _tag, level: 1000);
    }
  }

  /// Handle incoming messages
  void _handleMessage(Map<String, dynamic> message) {
    try {
      developer.log('Handling message: ${message['type']}', name: _tag);
      
      // Add to recent messages (keep only last 50)
      _recentMessages.insert(0, message);
      if (_recentMessages.length > 50) {
        _recentMessages.removeRange(50, _recentMessages.length);
      }
      
      // Notify listeners about the new message
      notifyListeners();
      
    } catch (e) {
      developer.log('Error handling message: $e', name: _tag, level: 1000);
    }
  }

  /// Handle typing indicators
  void _handleTyping(Map<String, dynamic> typingData) {
    try {
      final username = typingData['username'] as String?;
      final chatId = typingData['chat_id'] as String?;
      final isTyping = typingData['is_typing'] as bool? ?? false;
      
      if (username != null && chatId != null) {
        final key = '$chatId:$username';
        
        if (isTyping) {
          _typingUsers[key] = true;
          
          // Auto-remove typing indicator after 3 seconds
          Timer(const Duration(seconds: 3), () {
            _typingUsers.remove(key);
            notifyListeners();
          });
        } else {
          _typingUsers.remove(key);
        }
        
        developer.log('Typing: $username in $chatId -> $isTyping', name: _tag);
        notifyListeners();
      }
    } catch (e) {
      developer.log('Error handling typing: $e', name: _tag, level: 1000);
    }
  }

  /// Get typing users for a specific chat
  List<String> getTypingUsersForChat(String chatId) {
    return _typingUsers.entries
        .where((entry) => entry.key.startsWith('$chatId:') && entry.value)
        .map((entry) => entry.key.split(':')[1])
        .toList();
  }

  /// Get recent messages for a specific chat
  List<Map<String, dynamic>> getRecentMessagesForChat(String chatId) {
    return _recentMessages
        .where((message) => message['chat_id'] == chatId)
        .toList();
  }

  /// Clear recent messages
  void clearRecentMessages() {
    _recentMessages.clear();
    notifyListeners();
  }

  /// Check if service is healthy
  bool get isServiceHealthy => _isServiceRunning && _isConnected;

  /// Get service health status
  String get serviceHealthStatus {
    if (!_isServiceRunning) return 'Service not running';
    if (!_isConnected) return 'Service running but not connected';
    return 'Service healthy';
  }

  @override
  void dispose() {
    developer.log('Disposing background service provider', name: _tag);
    
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    
    super.dispose();
  }
}