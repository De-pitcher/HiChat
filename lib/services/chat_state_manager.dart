import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/user_presence.dart';
import '../models/reply_message.dart';
import 'chat_websocket_service.dart';
import 'native_camera_service.dart';
import 'enhanced_file_upload_service.dart';
import 'local_media_cache_service.dart';

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
  final Map<String, UserPresence> _userPresence = {};
  
  // Chat creation tracking
  final Map<int, Completer<Chat?>> _chatCreationCompleters = {};
  
  // Reply state management
  final Map<String, Message> _replyContext = {}; // chatId -> message being replied to
  
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
  
  // Presence getters
  Map<String, UserPresence> get userPresence => Map.unmodifiable(_userPresence);
  UserPresence? getUserPresence(String userId) => _userPresence[userId];
  bool isUserOnline(String userId) => _userPresence[userId]?.isOnline ?? false;
  String getUserStatus(String userId) => _userPresence[userId]?.displayStatus ?? 'Unknown';
  List<UserPresence> get onlineUsers => _userPresence.values.where((user) => user.isOnline).toList();
  List<UserPresence> get offlineUsers => _userPresence.values.where((user) => !user.isOnline).toList();
  
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
    if (_isInitialized && _currentUserId == userId) {
      debugPrint('ChatStateManager: Already initialized for user $userId');
      return;
    }
    
    _currentUserId = userId;
    _setLoading(true);
    
    try {
      debugPrint('ChatStateManager: Initializing for user: $userId');
      debugPrint('ChatStateManager: WebSocket connected: ${_chatWebSocketService.isConnected}');
      
      // Ensure we're registered as a WebSocket listener (in case it was cleared during logout)
      _chatWebSocketService.addListener(this);
      debugPrint('ChatStateManager: Re-added WebSocket event listener');
      
      // Clear previous state
      _chats.clear();
      _chatMessages.clear();
      
      // Set as initialized - chat loading will happen via onConnectionEstablished()
      _isInitialized = true;
      
      // If WebSocket is already connected, trigger chat loading immediately
      if (_chatWebSocketService.isConnected) {
        debugPrint('ChatStateManager: WebSocket already connected, loading chats immediately');
        _chatWebSocketService.loadActiveChats();
      } else {
        debugPrint('ChatStateManager: WebSocket not connected yet, chats will load when connection established');
        // Set a timeout to stop loading state if connection takes too long
        Timer(const Duration(seconds: 10), () {
          if (_isLoading && !_chatWebSocketService.isConnected) {
            debugPrint('ChatStateManager: WebSocket connection timeout, stopping loading state');
            _setLoading(false);
          }
        });
      }
      
      debugPrint('ChatStateManager: Initialization complete for user $userId');
    } catch (e) {
      debugPrint('ChatStateManager: Initialization failed: $e');
      _setError('Failed to initialize chat service: $e');
      _setLoading(false);
    }
    // Note: Don't always set loading to false here - let onConnectionEstablished or timeout handle it
  }

  /// Get messages for a specific chat
  List<Message> getMessagesForChat(String chatId) {
    // Return a new list instance to ensure UI detects changes
    final messages = _chatMessages[chatId] ?? [];
    return List<Message>.from(messages);
  }

  /// Get a specific chat by ID
  Chat? getChat(String chatId) {
    return _chats[chatId];
  }

  /// Get a specific message by ID from a chat
  Message? getMessageById(String chatId, String messageId) {
    final messages = _chatMessages[chatId];
    if (messages == null) return null;
    
    try {
      return messages.firstWhere((message) => message.id == messageId);
    } catch (e) {
      return null;
    }
  }

  // ============================================================================
  // REPLY FUNCTIONALITY
  // ============================================================================

  /// Set the message being replied to for a specific chat
  void setReplyContext(String chatId, Message message) {
    _replyContext[chatId] = message;
    debugPrint('💬 ChatStateManager: Set reply context for chat $chatId to message ${message.id}');
    notifyListeners();
  }

  /// Get the message being replied to for a specific chat
  Message? getReplyContext(String chatId) {
    return _replyContext[chatId];
  }

  /// Clear the reply context for a specific chat
  void clearReplyContext(String chatId) {
    if (_replyContext.containsKey(chatId)) {
      _replyContext.remove(chatId);
      debugPrint('💬 ChatStateManager: Cleared reply context for chat $chatId');
      notifyListeners();
    }
  }

  /// Check if a chat has an active reply context
  bool hasReplyContext(String chatId) {
    return _replyContext.containsKey(chatId);
  }

  /// Clear all reply contexts (used on logout)
  void clearAllReplyContexts() {
    _replyContext.clear();
    notifyListeners();
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
    String? replyToMessageId,
  }) async {
    debugPrint('🚀 ChatStateManager: sendMessage called - chatId: $chatId, content: $content, type: $type, replyTo: $replyToMessageId');
    debugPrint('🚀 ChatStateManager: WebSocket connected: ${_chatWebSocketService.isConnected}');
    
    // Note: Removed connection check to allow queuing when disconnected

    try {
      // Get reply context if replying
      ReplyMessage? replyToMessage;
      if (replyToMessageId != null) {
        final replyMessage = getMessageById(chatId, replyToMessageId);
        if (replyMessage != null) {
          replyToMessage = ReplyMessage.fromMessage({
            'id': replyMessage.id,
            'content': replyMessage.content,
            'message_type': replyMessage.type.name,
            'file_url': replyMessage.fileUrl,
            'sender_id': replyMessage.senderId,
            'sender_username': replyMessage.senderUsername ?? 'Unknown',
            'sender_email': replyMessage.senderEmail ?? '',
          });
        }
      }

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
        replyToMessageId: replyToMessageId,
        replyToMessage: replyToMessage,
        metadata: fileUrl != null ? {'file_url': fileUrl} : null,
      );
      
      debugPrint('ChatStateManager: Created optimistic message with ID: $tempId, replyTo: $replyToMessageId');

      // Add optimistic message to local state
      _addMessageToChat(chatId, message);

      // Send via WebSocket with temp ID for queue tracking
      _chatWebSocketService.sendMessage(
        chatId: chatId,
        receiverId: receiverId ?? 0,
        content: content,
        type: type,
        fileUrl: fileUrl,
        messageId: tempId, // Pass temp ID for enhanced queuing
        replyToMessageId: replyToMessageId, // Pass reply context
      );

      // Update message status based on connection state
      if (_chatWebSocketService.isConnected) {
        // Update message status to sent (optimistic)
        final updatedMessage = message.copyWith(status: MessageStatus.sent);
        _updateMessageInChat(chatId, updatedMessage);
      } else {
        // Message is queued, status will be updated by WebSocket service
        debugPrint('ChatStateManager: Message queued due to disconnection');
      }

      // Clear reply context after sending
      clearReplyContext(chatId);
      
    } catch (e) {
      debugPrint('ChatStateManager: Failed to send message: $e');
      rethrow;
    }
  }

  /// Send audio message
  Future<void> sendAudioMessage({
    required String chatId,
    required String audioFilePath,
    required Duration duration,
    int? receiverId,
    Function(double)? onUploadProgress,
  }) async {
    debugPrint('ChatStateManager: Starting audio message send for chat: $chatId');
    debugPrint('ChatStateManager: WebSocket connected: ${_chatWebSocketService.isConnected}');
    
    try {
      // Create file from path
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found: $audioFilePath');
      }

      final fileSize = await audioFile.length();
      
      // Create optimistic message with sending status
      final tempId = 'audio_${_currentUserId ?? 'unknown'}_${DateTime.now().millisecondsSinceEpoch}';
      final optimisticMessage = Message(
        id: tempId,
        chatId: chatId,
        senderId: _currentUserId ?? '',
        content: 'Sending audio...',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.audio,
        metadata: {
          'is_uploading': true,
          'upload_progress': 0.0,
          'duration': duration.inMilliseconds,
          'file_size': fileSize,
          'local_path': audioFilePath,
        },
      );

      // Add to messages immediately for UI feedback
      _addMessageToChat(chatId, optimisticMessage);

      // Read audio file data
      final audioData = await audioFile.readAsBytes();
      
      // Create NativeCameraResult structure for audio
      final audioResult = NativeCameraResult(
        file: audioFile,
        data: audioData,
        type: NativeMediaType.audio,
        size: fileSize,
        path: audioFilePath,
        name: 'audio_${DateTime.now().millisecondsSinceEpoch}.aac',
        captureTime: DateTime.now(),
        mimeType: 'audio/aac',
      );

      // Upload the audio file
      final uploadResult = await EnhancedFileUploadService.uploadMediaWithCaching(
        audioResult,
        chatId,
        onProgress: (progress) {
          // Update message with upload progress
          final updatedMessage = optimisticMessage.copyWith(
            metadata: {
              ...optimisticMessage.metadata!,
              'upload_progress': progress,
            },
          );
          _updateMessageInChat(chatId, updatedMessage);
          onUploadProgress?.call(progress);
        },
      );

      // Create final message with uploaded URL
      final uploadCompleteMessage = optimisticMessage.copyWith(
        content: uploadResult.fileUrl,
        status: MessageStatus.sent,
        metadata: {
          ...optimisticMessage.metadata!,
          'is_uploading': false,
          'upload_progress': 1.0,
          'url': uploadResult.fileUrl,
          'timestamp': uploadResult.timestamp,
        },
      );

      // Send via WebSocket (will queue automatically if disconnected)
      _chatWebSocketService.sendMessage(
        chatId: chatId,
        receiverId: receiverId ?? 0,
        content: uploadResult.fileUrl,
        type: 'audio',
        fileUrl: uploadResult.fileUrl,
        messageId: tempId, // Pass the temp ID for queue tracking
      );

      if (!_chatWebSocketService.isConnected) {
        // Message is queued, show failed status with error icon
        final queuedMessage = uploadCompleteMessage.copyWith(status: MessageStatus.failed);
        _updateMessageInChat(chatId, queuedMessage);
        debugPrint('ChatStateManager: Audio message queued due to disconnection');
      } else {
        // Update local state with success
        _updateMessageInChat(chatId, uploadCompleteMessage);
      }
      
      debugPrint('ChatStateManager: Audio message sent successfully');
      
    } catch (e) {
      debugPrint('ChatStateManager: Failed to send audio message: $e');
      
      // Mark message as failed
      final failedMessage = Message(
        id: 'audio_${_currentUserId ?? 'unknown'}_${DateTime.now().millisecondsSinceEpoch}',
        chatId: chatId,
        senderId: _currentUserId ?? '',
        content: 'Failed to send audio',
        timestamp: DateTime.now(),
        status: MessageStatus.failed,
        type: MessageType.audio,
        metadata: {
          'is_uploading': false,
          'duration': duration.inMilliseconds,
          'local_path': audioFilePath,
          'error': e.toString(),
        },
      );
      
      _updateMessageInChat(chatId, failedMessage);
      rethrow;
    }
  }

  /// Send multimedia message (image, video, audio)
  Future<void> sendMultimediaMessage({
    required String chatId,
    required NativeCameraResult mediaResult,
    int? receiverId,
    Function(double)? onUploadProgress,
  }) async {
    debugPrint('ChatStateManager: Starting multimedia message send for chat: $chatId');
    debugPrint('ChatStateManager: WebSocket connected: ${_chatWebSocketService.isConnected}');
    
    // Note: Removed connection check to allow queuing when disconnected

    try {
      
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
        messageId: tempId, // Pass the temp ID for queue tracking
      );

      // Update message status based on connection state
      if (_chatWebSocketService.isConnected) {
        // Update message status to sent (optimistic)
        final sentMessage = uploadCompleteMessage.copyWith(status: MessageStatus.sent);
        _updateMessageInChat(chatId, sentMessage);
        debugPrint('ChatStateManager: Multimedia message sent successfully');
      } else {
        // Message is queued, show failed status with error icon
        final queuedMessage = uploadCompleteMessage.copyWith(status: MessageStatus.failed);
        _updateMessageInChat(chatId, queuedMessage);
        debugPrint('ChatStateManager: Multimedia message queued due to disconnection');
      }

    } catch (e) {
      debugPrint('ChatStateManager: Failed to send multimedia message: $e');
      
      // Update message with failed status but keep timestamp as content for local caching
      if (_chatMessages.containsKey(chatId)) {
        final messages = _chatMessages[chatId]!;
        final messageIndex = messages.indexWhere((m) => m.id.startsWith('multimedia_${_currentUserId ?? 'unknown'}'));
        
        if (messageIndex != -1) {
          // Try to get timestamp from the cached media if upload was partial
          String contentForFailedMessage = 'Failed to send ${mediaResult.type.name}';
          
          // Check if we have a timestamp from partial upload
          final currentMetadata = messages[messageIndex].metadata ?? {};
          if (currentMetadata.containsKey('timestamp')) {
            contentForFailedMessage = currentMetadata['timestamp'].toString();
          }
          
          final failedMessage = messages[messageIndex].copyWith(
            status: MessageStatus.failed,
            content: contentForFailedMessage,
            metadata: {
              ...currentMetadata,
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

  /// Retry a failed message (text or multimedia)
  Future<void> retryFailedMessage(Message message) async {
    debugPrint('🔄 ChatStateManager: Retrying failed message - ID: ${message.id}, Type: ${message.type}');
    
    if (message.status != MessageStatus.failed) {
      throw Exception('Cannot retry message that is not in failed status');
    }

    // Update message status to sending
    final retryingMessage = message.copyWith(
      status: MessageStatus.sending,
      metadata: {
        ...message.metadata ?? {},
        'is_retrying': true,
        'retry_count': (message.metadata?['retry_count'] ?? 0) + 1,
      },
    );
    _updateMessageInChat(message.chatId, retryingMessage);

    try {
      if (message.type == MessageType.text) {
        // Retry text message
        await sendMessage(
          chatId: message.chatId,
          content: message.content,
          type: message.type.name,
          receiverId: message.metadata?['receiver_id'],
        );
      } else {
        // For multimedia messages, check if we have cached media
        final timestamp = message.content;
        final cachedFile = await _getCachedMediaFile(timestamp, message.type);
        
        if (cachedFile != null) {
          // Create NativeCameraResult from cached file
          final mediaResult = await _createMediaResultFromCache(cachedFile, message.type);
          
          // Retry multimedia message
          await sendMultimediaMessage(
            chatId: message.chatId,
            mediaResult: mediaResult,
            receiverId: message.metadata?['receiver_id'],
            onUploadProgress: (progress) {
              // Update progress in message metadata
              final progressMessage = retryingMessage.copyWith(
                metadata: {
                  ...retryingMessage.metadata ?? {},
                  'upload_progress': progress,
                },
              );
              _updateMessageInChat(message.chatId, progressMessage);
            },
          );
        } else {
          throw Exception('Cached media file not found for retry');
        }
      }
      
      debugPrint('🔄 ChatStateManager: Message retry successful');
      
    } catch (e) {
      debugPrint('🔄 ChatStateManager: Message retry failed: $e');
      
      // Revert to failed status
      final failedMessage = message.copyWith(
        status: MessageStatus.failed,
        metadata: {
          ...message.metadata ?? {},
          'retry_error': e.toString(),
          'last_retry_at': DateTime.now().toIso8601String(),
        },
      );
      _updateMessageInChat(message.chatId, failedMessage);
      
      rethrow;
    }
  }

  /// Get cached media file for retry
  Future<File?> _getCachedMediaFile(String timestamp, MessageType type) async {
    try {
      final cacheService = LocalMediaCacheService();
      await cacheService.initialize();
      
      final metadata = cacheService.getMediaMetadata(timestamp);
      if (metadata != null && File(metadata.localPath).existsSync()) {
        return File(metadata.localPath);
      }
      
      return null;
    } catch (e) {
      debugPrint('ChatStateManager: Error getting cached media file: $e');
      return null;
    }
  }

  /// Create NativeCameraResult from cached file
  Future<NativeCameraResult> _createMediaResultFromCache(File cachedFile, MessageType type) async {
    final fileBytes = await cachedFile.readAsBytes();
    final nativeType = type == MessageType.video ? NativeMediaType.video : NativeMediaType.image;
    
    return NativeCameraResult(
      file: cachedFile,
      data: fileBytes,
      type: nativeType,
      size: fileBytes.length,
      path: cachedFile.path,
      name: cachedFile.path.split('/').last,
      captureTime: DateTime.now(),
      mimeType: type == MessageType.video ? 'video/mp4' : 'image/jpeg',
    );
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
    debugPrint('ChatStateManager: Refreshing chats...');
    _setLoading(true);
    clearError(); // Clear any existing errors
    
    if (!_chatWebSocketService.isConnected) {
      debugPrint('ChatStateManager: WebSocket not connected, attempting to reconnect...');
      
      bool reconnected = await reconnectWebSocket();
      if (!reconnected) {
        debugPrint('ChatStateManager: Failed to reconnect WebSocket');
        _setError('Failed to reconnect to chat service');
        _setLoading(false);
        return;
      }
    }

    try {
      debugPrint('ChatStateManager: WebSocket connected, requesting chat refresh...');
      
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

  /// Manually trigger WebSocket reconnection
  Future<bool> reconnectWebSocket() async {
    if (_chatWebSocketService.isConnected) {
      debugPrint('ChatStateManager: WebSocket already connected');
      return true;
    }

    if (_currentUserId == null) {
      debugPrint('ChatStateManager: No user ID available for reconnection');
      return false;
    }

    try {
      debugPrint('ChatStateManager: Attempting WebSocket reconnection for user: $_currentUserId');
      
      // Ensure we're registered as a listener before attempting reconnection
      _chatWebSocketService.addListener(this);
      debugPrint('ChatStateManager: Re-registered as WebSocket listener');
      
      // Use the stored credentials from the WebSocket service for reconnection
      final success = await _chatWebSocketService.reconnectWithStoredCredentials();
      
      if (!success) {
        debugPrint('ChatStateManager: Initial reconnection attempt failed, trying with explicit userid');
        // Fallback: try with just the userId if available
        if (_currentUserId != null) {
          await _chatWebSocketService.connectWebSocket(userId: int.tryParse(_currentUserId!));
        } else {
          debugPrint('ChatStateManager: No userId available for fallback reconnection');
          return false;
        }
      }
      
      // Ensure we're still registered as a listener after reconnection
      _chatWebSocketService.addListener(this);
      debugPrint('ChatStateManager: Re-registered as WebSocket listener after reconnection');
      
      // Wait for connection to establish (up to 10 seconds)
      int attempts = 0;
      const maxConnectionAttempts = 100; // 10 seconds (100 * 100ms)
      
      while (!_chatWebSocketService.isConnected && attempts < maxConnectionAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      
      if (_chatWebSocketService.isConnected) {
        debugPrint('ChatStateManager: WebSocket reconnection successful');
        clearError();
        return true;
      } else {
        debugPrint('ChatStateManager: WebSocket reconnection failed within timeout');
        return false;
      }
    } catch (e) {
      debugPrint('ChatStateManager: WebSocket reconnection error: $e');
      return false;
    }
  }

  /// Force refresh with connection retry - useful for pull-to-refresh
  Future<void> forceRefreshWithReconnect() async {
    debugPrint('ChatStateManager: Force refresh with reconnection...');
    
    // Always try to reconnect first, even if we think we're connected
    if (_currentUserId != null) {
      debugPrint('ChatStateManager: Ensuring WebSocket connection...');
      
      // Close existing connection if any and reconnect fresh
      if (_chatWebSocketService.isConnected) {
        debugPrint('ChatStateManager: Closing existing connection for fresh reconnect...');
        _chatWebSocketService.closeWebSocket();
        
        // Wait a bit for clean disconnect
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      bool connected = await reconnectWebSocket();
      if (!connected) {
        debugPrint('ChatStateManager: Failed to establish fresh connection');
        _setError('Unable to connect to chat service');
        return;
      }
    }
    
    // Now refresh chats
    await refreshChats();
  }

  /// Clear all state (used on logout)
  void clear() {
    _chats.clear();
    _chatMessages.clear();
    _users.clear();
    _replyContext.clear();
    _isInitialized = false;
    _currentUserId = null;
    _setLoading(false); // Ensure loading state is cleared
    _errorMessage = null; // Clear any error state
    debugPrint('ChatStateManager: State cleared - loading: $_isLoading, error: $_errorMessage');
    notifyListeners();
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
    debugPrint('🔄 ChatStateManager: Added message ${message.id} to chat $chatId. Total messages: ${_chatMessages[chatId]!.length}');
    
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
        final oldContent = messages[index].content;
        messages[index] = updatedMessage;
        debugPrint('🔄 ChatStateManager: Updated message ${updatedMessage.id} content: "$oldContent" → "${updatedMessage.content}"');
        
        // Update chat's last message if this is the latest message
        if (_chats.containsKey(chatId)) {
          final chat = _chats[chatId]!;
          if (chat.lastMessage?.id == updatedMessage.id) {
            _chats[chatId] = chat.copyWith(lastMessage: updatedMessage);
            debugPrint('🔄 ChatStateManager: Updated last message for chat $chatId');
          }
        }
        
        debugPrint('🔄 ChatStateManager: Notifying listeners for message update');
        notifyListeners();
      } else {
        debugPrint('⚠️ ChatStateManager: Message ${updatedMessage.id} not found in chat $chatId for update');
      }
    } else {
      debugPrint('⚠️ ChatStateManager: Chat $chatId not found for message update');
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
    debugPrint('ChatStateManager: Current state - userId: $_currentUserId, initialized: $_isInitialized, chats: ${_chats.length}');
    
    if (_currentUserId != null && !_isInitialized) {
      // User ID exists but not initialized yet - call initialize
      debugPrint('ChatStateManager: User not initialized, calling initialize()');
      initialize(_currentUserId!);
    } else if (_currentUserId != null && _isInitialized) {
      // User is initialized and WebSocket just connected - load chats
      debugPrint('ChatStateManager: Connection established for initialized user, loading chats...');
      try {
        _setLoading(true);
        _chatWebSocketService.loadActiveChats();
        debugPrint('ChatStateManager: Called loadActiveChats() after connection established');
      } catch (e) {
        debugPrint('ChatStateManager: Error calling loadActiveChats(): $e');
        _setError('Failed to load chats: $e');
      }
    } else {
      debugPrint('ChatStateManager: No current user ID, skipping chat loading');
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
    debugPrint('📝 ChatStateManager: Message updated received - ID: ${message.id}, Content: "${message.content}"');
    _updateMessageInChat(message.chatId, message);
  }

  @override
  void onMessageDeleted(String chatId, String messageId) {
    debugPrint('ChatStateManager: Message deleted: $messageId from chat: $chatId');
    
    final messages = _chatMessages[chatId];
    if (messages != null) {
      final beforeCount = messages.length;
      messages.removeWhere((m) => m.id == messageId);
      final afterCount = messages.length;
      debugPrint('🔄 ChatStateManager: Removed message $messageId from chat $chatId. Messages: $beforeCount → $afterCount');
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
    debugPrint('ChatStateManager: onChatSummariesReceived called with ${summaries.length} chat summaries');
    
    try {
      for (final chat in summaries) {
        debugPrint('ChatStateManager: Processing chat ${chat.id} - "${chat.name}"');
        debugPrint('  - Participants: ${chat.participants.length}');
        debugPrint('  - ParticipantIds: ${chat.participantIds}');
        _chats[chat.id] = chat;
      }
      
      debugPrint('ChatStateManager: Setting loading to false and notifying listeners');
      _setLoading(false);
      notifyListeners();
      debugPrint('ChatStateManager: onChatSummariesReceived completed successfully');
    } catch (e) {
      debugPrint('ChatStateManager: Error in onChatSummariesReceived: $e');
      _setLoading(false);
      _setError('Error processing chat data: $e');
    }
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

  @override
  void onPresenceUpdate(UserPresence presence) {
    debugPrint('👤 ChatStateManager: Presence update for ${presence.username} - ${presence.isOnline ? 'Online' : 'Offline'}');
    _userPresence[presence.userId] = presence;
    notifyListeners();
  }

  @override
  void onContactsPresence(List<UserPresence> contacts) {
    debugPrint('👥 ChatStateManager: Received presence for ${contacts.length} contacts');
    for (final contact in contacts) {
      _userPresence[contact.userId] = contact;
    }
    notifyListeners();
  }

  @override
  void onChatPresence(String chatId, List<UserPresence> members) {
    debugPrint('💬 ChatStateManager: Chat $chatId presence - ${members.length} members');
    for (final member in members) {
      _userPresence[member.userId] = member;
    }
    notifyListeners();
  }

  /// Edit a message
  Future<void> editMessage(String messageId, String newContent) async {
    if (!_chatWebSocketService.isConnected) {
      throw Exception('Not connected to chat service');
    }

    try {
      // Find the message to edit for optimistic update
      Message? messageToEdit;
      String? chatId;
      
      for (final entry in _chatMessages.entries) {
        final messages = entry.value.cast<Message>();
        for (final message in messages) {
          if (message.id == messageId) {
            messageToEdit = message;
            chatId = entry.key;
            break;
          }
        }
        if (messageToEdit != null) break;
      }
      
      // Perform optimistic update
      if (messageToEdit != null && chatId != null) {
        final optimisticMessage = messageToEdit.copyWith(
          content: newContent,
          status: MessageStatus.sending, // Show as sending
        );
        debugPrint('📝 ChatStateManager: Optimistic update for message $messageId: "${messageToEdit.content}" → "$newContent"');
        _updateMessageInChat(chatId, optimisticMessage);
      }
      
      _chatWebSocketService.updateMessage(messageId, newContent);
      debugPrint('📝 ChatStateManager: Edit message request sent for: $messageId');
    } catch (e) {
      debugPrint('❌ ChatStateManager: Failed to edit message: $e');
      throw Exception('Failed to edit message: $e');
    }
  }

  /// Delete a message
  Future<void> deleteMessage(String messageId) async {
    if (!_chatWebSocketService.isConnected) {
      throw Exception('Not connected to chat service');
    }

    try {
      _chatWebSocketService.deleteMessage(messageId);
      debugPrint('ChatStateManager: Delete message request sent for: $messageId');
    } catch (e) {
      debugPrint('ChatStateManager: Failed to delete message: $e');
      throw Exception('Failed to delete message: $e');
    }
  }

  /// Debug method to test queue functionality
  void debugTestMessageQueue() {
    debugPrint('🧪 ChatStateManager: Testing message queue functionality');
    // _chatWebSocketService.debugTestQueue();
  }

  /// Debug method to check WebSocket connection and manually trigger chat loading
  void debugConnectionAndLoadChats() {
    debugPrint('🔍 ChatStateManager Debug Info:');
    debugPrint('  - Current User ID: $_currentUserId');
    debugPrint('  - Is Initialized: $_isInitialized');
    debugPrint('  - Is Loading: $_isLoading');
    debugPrint('  - WebSocket Connected: ${_chatWebSocketService.isConnected}');
    debugPrint('  - Chats Count: ${_chats.length}');
    debugPrint('  - Error Message: $_errorMessage');
    
    if (_currentUserId != null && _chatWebSocketService.isConnected) {
      debugPrint('🔍 Manually triggering loadActiveChats()...');
      _chatWebSocketService.loadActiveChats();
    } else if (_currentUserId == null) {
      debugPrint('🔍 Cannot load chats: No user ID');
    } else if (!_chatWebSocketService.isConnected) {
      debugPrint('🔍 Cannot load chats: WebSocket not connected');
    }
  }

  // ============================================================================
  // PRESENCE METHODS
  // ============================================================================

  /// Request presence for all contacts
  void refreshContactsPresence() {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('⚠️ ChatStateManager: Cannot refresh contacts presence - not connected');
      return;
    }
    
    debugPrint('👥 ChatStateManager: Refreshing contacts presence');
    _chatWebSocketService.getContactsPresence();
  }

  /// Request presence for a specific user
  void refreshUserPresence(String userId) {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('⚠️ ChatStateManager: Cannot refresh user presence - not connected');
      return;
    }
    
    debugPrint('👤 ChatStateManager: Refreshing presence for user: $userId');
    _chatWebSocketService.getUserPresence(userId);
  }

  /// Request presence for chat members
  void refreshChatPresence(String chatId) {
    if (!_chatWebSocketService.isConnected) {
      debugPrint('⚠️ ChatStateManager: Cannot refresh chat presence - not connected');
      return;
    }
    
    debugPrint('💬 ChatStateManager: Refreshing presence for chat: $chatId');
    _chatWebSocketService.getChatPresence(chatId);
  }

  /// Get online count for specific users
  int getOnlineCountForUsers(List<String> userIds) {
    return userIds.where((id) => isUserOnline(id)).length;
  }

  /// Clear all presence data
  void clearPresenceData() {
    _userPresence.clear();
    notifyListeners();
  }

  /// Dispose the state manager
  @override
  void dispose() {
    _chatWebSocketService.removeListener(this);
    super.dispose();
  }
}