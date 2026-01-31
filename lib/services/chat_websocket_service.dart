import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/user_presence.dart';

/// Represents a queued message waiting to be sent
class QueuedMessage {
  final String id;
  final String chatId;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  final int retryCount;
  final String type; // 'message', 'update', 'delete', etc.

  const QueuedMessage({
    required this.id,
    required this.chatId,
    required this.payload,
    required this.queuedAt,
    this.retryCount = 0,
    required this.type,
  });

  QueuedMessage copyWithRetry() {
    return QueuedMessage(
      id: id,
      chatId: chatId,
      payload: payload,
      queuedAt: queuedAt,
      retryCount: retryCount + 1,
      type: type,
    );
  }
}

/// Event listener interface for chat WebSocket events
abstract class ChatEventListener {
  void onUserFound(User user);
  void onGetOrCreateChat(Chat chat);
  void onMessagesReceived(List<Message> messages);
  void onNewMessage(Message message);
  void onMessageUpdated(Message message);
  void onMessageDeleted(String chatId, String messageId);
  void onMessagesSeen(List<String> messageIds);
  void onMessagesDelivered(List<String> messageIds);
  void onPresenceUpdate(UserPresence presence);
  void onContactsPresence(List<UserPresence> contacts);
  void onChatPresence(String chatId, List<UserPresence> members);
  void onSummaryUpdated(Chat summary);
  void onChatSummariesReceived(List<Chat> summaries);
  void onAllChatSummariesReceived(List<Chat> summaries);
  void onError(String error);
  void onConnectionEstablished();
  void onReconnectAttempt(int attemptCount);
  void onConnectionClosed();
  void onConnectionFailed(String error);
  void onConnectionClosing();
}

/// WebSocket service for real-time chat functionality
class ChatWebSocketService {
  static ChatWebSocketService? _instance;
  static const String _tag = 'ChatWebSocketService';
  static const int _normalClosureStatus = status.normalClosure;
  static const int _reconnectDelayMs = 5000;
  static const int _maxReconnectDelay = 30000;
  static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/chat/';

  // Connection management
  WebSocketChannel? _webSocket;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _connectionTimeoutTimer;

  // Authentication
  int? _lastUserId;
  String? _lastToken;

  // Message queuing
  final List<String> _messageQueue = [];
  final List<Uint8List> _videoQueue = [];
  final List<QueuedMessage> _enhancedMessageQueue = [];
  final Map<String, QueuedMessage> _pendingMessages = {};

  // Event listeners
  final List<ChatEventListener> _listeners = [];

  // Video upload state
  VoidCallback? _videoUploadListener;

  // Private constructor for singleton
  ChatWebSocketService._();

  /// Get singleton instance
  static ChatWebSocketService get instance {
    _instance ??= ChatWebSocketService._();
    return _instance!;
  }

  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Check if auto-reconnect is enabled
  bool get shouldReconnect => _shouldReconnect;

  /// Enable or disable auto-reconnect
  set shouldReconnect(bool value) {
    _shouldReconnect = value;
    if (!value) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  /// Add event listener
  void addListener(ChatEventListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// Remove event listener
  void removeListener(ChatEventListener listener) {
    _listeners.remove(listener);
  }

  /// Clear all event listeners
  void clearListeners() {
    _listeners.clear();
  }

  /// Connect to WebSocket using user ID or token
  Future<void> connectWebSocket({int? userId, String? token}) async {
    _lastUserId = userId;
    _lastToken = token;

    if (_isConnected) {
      debugPrint('$_tag: WebSocket already connected');
      return;
    }

    if (token == null && userId == null) {
      debugPrint('$_tag: Must provide userId or token');
      return;
    }

    // Log what we received to debug authentication
    debugPrint('$_tag: === WebSocket Connection Params ===');
    debugPrint('$_tag: userId: $userId');
    debugPrint('$_tag: token: ${token != null ? "${token.substring(0, token.length > 10 ? 10 : token.length)}..." : "null"}');
    debugPrint('$_tag: token length: ${token?.length ?? 0}');
    
    // Determine which auth method to use
    // Backend returns 40-char tokens (SHA1) for email/password login - these work with WebSocket
    // Backend returns 20-char tokens for Google/phone login - these DON'T work, use user_id instead
    final bool isLongToken = token != null && token.length >= 40;
    final bool useToken = isLongToken;
    debugPrint('$_tag: Using auth method: ${useToken ? "token (40+ chars)" : "user_id"}');

    try {
      // Build WebSocket URL with query parameters
      final baseUri = Uri.parse(_wsUrl);
      final uri = Uri(
        scheme: 'wss',
        host: baseUri.host,
        path: baseUri.path,
        queryParameters: {
          // Use token if available (email/password login), otherwise use user_id (phone/Google login)
          if (useToken) 
            'token': token
          else if (userId != null) 
            'user_id': userId.toString(),
        },
      );

      debugPrint('$_tag: Connecting to WebSocket: ${uri.toString()}');
      debugPrint('$_tag: URI scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}');
      debugPrint('$_tag: =====================================');

      // Create WebSocket connection
      _webSocket = WebSocketChannel.connect(uri);

      // Listen to messages
      _subscription = _webSocket!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onClosed,
      );

      // Don't mark as connected yet - wait for actual connection confirmation
      // Connection will be confirmed when we receive the first message successfully
      debugPrint('$_tag: WebSocket channel created, waiting for connection confirmation...');
      
      // Start connection timeout timer
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!_isConnected) {
          debugPrint('$_tag: WebSocket connection timeout after 10 seconds');
          closeWebSocket();
          _scheduleReconnect();
        }
      });
      
