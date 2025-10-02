import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'chat_websocket_service.dart';
import 'camera_service.dart';
import 'enhanced_file_upload_service.dart';

/// Manages the state of chats and messages with seamless WebSocket integration
/// This service acts as a centralized state manager that syncs with the WebSocket service
class ChatStateManager extends ChangeNotifier implements ChatEventListener {
  static ChatStateManager? _instance;
  static ChatStateManager get instance => _instance ??= ChatStateManager._();
  
  ChatStateManager._() {
    _chatWebSocketService.addListener(this);
  }

  final ChatWebSocketService _chatWebSocketService = ChatWebSocketService.instance;
  final Map<String, List<Message>> _chatMessages = {};
  final Map<String, Chat> _chats = {};
  final Map<String, User> _users = {};
  
  // Chat creation tracking
  final Map<int, Completer<Chat?>> _chatCreationCompleters = {};
  
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _currentUserId;
  String? _errorMessage;

  // Getters
  List<Chat> get chats => _chats.values.toList()..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  Map<String, List<Message>> get chatMessages => Map.unmodifiable(_chatMessages);
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _chatWebSocketService.isConnected;
  String? get currentUserId => _currentUserId;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  
  /// Get current user ID with consistent format for UI components
  String getCurrentUserIdForUI() {
    if (_currentUserId != null) {
      return _currentUserId!;
    }
    
    // Log warning if currentUserId is null
    debugPrint('ChatStateManager: Warning - currentUserId is null, returning fallback');
    return 'unknown';
  }

  /// Initialize the chat state manager with user context
  Future<void> initialize(String userId) async {
    if (_isInitialized && _currentUserId == userId) return;
    
    _currentUserId = userId;
    _setLoading(true);
    
    try {
      debugPrint('ChatStateManager: Initializing for user: $userId');
      
      // Clear previous state
      _chats.clear();
      _chatMessages.clear();
      
      // Load initial data if WebSocket is connected
      if (_chatWebSocketService.isConnected) {
        _chatWebSocketService.loadActiveChats();
      }
      
      _isInitialized = true;
      debugPrint('ChatStateManager: Initialization complete');
    } catch (e) {
      debugPrint('ChatStateManager: Initialization failed: $e');
      _setError('Failed to initialize chat service: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Get messages for a specific chat
  List<Message> getMessagesForChat(String chatId) {
    return _chatMessages[chatId] ?? [];
  }

  /// Get a specific chat by ID
  Chat? getChat(String chatId) {
    return _chats[chatId];
  }

  /// Load messages for a specific chat
  Future<void> loadMessagesForChat(String chatId) async {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('ChatStateManager: Cannot load messages - WebSocket not connected');
      return;
    }

    try {
      debugPrint('ChatStateManager: Loading messages for chat: $chatId');
      _chatWebSocketService.loadMessagesWithUser(chatId);
    } catch (e) {
      debugPrint('ChatStateManager: Failed to load messages for chat $chatId: $e');
    }
  }

  /// Send a text message
  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    int? receiverId,
    String? fileUrl,
  }) async {
    if (!_chatWebSocketService.isConnected) {
      throw Exception('WebSocket not connected');
    }

    try {
      // Create optimistic message with a trackable temporary ID
      final tempId = 'optimistic_${_currentUserId ?? 'unknown'}_${DateTime.now().millisecondsSinceEpoch}';
      final message = Message(
        id: tempId,
        chatId: chatId,
        senderId: _currentUserId ?? '',
        content: content,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: _parseMessageType(type),
        metadata: fileUrl != null ? {'file_url': fileUrl} : null,
      );
      
      debugPrint('ChatStateManager: Created optimistic message with ID: $tempId');

      // Add optimistic message to local state
      _addMessageToChat(chatId, message);

      // Send via WebSocket
      _chatWebSocketService.sendMessage(
        chatId: chatId,
        receiverId: receiverId ?? 0,
        content: content,
        type: type,
        fileUrl: fileUrl,
      );

      // Update message status to sent (optimistic)
      final updatedMessage = message.copyWith(status: MessageStatus.sent);
      _updateMessageInChat(chatId, updatedMessage);
      
    } catch (e) {
      debugPrint('ChatStateManager: Failed to send message: $e');
      rethrow;
    }
  }

