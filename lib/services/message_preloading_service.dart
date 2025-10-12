import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import 'chat_cache_service.dart';

/// Message preloading and pagination service for smooth chat experience
/// 
/// Features:
/// - Lazy loading of messages in chunks
/// - Intelligent preloading based on scroll position
/// - Seamless integration with cache and real-time updates
/// - Memory management and cleanup
/// - Progressive loading with placeholders
class MessagePreloadingService extends ChangeNotifier {
  final String chatId;
  final ChatCacheService _cacheService = ChatCacheService.instance;


  MessagePreloadingService({required this.chatId});

  // Configuration
  static const int messagesPerPage = 50;
  static const int preloadThreshold = 10; // Messages from top to trigger preload
  static const Duration loadingDelay = Duration(milliseconds: 300);
  static const int maxCachedMessages = 1000;

  // State
  final List<Message> _allMessages = [];
  final Set<int> _loadedPages = {};
  bool _isLoading = false;
  bool _hasMoreMessages = true;
  bool _isInitialized = false;
  int _currentPage = 0;
  Timer? _preloadTimer;

  // Getters
  List<Message> get messages => List.unmodifiable(_allMessages);
  bool get isLoading => _isLoading;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get isInitialized => _isInitialized;
  int get totalMessages => _allMessages.length;
  int get loadedPages => _loadedPages.length;

  /// Initialize the preloading service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('📚 MessagePreloadingService: Initializing for chat $chatId');
      
      // Load cached messages first for instant display
      await _loadCachedMessages();
      
      // Load initial page from network if needed
      if (_allMessages.isEmpty) {
        await loadInitialMessages();
      } else {
        // We have cached messages, try to load newer ones
        await _loadNewerMessages();
      }