      // Send a connection test ping to confirm the connection works
      _sendConnectionTest();
    } catch (e) {
      debugPrint('$_tag: Connection error: $e');
      debugPrint('$_tag: Connection error type: ${e.runtimeType}');
      if (e.toString().contains('HTTP status code: 500')) {
        debugPrint('$_tag: Server returned HTTP 500 - backend server may be down or having issues');
        _notifyError('Server is currently unavailable (HTTP 500)');
      } else {
        _notifyError('Connection failed: $e');
      }
      _updateConnectionState(false);
      
      if (_shouldReconnect) {
        _scheduleReconnect();
      }
    }
  }

  /// Send a connection test to confirm WebSocket is ready
  void _sendConnectionTest() {
    try {
      debugPrint('$_tag: Sending connection test...');
      final testMessage = jsonEncode({
        'action': 'connection_test',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      _webSocket?.sink.add(testMessage);
    } catch (e) {
      debugPrint('$_tag: Failed to send connection test: $e');
      _updateConnectionState(false);
      if (_shouldReconnect) {
        _scheduleReconnect();
      }
    }
  }

  /// Handle successful connection
  void _onConnected() {
    debugPrint('$_tag: WebSocket connected and confirmed');
    _reconnectAttempts = 0;

    // Start ping timer to keep connection alive
    _startPingTimer();

    // Send enhanced queued messages first (with retry logic)
    _processEnhancedMessageQueue();

    // Send legacy queued messages
    while (_messageQueue.isNotEmpty) {
      final queuedMsg = _messageQueue.removeAt(0);
      _webSocket?.sink.add(queuedMsg);
    }

    // Send queued video data
    while (_videoQueue.isNotEmpty) {
      final video = _videoQueue.removeAt(0);
      _webSocket?.sink.add(video);
    }

    // Notify listeners
    _notifyConnectionEstablished();
  }

  /// Process enhanced message queue with retry logic
  void _processEnhancedMessageQueue() {
    debugPrint('$_tag: Processing enhanced message queue - Queue size: ${_enhancedMessageQueue.length}');
    
    if (_enhancedMessageQueue.isEmpty) {
      debugPrint('$_tag: No messages in enhanced queue to process');
      return;
    }
    
    final List<QueuedMessage> failedMessages = [];
    int processedCount = 0;
    
    while (_enhancedMessageQueue.isNotEmpty) {
      final queuedMessage = _enhancedMessageQueue.removeAt(0);
      processedCount++;
      
      debugPrint('$_tag: Processing queued message $processedCount/${processedCount + _enhancedMessageQueue.length} - ID: ${queuedMessage.id}, Type: ${queuedMessage.type}');
      
      try {
        // Send the queued message
        final jsonMessage = jsonEncode(queuedMessage.payload);
        debugPrint('$_tag: Sending queued message: $jsonMessage');
        _webSocket?.sink.add(jsonMessage);
        
        // Remove from pending messages since it's sent
        _pendingMessages.remove(queuedMessage.id);
        
        // Update message status to 'sending'
        _notifyMessageSentFromQueue(queuedMessage);
        
        debugPrint('$_tag: Successfully sent queued message ${queuedMessage.id} (${queuedMessage.type})');
        
        // Small delay between messages to avoid overwhelming the server
        if (_enhancedMessageQueue.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100));
        }
        
      } catch (e) {
        debugPrint('$_tag: Failed to send queued message ${queuedMessage.id}: $e');
        
        // Retry logic - only retry up to 3 times
        if (queuedMessage.retryCount < 3) {
          debugPrint('$_tag: Adding message ${queuedMessage.id} for retry (attempt ${queuedMessage.retryCount + 1}/3)');
          failedMessages.add(queuedMessage.copyWithRetry());
        } else {
          debugPrint('$_tag: Message ${queuedMessage.id} exceeded max retries, marking as permanently failed');
          // Max retries reached, mark as permanently failed
          _notifyMessagePermanentlyFailed(queuedMessage);
        }
      }
    }
    
    // Re-add failed messages that can be retried
    if (failedMessages.isNotEmpty) {
      debugPrint('$_tag: Re-adding ${failedMessages.length} failed messages for retry');
      _enhancedMessageQueue.addAll(failedMessages);
    }
    
    debugPrint('$_tag: Queue processing complete - Processed: $processedCount, Failed for retry: ${failedMessages.length}, Remaining: ${_enhancedMessageQueue.length}');
  }

  /// Notify listeners that a queued message was sent successfully
  void _notifyMessageSentFromQueue(QueuedMessage queuedMessage) {
    final sentMessage = Message(
      id: queuedMessage.id,
      chatId: queuedMessage.chatId,
      senderId: _lastUserId?.toString() ?? 'unknown',
      content: queuedMessage.payload['content']?.toString() ?? '',
      timestamp: queuedMessage.queuedAt,
      status: MessageStatus.sending, // Will be updated to 'sent' when server confirms
      type: _parseMessageType(queuedMessage.payload['message_type']?.toString() ?? 'text'),
      metadata: {
        'was_queued': true,
        'sent_from_queue_at': DateTime.now().toIso8601String(),
      },
    );
    
    _notifyMessageStatusUpdated(sentMessage);
  }

  /// Notify listeners that a queued message permanently failed
  void _notifyMessagePermanentlyFailed(QueuedMessage queuedMessage) {
    final failedMessage = Message(
      id: queuedMessage.id,
      chatId: queuedMessage.chatId,
      senderId: _lastUserId?.toString() ?? 'unknown',
      content: queuedMessage.payload['content']?.toString() ?? '',
      timestamp: queuedMessage.queuedAt,
      status: MessageStatus.failed,
      type: _parseMessageType(queuedMessage.payload['message_type']?.toString() ?? 'text'),
      metadata: {
        'permanently_failed': true,
        'retry_count': queuedMessage.retryCount,
        'failure_reason': 'max_retries_exceeded',
      },
    );
    
    _notifyMessageStatusUpdated(failedMessage);
    _pendingMessages.remove(queuedMessage.id);
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic data) {
    try {
      final String text = data.toString();
      debugPrint('$_tag: Received message: $text');

      // Confirm connection on first successful message
      if (!_isConnected) {
        debugPrint('$_tag: First message received, confirming connection...');
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
        _updateConnectionState(true);
        _onConnected();
      }

      final Map<String, dynamic> json = jsonDecode(text);
      final String? eventType = json['type'];
      final String? action = json['action'];
      final String? error = json['error'];
      final String? status = json['status'];

      // Handle video upload status
      if (status == 'ready_for_chunks') {
        _videoUploadListener?.call();
        _videoUploadListener = null;
        return;
      }

      // Handle different event types
      switch (eventType) {
        case 'user_fetched':
          if (error != null && error.isNotEmpty) {
            _notifyError(error);
          } else {
            _handleUserFetch(json);
          }
          break;
        case 'create_chat':
          _handleCreateChat(json['chat']);
          break;
        case 'chat_messages':
          _handleChatMessages(json);
          break;
        case 'new_message':
          _handleNewMessage(json['message']);
          break;
        case 'message_edited':
          _handleMessageUpdated(json['message']);
          break;
        case 'message_deleted':
          _handleMessageDeleted(json);
          break;
        case 'update':
          _handleStatusUpdate(json, action);
          break;
        case 'active_chats':
          _handleActiveChats(json);
          break;
        case 'all_chats':
          _handleAllChats(json);
          break;
        case 'chat_summary_updated':
          _handleSummaryUpdated(json['chat']);
          break;
        case 'contacts_presence':
          _handleContactsPresence(json);
          break;
        case 'presence_update':
          _handlePresenceUpdate(json);
          break;
        case 'user_presence':
          _handleUserPresence(json);
          break;
        case 'chat_presence':
          _handleChatPresence(json);
          break;
        case 'messages_seen':
        case 'message_seen':
          _handleMessagesSeen(json);
          break;
        default:
          debugPrint('$_tag: Unknown event type: $eventType');
      }
    } catch (e) {
      debugPrint('$_tag: Error parsing message: $e');
      _notifyError('Failed to parse message: $e');
    }
  }

  /// Handle WebSocket errors
  void _onError(dynamic error) {
    debugPrint('$_tag: WebSocket error: $error');
    debugPrint('$_tag: Error type: ${error.runtimeType}');
    
    _updateConnectionState(false);
    
    String errorMessage = error.toString();
    if (errorMessage.contains('HTTP status code: 500')) {
      errorMessage = 'Server is temporarily unavailable. Please try again later.';
      debugPrint('$_tag: Detected HTTP 500 error - backend server issue');
    } else if (errorMessage.contains('was not upgraded to websocket')) {
      errorMessage = 'WebSocket connection failed. Please check your internet connection.';
      debugPrint('$_tag: WebSocket upgrade failed');
    }
    
    _notifyConnectionFailed(errorMessage);

    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Handle WebSocket connection closed
  void _onClosed() {
    debugPrint('$_tag: WebSocket connection closed');
    _updateConnectionState(false);
    _notifyConnectionClosed();

    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Update connection state
  void _updateConnectionState(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      if (connected) {
        _resetReconnectState();
      } else {
        _stopPingTimer();
      }
    }
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (!_shouldReconnect || (_lastUserId == null && _lastToken == null)) {
      debugPrint('$_tag: Reconnect skipped');
      return;
    }

    _reconnectAttempts++;
    final delay = math.min(
      (_reconnectDelayMs * math.pow(2, _reconnectAttempts - 1)).toInt(),
      _maxReconnectDelay,
    );

    // Add jitter
    final jitteredDelay = delay + (math.Random().nextInt(1000));

    debugPrint('$_tag: Scheduling reconnect attempt #$_reconnectAttempts in ${jitteredDelay}ms');

    _reconnectTimer = Timer(Duration(milliseconds: jitteredDelay), () {
      if (!_isConnected && _shouldReconnect) {
        _notifyReconnectAttempt(_reconnectAttempts);
        connectWebSocket(userId: _lastUserId, token: _lastToken);
      }
    });
  }

  /// Reset reconnection state
  void _resetReconnectState() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isConnected && _webSocket != null) {
        _sendJson({'action': 'ping'});
      }
    });
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send JSON message through WebSocket with enhanced queuing
  void _sendJson(Map<String, dynamic> json, {String? messageId, String? chatId}) {
    debugPrint('$_tag: _sendJson called - Connected: $_isConnected, WebSocket: ${_webSocket != null}, MessageID: $messageId, ChatID: $chatId');
    
    if (_isConnected && _webSocket != null) {
      final message = jsonEncode(json);
      debugPrint('$_tag: Sending immediately: $message');
      _webSocket!.sink.add(message);
      
      // If this was a queued message, remove it from pending
      if (messageId != null) {
        _pendingMessages.remove(messageId);
        debugPrint('$_tag: Removed message $messageId from pending queue');
      }
    } else {
      debugPrint('$_tag: WebSocket disconnected (Connected: $_isConnected, WebSocket: ${_webSocket != null}), queuing message');
      
      // Enhanced queuing with message tracking
      if (messageId != null && chatId != null) {
        debugPrint('$_tag: Adding message to enhanced queue - ID: $messageId, Chat: $chatId, Action: ${json['action']}');
        
        final queuedMessage = QueuedMessage(
          id: messageId,
          chatId: chatId,
          payload: json,
          queuedAt: DateTime.now(),
          type: json['action']?.toString() ?? 'unknown',
        );
        
        _enhancedMessageQueue.add(queuedMessage);
        _pendingMessages[messageId] = queuedMessage;
        
        debugPrint('$_tag: Queue sizes - Enhanced: ${_enhancedMessageQueue.length}, Pending: ${_pendingMessages.length}');
        
        // Notify listeners that message is queued (failed status)
        _notifyMessageQueuedStatus(messageId, chatId);
      } else {
        debugPrint('$_tag: Adding to simple queue (no ID/ChatID) - Message: ${jsonEncode(json)}');
        // Fallback to simple queue for messages without IDs
        _messageQueue.add(jsonEncode(json));
      }
      
      if (_shouldReconnect && !_isConnected) {
        debugPrint('$_tag: Scheduling reconnect due to queued message');
        _scheduleReconnect();
      }
    }
  }

  /// Notify listeners that a message is queued (failed status)
  void _notifyMessageQueuedStatus(String messageId, String chatId) {
    // Create a temporary message with failed status to update UI
    final queuedMessage = Message(
      id: messageId,
      chatId: chatId,
      senderId: _lastUserId?.toString() ?? 'unknown',
      content: 'Message queued...',
      timestamp: DateTime.now(),
      status: MessageStatus.failed, // This will show the error icon
      type: MessageType.text,
      metadata: {
        'queued': true,
        'queue_reason': 'connection_lost',
        'queued_at': DateTime.now().toIso8601String(),
      },
    );
    
    // Notify all listeners that message status has been updated
    _notifyMessageStatusUpdated(queuedMessage);
  }

  /// Notify listeners about message status update
  void _notifyMessageStatusUpdated(Message message) {
    for (final listener in _listeners) {
      try {
        listener.onMessageUpdated(message);
      } catch (e) {
        debugPrint('$_tag: Error notifying listener of message update: $e');
      }
    }
  }

  /// Close WebSocket connection
  void closeWebSocket() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(_normalClosureStatus);
    _webSocket = null;
    _updateConnectionState(false);
    _resetReconnectState();
    clearListeners();
    _videoUploadListener = null;
  }

  /// Reconnect using stored credentials if available
  Future<bool> reconnectWithStoredCredentials() async {
    if (_lastUserId == null && _lastToken == null) {
      debugPrint('$_tag: No stored credentials available for reconnection');
      return false;
    }

    debugPrint('$_tag: Attempting reconnection with stored credentials');
    
    // Preserve existing listeners
    final existingListeners = List<ChatEventListener>.from(_listeners);
    debugPrint('$_tag: Preserving ${existingListeners.length} existing listeners');
    
    try {
      await connectWebSocket(userId: _lastUserId, token: _lastToken);
      
      // Restore listeners after connection
      for (final listener in existingListeners) {
        addListener(listener);
      }
      debugPrint('$_tag: Restored ${existingListeners.length} listeners after reconnection');
      
      return true;
    } catch (e) {
      debugPrint('$_tag: Reconnection with stored credentials failed: $e');
      
      // Restore listeners even if connection failed
      for (final listener in existingListeners) {
        addListener(listener);
      }
      debugPrint('$_tag: Restored listeners after failed reconnection attempt');
      
      return false;
    }
  }

  // Event notification methods
  void _notifyConnectionEstablished() {
    for (final listener in List<ChatEventListener>.from(_listeners)) {
      try {
        listener.onConnectionEstablished();
      } catch (e) {
        debugPrint('$_tag: Error notifying listener: $e');
      }
    }
  }

  void _notifyConnectionClosed() {
    for (final listener in List<ChatEventListener>.from(_listeners)) {
      try {
        listener.onConnectionClosed();
      } catch (e) {
        debugPrint('$_tag: Error notifying listener: $e');
      }
    }
  }

  void _notifyConnectionFailed(String error) {
    for (final listener in List<ChatEventListener>.from(_listeners)) {
      try {
        listener.onConnectionFailed(error);
      } catch (e) {
        debugPrint('$_tag: Error notifying listener: $e');
      }
    }
  }

  void _notifyReconnectAttempt(int attemptCount) {
    for (final listener in List<ChatEventListener>.from(_listeners)) {
      try {
        listener.onReconnectAttempt(attemptCount);
      } catch (e) {
        debugPrint('$_tag: Error notifying listener: $e');
      }
    }
  }

  void _notifyError(String error) {
    for (final listener in List<ChatEventListener>.from(_listeners)) {
      try {
        listener.onError(error);
      } catch (e) {
        debugPrint('$_tag: Error notifying listener: $e');
      }
    }
  }

  // ============================================================================
  // MESSAGE HANDLER METHODS
  // ============================================================================

  void _handleUserFetch(Map<String, dynamic> data) {
    try {
      final userMap = data['user'] as Map<String, dynamic>?;
      if (userMap != null) {
        final user = User.fromJson(userMap);
        for (final listener in List<ChatEventListener>.from(_listeners)) {
          try {
            listener.onUserFound(user);
          } catch (e) {
            debugPrint('$_tag: Error notifying user found: $e');
          }
        }
      } else {
        _notifyError('Error parsing user object');
      }
    } catch (e) {
      debugPrint('$_tag: Error handling user fetch: $e');
      _notifyError('Error creating user: $e');
    }
  }

  void _handleCreateChat(Map<String, dynamic>? data) {
    if (data == null) return;
    
    debugPrint('$_tag: Handling create chat with data: $data');
    
    try {
      // Parse the create_chat response format:
      // {"chat_id": 9, "user": {"id": 4, "username": "Tester1", "image_url": null}, "last_message": null}
      final chatId = data['chat_id']?.toString() ?? '';
      final userData = data['user'] as Map<String, dynamic>?;
      final lastMessageData = data['last_message'] as Map<String, dynamic>?;
      
      if (chatId.isEmpty || userData == null) {
        debugPrint('$_tag: Invalid create chat data - missing chat_id or user');
        return;
      }

      // Create User object from the user data
      final otherUser = User(
        id: userData['id'] as int,
        username: userData['username'] as String,
        email: userData['email'] as String? ?? '',
        imageUrl: userData['image_url'] as String?,
        createdAt: DateTime.now(),
      );

      // Create a proper Chat object
      final chat = Chat(
        id: chatId,
        name: otherUser.username, // Use username as chat name for direct chats
        type: ChatType.direct,
        participantIds: [_lastUserId?.toString() ?? '', otherUser.id.toString()],
        participants: [
          // Add current user (we'll need to get this from auth)
          if (_lastUserId != null) 
            User(
              id: _lastUserId!,
              username: 'You', // Temporary, should be from auth
              email: '',
              createdAt: DateTime.now(),
            ),
          otherUser,
        ],
        lastMessage: lastMessageData != null ? Message.fromJson(lastMessageData) : null,
        lastActivity: DateTime.now(),
        unreadCount: 0,
        createdAt: DateTime.now(),
      );

      debugPrint('$_tag: Created chat object: ${chat.id} with participants: ${chat.participants.map((u) => u.username).join(", ")}');

      // Notify listeners
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onGetOrCreateChat(chat);
        } catch (e) {
          debugPrint('$_tag: Error notifying create chat: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling create chat: $e');
      _notifyError('Error creating chat: $e');
    }
  }

  void _handleChatMessages(Map<String, dynamic> data) {
    debugPrint('$_tag: Handling chat messages with data: $data');
    
    try {
      final messagesArray = data['messages'] as List<dynamic>?;
      if (messagesArray == null) {
        debugPrint('$_tag: No messages array in chat_messages response');
        return;
      }

      debugPrint('$_tag: Processing ${messagesArray.length} chat messages');

      final messages = <Message>[];
      
      for (final msgData in messagesArray) {
        try {
          final messageMap = msgData as Map<String, dynamic>;
          debugPrint('$_tag: Processing message data: $messageMap');
          
          // Parse chat_messages response format:
          // {"id": 218, "chat_id": 9, "sender": {...}, "content": "Hi", "message_type": "text", 
          //  "file": null, "timestamp": "...", "recipients": [...]}
          
          final messageId = messageMap['id']?.toString() ?? '';
          final chatId = messageMap['chat_id']?.toString() ?? '';
          final content = messageMap['content']?.toString() ?? '';
          final messageType = messageMap['message_type']?.toString() ?? 'text';
          final timestamp = messageMap['timestamp']?.toString();
          final file = messageMap['file'];
          
          // Extract sender information
          final senderData = messageMap['sender'] as Map<String, dynamic>?;
          final senderId = senderData?['id']?.toString() ?? '';
          
          // Extract read status from recipients
          final recipients = messageMap['recipients'] as List<dynamic>?;
          String readStatus = 'sent'; // default
          if (recipients != null && recipients.isNotEmpty) {
            final recipient = recipients.first as Map<String, dynamic>;
            readStatus = recipient['read_status']?.toString() ?? 'sent';
          }
          
          debugPrint('$_tag: Parsed message - ID: $messageId, Chat: $chatId, Sender: $senderId, Content: $content');
          
          if (messageId.isEmpty || chatId.isEmpty || senderId.isEmpty) {
            debugPrint('$_tag: Invalid message data - missing required fields');
            continue;
          }

          // Check for reply_to_message in the original data
          final replyToMessageData = messageMap['reply_to_message'] as Map<String, dynamic>?;
          
          // Create a message data map that matches Message.fromJson expectations
          final messageDataForParsing = <String, dynamic>{
            'id': messageId,
            'chat_id': chatId,
            'sender_id': senderId,
            'content': content,
            'message_type': messageType,
            'read_status': readStatus,
            'timestamp': timestamp,
            'file': file,
          };
          
          // Add reply data if it exists
          if (replyToMessageData != null) {
            messageDataForParsing['reply_to_message'] = replyToMessageData;
          }

          // Parse the message using the standard fromJson method
          final message = Message.fromJson(messageDataForParsing);
          messages.add(message);
        } catch (e) {
          debugPrint('$_tag: Error parsing individual message: $e');
        }
      }

      debugPrint('$_tag: Successfully parsed ${messages.length} chat messages');

      // Notify listeners
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onMessagesReceived(messages);
        } catch (e) {
          debugPrint('$_tag: Error notifying messages received: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling chat messages: $e');
      _notifyError('Error loading messages: $e');
    }
  }

  void _handleNewMessage(Map<String, dynamic>? data) {
    if (data == null) return;
    
    debugPrint('$_tag: Handling new message with data: $data');
    
    try {
      Message message;
      
      // Check if this has the chat_messages format (with sender object)
      if (data.containsKey('sender') && data['sender'] is Map<String, dynamic>) {
        // Parse new message in chat_messages format
        final messageId = data['id']?.toString() ?? '';
        final chatId = data['chat_id']?.toString() ?? '';
        final content = data['content']?.toString() ?? '';
        final messageType = data['message_type']?.toString() ?? 'text';
        final timestamp = data['timestamp']?.toString();
        final file = data['file'];
        
        // Extract sender information
        final senderData = data['sender'] as Map<String, dynamic>;
        final senderId = senderData['id']?.toString() ?? '';
        
        // Extract read status from recipients
        final recipients = data['recipients'] as List<dynamic>?;
        String readStatus = 'sent'; // default
        if (recipients != null && recipients.isNotEmpty) {
          final recipient = recipients.first as Map<String, dynamic>;
          readStatus = recipient['read_status']?.toString() ?? 'sent';
        }
        
        // Check for reply_to_message in new message
        final replyToMessageData = data['reply_to_message'] as Map<String, dynamic>?;
        
        // Create a message data map that matches Message.fromJson expectations
        final messageDataForParsing = <String, dynamic>{
          'id': messageId,
          'chat_id': chatId,
          'sender_id': senderId,
          'content': content,
          'message_type': messageType,
          'read_status': readStatus,
          'timestamp': timestamp,
          'file': file,
        };
        
        // Add reply data if it exists
        if (replyToMessageData != null) {
          messageDataForParsing['reply_to_message'] = replyToMessageData;
        }

        message = Message.fromJson(messageDataForParsing);
        debugPrint('$_tag: ✅ PARSED MESSAGE - Type: ${message.type.name}, isCall: ${message.isCall}, Content starts with: ${message.content.substring(0, 50)}');
        debugPrint('$_tag: Parsed new message with sender object: ${message.content}');
      } else {
        // Parse using standard format
        message = Message.fromJson(data);
      }
      
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onNewMessage(message);
        } catch (e) {
          debugPrint('$_tag: Error notifying new message: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling new message: $e');
      _notifyError('Error processing new message: $e');
    }
  }

  void _handleMessageUpdated(Map<String, dynamic>? data) {
    if (data == null) return;
    
    debugPrint('$_tag: Handling message updated with data: $data');
    
    try {
      Message message;
      
      // Check if this has the chat_messages format (with sender object)
      if (data.containsKey('sender') && data['sender'] is Map<String, dynamic>) {
        // Parse updated message in chat_messages format
        final messageId = data['id']?.toString() ?? '';
        final chatId = data['chat_id']?.toString() ?? '';
        final content = data['content']?.toString() ?? '';
        final messageType = data['message_type']?.toString() ?? 'text';
        final timestamp = data['timestamp']?.toString();
        final file = data['file'];
        
        // Extract sender information
        final senderData = data['sender'] as Map<String, dynamic>;
        final senderId = senderData['id']?.toString() ?? '';
        
        // Extract read status from recipients
        final recipients = data['recipients'] as List<dynamic>?;
        String readStatus = 'sent'; // default
        if (recipients != null && recipients.isNotEmpty) {
          final recipient = recipients.first as Map<String, dynamic>;
          readStatus = recipient['read_status']?.toString() ?? 'sent';
        }
        
        // Create a message data map that matches Message.fromJson expectations
        final messageDataForParsing = <String, dynamic>{
          'id': messageId,
          'chat_id': chatId,
          'sender_id': senderId,
          'content': content,
          'message_type': messageType,
          'read_status': readStatus,
          'timestamp': timestamp,
          'file': file,
        };

        message = Message.fromJson(messageDataForParsing);
        debugPrint('$_tag: Parsed updated message with sender object: ${message.content}');
      } else {
        // Parse using standard format
        message = Message.fromJson(data);
        debugPrint('$_tag: Parsed updated message with standard format: ${message.content}');
      }
      
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onMessageUpdated(message);
        } catch (e) {
          debugPrint('$_tag: Error notifying message updated: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling message update: $e');
      _notifyError('Error updating message: $e');
    }
  }

  void _handleMessageDeleted(Map<String, dynamic> data) {
    try {
      final chatId = data['chat_id']?.toString();
      final messageId = data['message_id']?.toString();
      
      if (chatId != null && messageId != null) {
        for (final listener in List<ChatEventListener>.from(_listeners)) {
          try {
            listener.onMessageDeleted(chatId, messageId);
          } catch (e) {
            debugPrint('$_tag: Error notifying message deleted: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling message deletion: $e');
      _notifyError('Error deleting message: $e');
    }
  }

  void _handleStatusUpdate(Map<String, dynamic> data, String? action) {
    try {
      final messageIdsArray = data['message_ids'] as List<dynamic>?;
      if (messageIdsArray == null) return;

      final messageIds = messageIdsArray.map((id) => id.toString()).toList();

      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          if (action?.contains('read_delivered') == true) {
            listener.onMessagesDelivered(messageIds);
          }
          if (action?.contains('read_status') == true) {
            listener.onMessagesSeen(messageIds);
          }
        } catch (e) {
          debugPrint('$_tag: Error notifying status update: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling status update: $e');
      _notifyError('Error updating message status: $e');
    }
  }

  void _handleActiveChats(Map<String, dynamic> data) {
    debugPrint('$_tag: Handling active chats with data: $data');
    
    try {
      final chatsArray = data['chats'] as List<dynamic>?;
      if (chatsArray == null) {
        debugPrint('$_tag: No chats array in active_chats response');
        return;
      }

      debugPrint('$_tag: Processing ${chatsArray.length} active chats');

      final chats = <Chat>[];
      
      for (final chatData in chatsArray) {
        try {
          final chatMap = chatData as Map<String, dynamic>;
          debugPrint('$_tag: Processing chat data: $chatMap');
          
          // Parse the active_chats response format:
          // {"chat_id": 9, "user": {...}, "last_message": {...}}
          final chatId = chatMap['chat_id']?.toString() ?? '';
          final userData = chatMap['user'] as Map<String, dynamic>?;
          final lastMessageData = chatMap['last_message'] as Map<String, dynamic>?;
          
          if (chatId.isEmpty || userData == null) {
            debugPrint('$_tag: Invalid active chat data - missing chat_id or user');
            continue;
          }

          // Create User object from the user data
          final otherUser = User.fromJson(userData);
          debugPrint('$_tag: Parsed other user: ${otherUser.username} (ID: ${otherUser.id})');
          debugPrint('$_tag: Current _lastUserId: $_lastUserId');

          // Parse last message if present
          Message? lastMessage;
          if (lastMessageData != null) {
            try {
              // Add chat_id to message data since it's not included in the response
              final messageDataWithChatId = Map<String, dynamic>.from(lastMessageData);
              messageDataWithChatId['chat_id'] = chatId;
              
              lastMessage = Message.fromJson(messageDataWithChatId);
              debugPrint('$_tag: Parsed last message: ${lastMessage.content}');
            } catch (e) {
              debugPrint('$_tag: Error parsing last message: $e');
            }
          }

          // Create participant list
          final participants = <User>[];
          final participantIds = <String>[];
          
          // Add current user if we have the ID
          if (_lastUserId != null) {
            participants.add(User(
              id: _lastUserId!,
              username: 'You', // Temporary, should be from auth
              email: '',
              createdAt: DateTime.now(),
            ));
            participantIds.add(_lastUserId!.toString());
            debugPrint('$_tag: Added current user to participants (ID: $_lastUserId)');
          } else {
            debugPrint('$_tag: Warning - _lastUserId is null, cannot add current user to participants');
          }
          
          // Add other user
          participants.add(otherUser);
          participantIds.add(otherUser.id.toString());
          debugPrint('$_tag: Added other user to participants (ID: ${otherUser.id})');
          
          debugPrint('$_tag: Final participants count: ${participants.length}');
          debugPrint('$_tag: Final participantIds: $participantIds');

          // Create a proper Chat object
          final chat = Chat(
            id: chatId,
            name: otherUser.username, // Use username as chat name for direct chats
            type: ChatType.direct,
            participantIds: participantIds,
            participants: participants,
            lastMessage: lastMessage,
            lastActivity: lastMessage?.timestamp ?? DateTime.now(),
            unreadCount: 0, // TODO: Get from response if available
            createdAt: DateTime.now(),
          );

          debugPrint('$_tag: Created chat object: ${chat.id} - ${chat.name}');
          debugPrint('$_tag: Chat participants after creation: ${chat.participants.length}');
          debugPrint('$_tag: Chat participantIds after creation: ${chat.participantIds}');
          chats.add(chat);
        } catch (e) {
          debugPrint('$_tag: Error parsing individual chat: $e');
        }
      }

      debugPrint('$_tag: Successfully parsed ${chats.length} active chats');

      // Notify listeners
      debugPrint('$_tag: Notifying ${_listeners.length} listeners of active chats');
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          debugPrint('$_tag: Calling onChatSummariesReceived on listener: ${listener.runtimeType}');
          listener.onChatSummariesReceived(chats);
          debugPrint('$_tag: Successfully notified listener: ${listener.runtimeType}');
        } catch (e) {
          debugPrint('$_tag: Error notifying active chats to ${listener.runtimeType}: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling active chats: $e');
      _notifyError('Error loading active chats: $e');
    }
  }

  void _handleAllChats(Map<String, dynamic> data) {
    debugPrint('$_tag: Handling all chats with data: $data');
    
    try {
      final chatsArray = data['chats'] as List<dynamic>?;
      if (chatsArray == null) {
        debugPrint('$_tag: No chats array in all_chats response');
        return;
      }

      debugPrint('$_tag: Processing ${chatsArray.length} all chats');

      final chats = <Chat>[];
      
      for (final chatData in chatsArray) {
        try {
          final chatMap = chatData as Map<String, dynamic>;
          
          // Check if this is the active_chats format or a different format
          if (chatMap.containsKey('chat_id') && chatMap.containsKey('user')) {
            // Same format as active_chats
            final chatId = chatMap['chat_id']?.toString() ?? '';
            final userData = chatMap['user'] as Map<String, dynamic>?;
            final lastMessageData = chatMap['last_message'] as Map<String, dynamic>?;
            
            if (chatId.isEmpty || userData == null) {
              debugPrint('$_tag: Invalid all chat data - missing chat_id or user');
              continue;
            }

            // Create User object from the user data
            final otherUser = User.fromJson(userData);

            // Parse last message if present
            Message? lastMessage;
            if (lastMessageData != null) {
              try {
                // Add chat_id to message data since it's not included in the response
                final messageDataWithChatId = Map<String, dynamic>.from(lastMessageData);
                messageDataWithChatId['chat_id'] = chatId;
                
                lastMessage = Message.fromJson(messageDataWithChatId);
              } catch (e) {
                debugPrint('$_tag: Error parsing last message in all chats: $e');
              }
            }

            // Create a proper Chat object
            final chat = Chat(
              id: chatId,
              name: otherUser.username,
              type: ChatType.direct,
              participantIds: [_lastUserId?.toString() ?? '', otherUser.id.toString()],
              participants: [
                if (_lastUserId != null) 
                  User(
                    id: _lastUserId!,
                    username: 'You',
                    email: '',
                    createdAt: DateTime.now(),
                  ),
                otherUser,
              ],
              lastMessage: lastMessage,
              lastActivity: lastMessage?.timestamp ?? DateTime.now(),
              unreadCount: 0,
              createdAt: DateTime.now(),
            );

            chats.add(chat);
          } else {
            // Try parsing as regular Chat format
            final chat = Chat.fromJson(chatMap);
            chats.add(chat);
          }
        } catch (e) {
          debugPrint('$_tag: Error parsing individual chat in all chats: $e');
        }
      }

      debugPrint('$_tag: Successfully parsed ${chats.length} all chats');

      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onAllChatSummariesReceived(chats);
        } catch (e) {
          debugPrint('$_tag: Error notifying all chats: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling all chats: $e');
      _notifyError('Error loading all chats: $e');
    }
  }

  void _handleSummaryUpdated(Map<String, dynamic>? data) {
    if (data == null) return;
    
    try {
      debugPrint('$_tag: Handling summary updated with data: $data');
      final chat = Chat.fromJson(data);
      debugPrint('$_tag: Created chat from JSON - participants: ${chat.participants.length}, name: "${chat.name}"');
      
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onSummaryUpdated(chat);
        } catch (e) {
          debugPrint('$_tag: Error notifying summary updated: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling summary update: $e');
      _notifyError('Error updating chat summary: $e');
    }
  }

  // ============================================================================
  // PRESENCE HANDLERS
  // ============================================================================

  void _handleContactsPresence(Map<String, dynamic> data) {
    try {
      final List<dynamic> contactsData = data['contacts'] ?? [];
      final contacts = contactsData
          .map((contact) => UserPresence.fromJson(contact as Map<String, dynamic>))
          .toList();
      
      debugPrint('$_tag: Received presence for ${contacts.length} contacts');
      
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onContactsPresence(contacts);
        } catch (e) {
          debugPrint('$_tag: Error notifying contacts presence: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling contacts presence: $e');
      _notifyError('Error updating contacts presence: $e');
    }
  }

  void _handlePresenceUpdate(Map<String, dynamic> data) {
    try {
      final presenceData = data['presence'] as Map<String, dynamic>?;
      if (presenceData != null) {
        final presence = UserPresence.fromJson(presenceData);
        final status = data['status'] as String?;
        
        debugPrint('$_tag: Presence update: ${presence.username} is ${status ?? (presence.isOnline ? 'online' : 'offline')}');
        
        for (final listener in List<ChatEventListener>.from(_listeners)) {
          try {
            listener.onPresenceUpdate(presence);
          } catch (e) {
            debugPrint('$_tag: Error notifying presence update: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling presence update: $e');
      _notifyError('Error updating presence: $e');
    }
  }

  void _handleUserPresence(Map<String, dynamic> data) {
    try {
      final presenceData = data['presence'] as Map<String, dynamic>?;
      if (presenceData != null) {
        final presence = UserPresence.fromJson(presenceData);
        debugPrint('$_tag: User presence: ${presence.username} - ${presence.displayStatus}');
        
        for (final listener in List<ChatEventListener>.from(_listeners)) {
          try {
            listener.onPresenceUpdate(presence);
          } catch (e) {
            debugPrint('$_tag: Error notifying user presence: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling user presence: $e');
      _notifyError('Error updating user presence: $e');
    }
  }

  void _handleChatPresence(Map<String, dynamic> data) {
    try {
      final List<dynamic> membersData = data['members'] ?? [];
      final members = membersData
          .map((member) => UserPresence.fromJson(member as Map<String, dynamic>))
          .toList();
      
      final chatId = data['chat_id']?.toString() ?? '';
      debugPrint('$_tag: Chat $chatId presence: ${members.length} members');
      
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onChatPresence(chatId, members);
        } catch (e) {
          debugPrint('$_tag: Error notifying chat presence: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling chat presence: $e');
      _notifyError('Error updating chat presence: $e');
    }
  }

  void _handleMessagesSeen(Map<String, dynamic> data) {
    try {
      final List<dynamic>? messageIds = data['message_ids'];
      final String? chatId = data['chat_id']?.toString();
      
      if (messageIds == null || chatId == null) {
        debugPrint('$_tag: Invalid messages seen data: missing message_ids or chat_id');
        return;
      }

      final List<String> seenMessageIds = messageIds.map((id) => id.toString()).toList();
      debugPrint('$_tag: Messages marked as seen in chat $chatId: ${seenMessageIds.length} messages');
      
      // Notify listeners to update message status to read
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onMessagesSeen(seenMessageIds);
        } catch (e) {
          debugPrint('$_tag: Error notifying messages seen: $e');
        }
      }
    } catch (e) {
      debugPrint('$_tag: Error handling messages seen: $e');
      _notifyError('Error processing read receipts: $e');
    }
  }

  // ============================================================================
  // PUBLIC API METHODS
  // ============================================================================

  /// Load messages for a specific chat
  void loadMessagesWithUser(String chatId) {
    debugPrint('$_tag: Loading messages for chat: $chatId');
    _sendJson({
      'action': 'get_messages',
      'chat_id': chatId,
    });
  }

  /// Load all chats
  void loadAllChats() {
    debugPrint('$_tag: Loading all chats');
    _sendJson({
      'action': 'get_all_chats',
    });
  }

  /// Load active chats
  void loadActiveChats() {
    debugPrint('$_tag: Loading active chats');
    _sendJson({
      'action': 'get_active_chats',
    });
  }

  /// Find user by email
  void findUser(String email) {
    debugPrint('$_tag: Finding user with email: $email');
    _sendJson({
      'action': 'fetch_user',
      'email': email,
    });
  }

  /// Get or create chat with user
  void getOrCreateChatWithUser(int userId) {
    debugPrint('$_tag: Getting or creating chat with user: $userId');
    _sendJson({
      'action': 'create_chat',
      'user_id': userId,
    });
  }

  /// Send a message with enhanced queuing support
  void sendMessage({
    required String chatId,
    required int receiverId,
    required String content,
    required String type,
    String? fileUrl,
    String? messageId, // Optional message ID for tracking
    String? replyToMessageId, // Reply to message ID
  }) {
    debugPrint('$_tag: 🚀 sendMessage called - ChatID: $chatId, Type: $type, ProvidedID: $messageId, ReplyTo: $replyToMessageId, Content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content}');
    
    // Generate temporary ID if not provided
    final tempId = messageId ?? 'temp_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
    debugPrint('$_tag: 🆔 Using message ID: $tempId (provided: ${messageId != null})');
    
    final payload = {
      'action': 'send_message',
      'chat_id': chatId,
      'receiver_id': receiverId,
      'message_type': type,
      'content': content,
      'temp_message_id': tempId, // Include temp ID for tracking
    };
    
    if (fileUrl != null) {
      payload['file_url'] = fileUrl;
      debugPrint('$_tag: 📎 Including file URL: $fileUrl');
    }
    
    if (replyToMessageId != null) {
      payload['reply_to_message_id'] = replyToMessageId;
      debugPrint('$_tag: 💬 Including reply to message ID: $replyToMessageId');
    }
    
    debugPrint('$_tag: 📤 Calling _sendJson with messageId: $tempId, chatId: $chatId');
    // Use enhanced queuing with message tracking
    _sendJson(payload, messageId: tempId, chatId: chatId);
  }

  /// Update a message
  void updateMessage(String messageId, String newContent) {
    debugPrint('$_tag: Updating message: $messageId');
    _sendJson({
      'action': 'edit_message',
      'message_id': messageId,
      'new_content': newContent,
    });
  }

  /// Delete a message
  void deleteMessage(String messageId) {
    debugPrint('$_tag: Deleting message: $messageId');
    _sendJson({
      'action': 'delete_message',
      'message_id': messageId,
    });
  }

  /// Mark messages as seen
  void markMessagesSeen(List<String> messageIds) {
    debugPrint('$_tag: Marking messages as seen: $messageIds');
    _sendJson({
      'action': 'mark_seen',
      'message_ids': messageIds,
    });
  }

  /// Mark messages as delivered
  void markMessagesDelivered(List<String> messageIds) {
    debugPrint('$_tag: Marking messages as delivered: $messageIds');
    _sendJson({
      'action': 'mark_delivered',
      'message_ids': messageIds,
    });
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Parse string to MessageType enum
  MessageType _parseMessageType(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'audio':
        return MessageType.audio;
      case 'file':
        return MessageType.file;
      case 'call_invitation':
      case 'call_accepted':
      case 'call_rejected':
      case 'call_declined':
      case 'call_ended':
      case 'call':
        return MessageType.call;
      default:
        return MessageType.text;
    }
  }

  /// Get the number of messages currently queued
  int get queuedMessageCount => _enhancedMessageQueue.length + _messageQueue.length;

  /// Get queued messages for a specific chat
  List<QueuedMessage> getQueuedMessagesForChat(String chatId) {
    return _enhancedMessageQueue.where((msg) => msg.chatId == chatId).toList();
  }

  /// Check if a specific message is currently queued
  bool isMessageQueued(String messageId) {
    return _pendingMessages.containsKey(messageId);
  }

  /// Manually retry sending a specific queued message
  void retryQueuedMessage(String messageId) {
    final queuedMessage = _pendingMessages[messageId];
    if (queuedMessage != null && _isConnected && _webSocket != null) {
      try {
        final jsonMessage = jsonEncode(queuedMessage.payload);
        _webSocket!.sink.add(jsonMessage);
        
        // Remove from pending and queues
        _pendingMessages.remove(messageId);
        _enhancedMessageQueue.removeWhere((msg) => msg.id == messageId);
        
        // Update status
        _notifyMessageSentFromQueue(queuedMessage);
        
        debugPrint('$_tag: Manually retried message $messageId');
      } catch (e) {
        debugPrint('$_tag: Manual retry failed for message $messageId: $e');
      }
    }
  }

  /// Clear all queued messages (use with caution)
  void clearMessageQueue() {
    _enhancedMessageQueue.clear();
    _messageQueue.clear();
    _pendingMessages.clear();
    debugPrint('$_tag: Message queues cleared');
  }

  /// Check if the backend server is reachable (simple connectivity test)
  Future<bool> checkServerHealth() async {
    try {
      final baseUri = Uri.parse(_wsUrl);
      final healthUri = Uri(
        scheme: 'https', // Use HTTPS for health check
        host: baseUri.host,
        path: '/health', // Assuming there's a health endpoint
      );
      
      debugPrint('$_tag: Checking server health at ${healthUri.toString()}');
      // This would require adding http package dependency
      // For now, just return true and rely on WebSocket connection attempt
      return true;
    } catch (e) {
      debugPrint('$_tag: Server health check failed: $e');
      return false;
    }
  }

  // ============================================================================
  // PRESENCE API METHODS
  // ============================================================================

  /// Get presence for a specific user
  void getUserPresence(String userId) {
    debugPrint('$_tag: Getting user presence: $userId');
    _sendJson({
      'action': 'get_presence',
      'user_id': userId,
    });
  }

  /// Get presence for all contacts
  void getContactsPresence() {
    debugPrint('$_tag: Getting contacts presence');
    _sendJson({
      'action': 'get_contacts_presence',
    });
  }

  /// Get presence for chat members
  void getChatPresence(String chatId) {
    debugPrint('$_tag: Getting chat presence: $chatId');
    _sendJson({
      'action': 'get_chat_presence',
      'chat_id': chatId,
    });
  }

}