  /// Send multimedia message (image, video, audio)
  Future<void> sendMultimediaMessage({
    required String chatId,
    required CameraResult mediaResult,
    int? receiverId,
    Function(double)? onUploadProgress,
  }) async {
    if (!_chatWebSocketService.isConnected) {
      throw Exception('WebSocket not connected');
    }

    try {
      debugPrint('ChatStateManager: Starting multimedia message send for chat: $chatId');
      
      // Create optimistic message with sending status
      final tempId = 'multimedia_${_currentUserId ?? 'unknown'}_${DateTime.now().millisecondsSinceEpoch}';
      final optimisticMessage = Message(
        id: tempId,
        chatId: chatId,
        senderId: _currentUserId ?? '',
        content: 'Sending ${mediaResult.type.name}...',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: _parseMessageType(mediaResult.type.name),
        metadata: {
          'file_size': mediaResult.size,
          'upload_progress': 0.0,
          'is_uploading': true,
        },
      );
      
      debugPrint('ChatStateManager: Created optimistic multimedia message with ID: $tempId');

      // Add optimistic message to local state
      _addMessageToChat(chatId, optimisticMessage);

      // Upload file to server with local caching
      final uploadResult = await EnhancedFileUploadService.uploadMediaWithCaching(
        mediaResult,
        chatId,
        onProgress: (progress) {
          // Update message with upload progress
          final progressMessage = optimisticMessage.copyWith(
            content: 'Uploading ${mediaResult.type.name}... ${(progress * 100).round()}%',
            metadata: {
              ...optimisticMessage.metadata ?? {},
              'upload_progress': progress,
            },
          );
          _updateMessageInChat(chatId, progressMessage);
          
          // Call external progress callback
          onUploadProgress?.call(progress);
        },
      );

      if (!uploadResult.success) {
        throw Exception(uploadResult.error ?? 'Upload failed');
      }

      debugPrint('ChatStateManager: File uploaded successfully: ${uploadResult.fileUrl}, timestamp: ${uploadResult.timestamp}');

      // Update message with upload complete status using timestamp as content
      final uploadCompleteMessage = optimisticMessage.copyWith(
        content: uploadResult.timestamp, // Use timestamp for local caching
        metadata: {
          'file_url': uploadResult.fileUrl,
          'file_size': uploadResult.fileSize,
          'file_name': uploadResult.fileName,
          'duration': uploadResult.duration,
          'thumbnail_path': uploadResult.thumbnailPath,
          'upload_progress': 1.0,
          'is_uploading': false,
        },
      );
      _updateMessageInChat(chatId, uploadCompleteMessage);

      // Send message via WebSocket with timestamp as content and file URL
      _chatWebSocketService.sendMessage(
        chatId: chatId,
        receiverId: receiverId ?? 0,
        content: uploadResult.timestamp, // Send timestamp as content
        type: mediaResult.type.name,
        fileUrl: uploadResult.fileUrl,
      );

      // Update message status to sent
      final sentMessage = uploadCompleteMessage.copyWith(status: MessageStatus.sent);
      _updateMessageInChat(chatId, sentMessage);

      debugPrint('ChatStateManager: Multimedia message sent successfully');

    } catch (e) {
      debugPrint('ChatStateManager: Failed to send multimedia message: $e');
      
      // Update message with failed status
      if (_chatMessages.containsKey(chatId)) {
        final messages = _chatMessages[chatId]!;
        final messageIndex = messages.indexWhere((m) => m.id.startsWith('multimedia_${_currentUserId ?? 'unknown'}'));
        
        if (messageIndex != -1) {
          final failedMessage = messages[messageIndex].copyWith(
            status: MessageStatus.failed,
            content: 'Failed to send ${mediaResult.type.name}',
            metadata: {
              ...messages[messageIndex].metadata ?? {},
              'error': e.toString(),
              'is_uploading': false,
            },
          );
          messages[messageIndex] = failedMessage;
          notifyListeners();
        }
      }
      
      rethrow;
    }
  }