      _isInitialized = true;
      debugPrint('✅ MessagePreloadingService: Initialized with ${_allMessages.length} messages');
    } catch (e) {
      debugPrint('❌ MessagePreloadingService: Initialization failed: $e');
      rethrow;
    }
  }

  /// Load cached messages from local storage
  Future<void> _loadCachedMessages() async {
    try {
      final cachedMessages = _cacheService.getCachedMessages(chatId);
      if (cachedMessages.isNotEmpty) {
        _allMessages.clear();
        _allMessages.addAll(cachedMessages);
        
        // Sort messages by timestamp
        _allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        // Update state
        _currentPage = (cachedMessages.length / messagesPerPage).ceil();
        _loadedPages.addAll(List.generate(_currentPage, (index) => index));

        debugPrint('📦 Loaded ${cachedMessages.length} cached messages');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error loading cached messages: $e');
    }
  }

  /// Load initial messages (first page)
  Future<void> loadInitialMessages() async {
    if (_isLoading) return;

    _setLoading(true);
    
    try {
      debugPrint('🔄 Loading initial messages for chat $chatId');
      
      // Simulate API call - replace with actual WebSocket/API call
      final messages = await _fetchMessagesFromServer(
        page: 0,
        limit: messagesPerPage,
      );

      if (messages.isEmpty) {
        _hasMoreMessages = false;
      } else {
        _allMessages.clear();
        _allMessages.addAll(messages);
        _allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        _currentPage = 1;
        _loadedPages.add(0);

        // Cache the messages
        await _cacheService.cacheMessages(chatId, _allMessages);
      }

      debugPrint('✅ Loaded ${messages.length} initial messages');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading initial messages: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Load newer messages (after the latest cached message)
  Future<void> _loadNewerMessages() async {
    if (_allMessages.isEmpty) return;

    try {
      debugPrint('🔄 Loading newer messages for chat $chatId');
      
      final latestMessage = _allMessages.last;
      final newerMessages = await _fetchNewerMessages(latestMessage.timestamp);

      if (newerMessages.isNotEmpty) {
        // Add newer messages
        for (final message in newerMessages) {
          if (!_allMessages.any((m) => m.id == message.id)) {
            _allMessages.add(message);
          }
        }
        
        _allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        // Update cache
        await _cacheService.cacheMessages(chatId, _allMessages);
        
        debugPrint('✅ Added ${newerMessages.length} newer messages');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error loading newer messages: $e');
    }
  }

  /// Load older messages (pagination)
  Future<void> loadOlderMessages() async {
    if (_isLoading || !_hasMoreMessages) return;

    _setLoading(true);

    try {
      debugPrint('🔄 Loading older messages (page $_currentPage) for chat $chatId');
      
      final olderMessages = await _fetchMessagesFromServer(
        page: _currentPage,
        limit: messagesPerPage,
        before: _allMessages.isNotEmpty ? _allMessages.first.timestamp : null,
      );

      if (olderMessages.isEmpty) {
        _hasMoreMessages = false;
        debugPrint('📭 No more older messages available');
      } else {
        // Add older messages to the beginning
        final newMessages = <Message>[];
        for (final message in olderMessages) {
          if (!_allMessages.any((m) => m.id == message.id)) {
            newMessages.add(message);
          }
        }

        _allMessages.insertAll(0, newMessages);
        _allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        _loadedPages.add(_currentPage);
        _currentPage++;

        // Manage memory by removing old messages if cache is too large
        await _manageMemory();

        // Update cache
        await _cacheService.cacheMessages(chatId, _allMessages);

        debugPrint('✅ Loaded ${newMessages.length} older messages');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading older messages: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Check if should preload more messages based on scroll position
  void checkPreloadTrigger(int firstVisibleIndex) {
    if (_isLoading || !_hasMoreMessages) return;

    // If user is near the top, preload older messages
    if (firstVisibleIndex <= preloadThreshold) {
      _preloadTimer?.cancel();
      _preloadTimer = Timer(loadingDelay, () {
        if (!_isLoading && _hasMoreMessages) {
          loadOlderMessages();
        }
      });
    }
  }

  /// Add a new message to the list
  Future<void> addMessage(Message message) async {
    try {
      // Check if message already exists
      final existingIndex = _allMessages.indexWhere((m) => m.id == message.id);
      
      if (existingIndex != -1) {
        // Update existing message
        _allMessages[existingIndex] = message;
      } else {
        // Add new message
        _allMessages.add(message);
        _allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      // Update cache
      await _cacheService.addMessageToCache(chatId, message);
      
      debugPrint('➕ Added message ${message.id} to preloading service');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error adding message: $e');
    }
  }

  /// Update message status
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    try {
      final messageIndex = _allMessages.indexWhere((m) => m.id == messageId);
      if (messageIndex != -1) {
        final updatedMessage = _allMessages[messageIndex].copyWith(status: status);
        _allMessages[messageIndex] = updatedMessage;
        
        // Update cache
        await _cacheService.updateMessageStatus(chatId, messageId, status);
        
        debugPrint('📝 Updated message $messageId status to ${status.name}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error updating message status: $e');
    }
  }

  /// Remove a message
  Future<void> removeMessage(String messageId) async {
    try {
      _allMessages.removeWhere((m) => m.id == messageId);
      
      // Update cache
      await _cacheService.cacheMessages(chatId, _allMessages);
      
      debugPrint('🗑️ Removed message $messageId');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error removing message: $e');
    }
  }

  /// Refresh messages (reload from server)
  Future<void> refresh() async {
    try {
      debugPrint('🔄 Refreshing messages for chat $chatId');
      
      _allMessages.clear();
      _loadedPages.clear();
      _currentPage = 0;
      _hasMoreMessages = true;
      
      await loadInitialMessages();
      
      debugPrint('✅ Refreshed messages');
    } catch (e) {
      debugPrint('❌ Error refreshing messages: $e');
      rethrow;
    }
  }

  /// Manage memory by removing old messages if needed
  Future<void> _manageMemory() async {
    if (_allMessages.length > maxCachedMessages) {
      final excessCount = _allMessages.length - maxCachedMessages;
      _allMessages.removeRange(0, excessCount);
      
      debugPrint('🧹 Removed $excessCount old messages for memory management');
    }
  }

  /// Simulate fetching messages from server
  Future<List<Message>> _fetchMessagesFromServer({
    required int page,
    required int limit,
    DateTime? before,
  }) async {
    // This is a placeholder - replace with actual API call
    // For now, return empty list to simulate no more messages
    debugPrint('🌐 Fetching messages from server: page=$page, limit=$limit, before=$before');
    
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Return empty list for now - implement actual API call here
    return <Message>[];
  }

  /// Simulate fetching newer messages from server
  Future<List<Message>> _fetchNewerMessages(DateTime after) async {
    // This is a placeholder - replace with actual API call
    debugPrint('🌐 Fetching newer messages after: $after');
    
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Return empty list for now - implement actual API call here
    return <Message>[];
  }

  /// Set loading state
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  /// Get page info for debugging
  Map<String, dynamic> getPageInfo() {
    return {
      'currentPage': _currentPage,
      'loadedPages': _loadedPages.toList(),
      'totalMessages': _allMessages.length,
      'hasMoreMessages': _hasMoreMessages,
      'isLoading': _isLoading,
      'isInitialized': _isInitialized,
    };
  }

  /// Clear all messages and reset state
  Future<void> clear() async {
    _allMessages.clear();
    _loadedPages.clear();
    _currentPage = 0;
    _hasMoreMessages = true;
    _isInitialized = false;
    
    notifyListeners();
    debugPrint('🗑️ Cleared all messages for chat $chatId');
  }

  /// Dispose resources
  @override
  void dispose() {
    _preloadTimer?.cancel();
    _allMessages.clear();
    _loadedPages.clear();
    super.dispose();
  }
}

/// Loading placeholder widget for messages being loaded
class MessageLoadingPlaceholder extends StatelessWidget {
  final int count;
  final bool isLoadingOlder;

  const MessageLoadingPlaceholder({
    super.key,
    this.count = 3,
    this.isLoadingOlder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        children: [
          if (isLoadingOlder) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading older messages...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ] else ...[
            ...List.generate(count, (index) => _buildMessagePlaceholder(context)),
          ],
        ],
      ),
    );
  }

  Widget _buildMessagePlaceholder(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Avatar placeholder
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // Message placeholder
          Expanded(
            child: Container(
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 50),
        ],
      ),
    );
  }
}