import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';

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

  // Authentication
  int? _lastUserId;
  String? _lastToken;

  // Message queuing
  final List<String> _messageQueue = [];
  final List<Uint8List> _videoQueue = [];

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

    try {
      // Build WebSocket URL with query parameters
      final uri = Uri.parse(_wsUrl).replace(queryParameters: {
        if (token != null) 'token': token,
        if (userId != null) 'user_id': userId.toString(),
      });

      debugPrint('$_tag: Connecting to WebSocket: ${uri.toString()}');

      // Create WebSocket connection
      _webSocket = WebSocketChannel.connect(uri);

      // Listen to messages
      _subscription = _webSocket!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onClosed,
      );

      // Mark as connected and notify listeners
      _updateConnectionState(true);
      _onConnected();

      // Start ping timer to keep connection alive
      _startPingTimer();
    } catch (e) {
      debugPrint('$_tag: Connection error: $e');
      _onError(e);
    }
  }

  /// Handle successful connection
  void _onConnected() {
    debugPrint('$_tag: WebSocket connected');
    _isConnected = true;
    _reconnectAttempts = 0;

    // Send queued messages
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

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic data) {
    try {
      final String text = data.toString();
      debugPrint('$_tag: Received message: $text');

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
        case 'message_updated':
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
    _updateConnectionState(false);
    _notifyConnectionFailed(error.toString());

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

  /// Send JSON message through WebSocket
  void _sendJson(Map<String, dynamic> json) {
    if (_isConnected && _webSocket != null) {
      final message = jsonEncode(json);
      debugPrint('$_tag: Sending: $message');
      _webSocket!.sink.add(message);
    } else {
      debugPrint('$_tag: WebSocket disconnected, queuing message');
      _messageQueue.add(jsonEncode(json));
      if (_shouldReconnect && !_isConnected) {
        _scheduleReconnect();
      }
    }
  }

  /// Close WebSocket connection
  void closeWebSocket() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(_normalClosureStatus);
    _webSocket = null;
    _updateConnectionState(false);
    _resetReconnectState();
    clearListeners();
    _videoUploadListener = null;
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

          // Parse the message using the standard fromJson method
          final message = Message.fromJson(messageDataForParsing);
          
          debugPrint('$_tag: Successfully created message: ${message.id} - ${message.content}');
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
        debugPrint('$_tag: Parsed new message with sender object: ${message.content}');
      } else {
        // Parse using standard format
        message = Message.fromJson(data);
        debugPrint('$_tag: Parsed new message with standard format: ${message.content}');
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
      for (final listener in List<ChatEventListener>.from(_listeners)) {
        try {
          listener.onChatSummariesReceived(chats);
        } catch (e) {
          debugPrint('$_tag: Error notifying active chats: $e');
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

  /// Send a message
  void sendMessage({
    required String chatId,
    required int receiverId,
    required String content,
    required String type,
    String? fileUrl,
  }) {
    debugPrint('$_tag: Sending message to chat: $chatId');
    final payload = {
      'action': 'send_message',
      'chat_id': chatId,
      'receiver_id': receiverId,
      'message_type': type,
      'content': content,
    };
    
    if (fileUrl != null) {
      payload['file_url'] = fileUrl;
    }
    
    _sendJson(payload);
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
}