  /// Create or get a chat with another user
  Future<Chat?> createOrGetChatWithUser(int userId) async {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('ChatStateManager: Cannot create chat - WebSocket not connected');
      return null;
    }

    try {
      // Check if chat already exists with this user
      try {
        final existingChat = _chats.values.firstWhere(
          (chat) => chat.isDirectChat && chat.participantIds.contains(userId.toString()),
        );
        debugPrint('ChatStateManager: Chat already exists with user $userId');
        return existingChat;
      } catch (e) {
        // No existing chat found, proceed to create one
        debugPrint('ChatStateManager: No existing chat found with user $userId, creating new one');
      }

      // Create a completer to wait for the chat creation response
      final completer = Completer<Chat?>();
      _chatCreationCompleters[userId] = completer;

      // Send the WebSocket request
      _chatWebSocketService.getOrCreateChatWithUser(userId);
      
      // Wait for the response with a timeout
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('ChatStateManager: Timeout waiting for chat creation with user $userId');
          _chatCreationCompleters.remove(userId);
          return null;
        },
      );
    } catch (e) {
      debugPrint('ChatStateManager: Failed to create/get chat with user $userId: $e');
      _chatCreationCompleters.remove(userId);
      return null;
    }
  }

  /// Find a user by username or email
  Future<User?> findUser(String query) async {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('ChatStateManager: Cannot find user - WebSocket not connected');
      return null;
    }

    try {
      _chatWebSocketService.findUser(query);
      // The user will be received via onUserFound callback
      return null; // Return null for now, actual user comes via callback
    } catch (e) {
      debugPrint('ChatStateManager: Failed to find user: $e');
      return null;
    }
  }

  /// Mark messages as seen
  Future<void> markMessagesAsSeen(String chatId, List<String> messageIds) async {
    if (!_chatWebSocketService.isConnected) return;

    try {
      _chatWebSocketService.markMessagesSeen(messageIds);
      
      // Update local state
      final messages = _chatMessages[chatId];
      if (messages != null) {
        for (int i = 0; i < messages.length; i++) {
          if (messageIds.contains(messages[i].id)) {
            messages[i] = messages[i].copyWith(status: MessageStatus.read);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ChatStateManager: Failed to mark messages as seen: $e');
    }
  }

  /// Refresh chats by reloading from WebSocket
  Future<void> refreshChats() async {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('ChatStateManager: Cannot refresh chats - WebSocket not connected');
      _setError('Not connected to chat service');
      return;
    }

    try {
      debugPrint('ChatStateManager: Refreshing chats...');
      _setLoading(true);
      clearError(); // Clear any existing errors
      
      // Trigger WebSocket to load active chats
      // The loading state will be set to false in onChatSummariesReceived
      _chatWebSocketService.loadActiveChats();
      
      // Wait for the WebSocket response or timeout
      int attempts = 0;
      const maxAttempts = 50; // 5 seconds (50 * 100ms)
      
      while (_isLoading && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      
      // If still loading after timeout, force stop
      if (_isLoading) {
        debugPrint('ChatStateManager: Refresh timeout, clearing loading state');
        _setLoading(false);
        if (_errorMessage == null) {
          _setError('Request timed out. Please try again.');
        }
      }
      
    } catch (e) {
      debugPrint('ChatStateManager: Failed to refresh chats: $e');
      _setError('Failed to refresh chats: $e');
    }
  }

  /// Clear all state (used on logout)
  void clear() {
    _chats.clear();
    _chatMessages.clear();
    _users.clear();
    _isInitialized = false;
    _currentUserId = null;
    notifyListeners();
    debugPrint('ChatStateManager: State cleared');
  }

  // Private helper methods
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      if (loading) {
        _errorMessage = null; // Clear error when starting to load
      }
      notifyListeners();
    }
  }

  void _setError(String error) {
    _errorMessage = error;
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _addMessageToChat(String chatId, Message message) {
    _chatMessages.putIfAbsent(chatId, () => []);
    _chatMessages[chatId]!.add(message);
    
    // Update chat's last message and activity
    if (_chats.containsKey(chatId)) {
      final chat = _chats[chatId]!;
      
      // Debug logging to understand chat state during updates
      debugPrint('ChatStateManager: Updating chat $chatId during message add');
      debugPrint('  - Chat name: "${chat.name}"');
      debugPrint('  - Participants count: ${chat.participants.length}');
      debugPrint('  - Current user ID: $_currentUserId');
      
      // Ensure chat name is preserved if it becomes empty
      final updatedChat = chat.copyWith(
        lastMessage: message,
        lastActivity: message.timestamp,
      );
      
      // Additional safety check: if chat name becomes "Chat" but we had proper data before,
      // this might indicate a data loss issue
      if (updatedChat.name == 'Chat' && chat.participants.isNotEmpty) {
        debugPrint('ChatStateManager: Warning - chat name reverted to "Chat" despite having participants');
        debugPrint('  - Original chat name: "${chat.name}"');
        debugPrint('  - Participants: ${chat.participants.map((u) => '${u.id}:${u.username}').join(', ')}');
      }
      
      _chats[chatId] = updatedChat;
    } else {
      debugPrint('ChatStateManager: Chat $chatId not found in _chats during message add');
    }
    
    notifyListeners();
  }

  void _updateMessageInChat(String chatId, Message updatedMessage) {
    final messages = _chatMessages[chatId];
    if (messages != null) {
      final index = messages.indexWhere((m) => m.id == updatedMessage.id);
      if (index != -1) {
        messages[index] = updatedMessage;
        
        // Update chat's last message if this is the latest message
        if (_chats.containsKey(chatId)) {
          final chat = _chats[chatId]!;
          if (chat.lastMessage?.id == updatedMessage.id) {
            _chats[chatId] = chat.copyWith(lastMessage: updatedMessage);
          }
        }
        
        notifyListeners();
      }
    }
  }

  MessageType _parseMessageType(String type) {
    switch (type.toLowerCase()) {
      case 'image': return MessageType.image;
      case 'video': return MessageType.video;
      case 'audio': return MessageType.audio;
      case 'file': return MessageType.file;
      default: return MessageType.text;
    }
  }

  // ChatEventListener implementations
  @override
  void onConnectionEstablished() {
    debugPrint('ChatStateManager: WebSocket connection established');
    if (_currentUserId != null && !_isInitialized) {
      initialize(_currentUserId!);
    } else if (_currentUserId != null && _chats.isEmpty) {
      // If we're already initialized but have no chats, refresh them
      debugPrint('ChatStateManager: Connection established, refreshing chats');
      refreshChats();
    }
    notifyListeners();
  }

  @override
  void onReconnectAttempt(int attemptCount) {
    debugPrint('ChatStateManager: WebSocket reconnect attempt: $attemptCount');
  }

  @override
  void onConnectionClosed() {
    debugPrint('ChatStateManager: WebSocket connection closed');
    notifyListeners();
  }

  @override
  void onConnectionFailed(String error) {
    debugPrint('ChatStateManager: WebSocket connection failed: $error');
    notifyListeners();
  }

  @override
  void onConnectionClosing() {
    debugPrint('ChatStateManager: WebSocket connection closing');
  }

  @override
  void onUserFound(User user) {
    debugPrint('ChatStateManager: User found: ${user.username}');
    _users[user.id.toString()] = user;
    notifyListeners();
  }

  @override
  void onGetOrCreateChat(Chat chat) {
    debugPrint('ChatStateManager: Got/created chat: ${chat.name}');
    debugPrint('ChatStateManager: Chat participants: ${chat.participants.length}');
    debugPrint('ChatStateManager: Chat participant IDs: ${chat.participantIds}');
    for (final participant in chat.participants) {
      debugPrint('ChatStateManager: Participant: ${participant.id} - ${participant.username}');
    }
    
    _chats[chat.id] = chat;
    
    // Complete any pending chat creation requests
    final List<int> completedRequestUserIds = [];
    for (final entry in _chatCreationCompleters.entries) {
      final userId = entry.key;
      final completer = entry.value;
      
      // Check if this chat is for the requested user
      if (chat.participantIds.contains(userId.toString())) {
        if (!completer.isCompleted) {
          completer.complete(chat);
        }
        completedRequestUserIds.add(userId);
      }
    }
    
    // Remove completed requestst
    for (final userId in completedRequestUserIds) {
      _chatCreationCompleters.remove(userId);
    }
    
    notifyListeners();
  }

  @override
  void onMessagesReceived(List<Message> messages) {
    debugPrint('ChatStateManager: Received ${messages.length} messages');
    
    for (final message in messages) {
      _chatMessages.putIfAbsent(message.chatId, () => []);
      
      // Check if message already exists to avoid duplicates
      final existingIndex = _chatMessages[message.chatId]!
          .indexWhere((m) => m.id == message.id);
      
      if (existingIndex == -1) {
        _chatMessages[message.chatId]!.add(message);
      } else {
        _chatMessages[message.chatId]![existingIndex] = message;
      }
    }
    
    // Sort messages by timestamp
    for (final chatId in _chatMessages.keys) {
      _chatMessages[chatId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    
    notifyListeners();
  }

  @override
  void onNewMessage(Message message) {
    debugPrint('ChatStateManager: New message received: ${message.content}');
    
    // Check if this might be a duplicate of an optimistic message we already added
    final messages = _chatMessages[message.chatId];
    if (messages != null) {
      // Look for a message with the same content and sender that was sent recently
      // This handles the case where we added an optimistic message and now received the server confirmation
      final recentTimeThreshold = DateTime.now().subtract(const Duration(minutes: 5));
      
      final duplicateIndex = messages.indexWhere((existingMessage) =>
        existingMessage.senderId == message.senderId &&
        existingMessage.content == message.content &&
        existingMessage.timestamp.isAfter(recentTimeThreshold) &&
        (existingMessage.status == MessageStatus.sending || existingMessage.status == MessageStatus.sent)
      );
      
      if (duplicateIndex != -1) {
        // Replace the optimistic message with the server version
        debugPrint('ChatStateManager: Replacing optimistic message with server version');
        messages[duplicateIndex] = message;
        
        // Update chat's last message if this was the most recent
        if (duplicateIndex == messages.length - 1) {
          if (_chats.containsKey(message.chatId)) {
            final chat = _chats[message.chatId]!;
            _chats[message.chatId] = chat.copyWith(
              lastMessage: message,
              lastActivity: message.timestamp,
            );
          }
        }
        
        notifyListeners();
        return;
      }
    }
    
    // No duplicate found, add as new message
    debugPrint('ChatStateManager: Adding new message (not a duplicate)');
    _addMessageToChat(message.chatId, message);
  }

  @override
  void onMessageUpdated(Message message) {
    debugPrint('ChatStateManager: Message updated: ${message.id}');
    _updateMessageInChat(message.chatId, message);
  }

  @override
  void onMessageDeleted(String chatId, String messageId) {
    debugPrint('ChatStateManager: Message deleted: $messageId from chat: $chatId');
    
    final messages = _chatMessages[chatId];
    if (messages != null) {
      messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
  }

  @override
  void onMessagesSeen(List<String> messageIds) {
    debugPrint('ChatStateManager: Messages seen: ${messageIds.join(', ')}');
    
    // Update all matching messages to seen status
    for (final chatId in _chatMessages.keys) {
      final messages = _chatMessages[chatId]!;
      bool updated = false;
      
      for (int i = 0; i < messages.length; i++) {
        if (messageIds.contains(messages[i].id)) {
          messages[i] = messages[i].copyWith(status: MessageStatus.read);
          updated = true;
        }
      }
      
      if (updated) {
        notifyListeners();
      }
    }
  }

  @override
  void onMessagesDelivered(List<String> messageIds) {
    debugPrint('ChatStateManager: Messages delivered: ${messageIds.join(', ')}');
    
    // Update all matching messages to delivered status
    for (final chatId in _chatMessages.keys) {
      final messages = _chatMessages[chatId]!;
      bool updated = false;
      
      for (int i = 0; i < messages.length; i++) {
        if (messageIds.contains(messages[i].id) && 
            messages[i].status == MessageStatus.sent) {
          messages[i] = messages[i].copyWith(status: MessageStatus.delivered);
          updated = true;
        }
      }
      
      if (updated) {
        notifyListeners();
      }
    }
  }

  @override
  void onSummaryUpdated(Chat summary) {
    debugPrint('ChatStateManager: Chat summary updated: ${summary.name}');
    debugPrint('  - Summary participants: ${summary.participants.length}');
    debugPrint('  - Summary participantIds: ${summary.participantIds}');
    
    final existingChat = _chats[summary.id];
    if (existingChat != null) {
      debugPrint('  - Existing chat participants: ${existingChat.participants.length}');
      debugPrint('  - Existing chat name: "${existingChat.name}"');
      
      // Preserve participant data if the summary doesn't have it but existing chat does
      if (summary.participants.isEmpty && existingChat.participants.isNotEmpty) {
        debugPrint('  - Preserving existing participant data');
        final preservedChat = summary.copyWith(
          participants: existingChat.participants,
          participantIds: existingChat.participantIds,
          // Also preserve the proper name if summary reverted to "Chat"
          name: summary.name == 'Chat' && existingChat.name != 'Chat' 
              ? existingChat.name 
              : summary.name,
        );
        _chats[summary.id] = preservedChat;
        debugPrint('  - Preserved chat: participants=${preservedChat.participants.length}, name="${preservedChat.name}"');
      } else {
        _chats[summary.id] = summary;
      }
    } else {
      _chats[summary.id] = summary;
    }
    
    notifyListeners();
  }

  @override
  void onChatSummariesReceived(List<Chat> summaries) {
    debugPrint('ChatStateManager: Received ${summaries.length} chat summaries');
    
    for (final chat in summaries) {
      debugPrint('ChatStateManager: Processing chat ${chat.id} - "${chat.name}"');
      debugPrint('  - Participants: ${chat.participants.length}');
      debugPrint('  - ParticipantIds: ${chat.participantIds}');
      _chats[chat.id] = chat;
    }
    
    _setLoading(false);
    notifyListeners();
  }

  @override
  void onAllChatSummariesReceived(List<Chat> summaries) {
    debugPrint('ChatStateManager: Received ${summaries.length} all chat summaries');
    
    // Clear existing chats and replace with new summaries
    _chats.clear();
    for (final chat in summaries) {
      _chats[chat.id] = chat;
    }
    
    _setLoading(false);
    notifyListeners();
  }

  @override
  void onError(String error) {
    debugPrint('ChatStateManager: WebSocket error: $error');
    _setError(error);
  }

  /// Dispose the state manager
  @override
  void dispose() {
    _chatWebSocketService.removeListener(this);
    super.dispose();
  }
}