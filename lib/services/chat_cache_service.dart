import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';


/// WhatsApp-like chat caching service for persistent storage and improved UX
/// 
/// This service provides:
/// - Message caching with SQLite-like storage
/// - Scroll position persistence per chat
/// - Draft message preservation
/// - UI state caching (typing indicators, etc.)
/// - Intelligent preloading and pagination
class ChatCacheService {
  static ChatCacheService? _instance;
  static ChatCacheService get instance => _instance ??= ChatCacheService._();
  
  ChatCacheService._();

  SharedPreferences? _prefs;
  final Map<String, List<Message>> _messageCache = {};
  final Map<String, ChatScrollState> _scrollStates = {};
  final Map<String, String> _draftMessages = {};
  final Map<String, DateTime> _lastReadTimestamps = {};
  
  // Cache configuration
  static const int maxMessagesPerChat = 1000;
  static const int preloadMessageCount = 50;
  static const Duration cacheExpiration = Duration(days: 7);
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize the cache service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadCachedData();
      _isInitialized = true;
      debugPrint('✅ ChatCacheService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ ChatCacheService: Initialization failed: $e');
      rethrow;
    }
  }

  /// Load all cached data from persistent storage
  Future<void> _loadCachedData() async {
    if (_prefs == null) return;

    try {
      // Load cached messages
      await _loadCachedMessages();
      
      // Load scroll states
      await _loadScrollStates();
      
      // Load draft messages
      await _loadDraftMessages();
      
      // Load last read timestamps
      await _loadLastReadTimestamps();
      
      debugPrint('📱 ChatCacheService: Loaded cached data for ${_messageCache.length} chats');
    } catch (e) {
      debugPrint('❌ ChatCacheService: Error loading cached data: $e');
    }
  }

  /// Load cached messages from SharedPreferences
  Future<void> _loadCachedMessages() async {
    final chatIds = _prefs!.getStringList('cached_chat_ids') ?? [];
    
    for (final chatId in chatIds) {
      final messagesJson = _prefs!.getString('messages_$chatId');
      if (messagesJson != null) {
        try {
          final messagesList = jsonDecode(messagesJson) as List;
          final messages = messagesList
              .map((json) => Message.fromJson(json as Map<String, dynamic>))
              .toList();
          
          // Sort messages by timestamp
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          
          _messageCache[chatId] = messages;
          debugPrint('📦 Loaded ${messages.length} cached messages for chat $chatId');
        } catch (e) {
          debugPrint('❌ Error parsing cached messages for chat $chatId: $e');
          // Remove corrupted cache entry
          await _prefs!.remove('messages_$chatId');
        }
      }
    }
  }

  /// Load scroll states from SharedPreferences
  Future<void> _loadScrollStates() async {
    final scrollStatesJson = _prefs!.getString('scroll_states');
    if (scrollStatesJson != null) {
      try {
        final scrollStatesMap = jsonDecode(scrollStatesJson) as Map<String, dynamic>;
        _scrollStates.clear();
        
        scrollStatesMap.forEach((chatId, stateJson) {
          _scrollStates[chatId] = ChatScrollState.fromJson(stateJson as Map<String, dynamic>);
        });
        
        debugPrint('📍 Loaded scroll states for ${_scrollStates.length} chats');
      } catch (e) {
        debugPrint('❌ Error loading scroll states: $e');
        await _prefs!.remove('scroll_states');
      }
    }
  }

  /// Load draft messages from SharedPreferences
  Future<void> _loadDraftMessages() async {
    final draftMessagesJson = _prefs!.getString('draft_messages');
    if (draftMessagesJson != null) {
      try {
        final draftMap = jsonDecode(draftMessagesJson) as Map<String, dynamic>;
        _draftMessages.clear();
        _draftMessages.addAll(draftMap.cast<String, String>());
        
        debugPrint('✏️ Loaded draft messages for ${_draftMessages.length} chats');
      } catch (e) {
        debugPrint('❌ Error loading draft messages: $e');
        await _prefs!.remove('draft_messages');
      }
    }
  }

  /// Load last read timestamps
  Future<void> _loadLastReadTimestamps() async {
    final timestampsJson = _prefs!.getString('last_read_timestamps');
    if (timestampsJson != null) {
      try {
        final timestampsMap = jsonDecode(timestampsJson) as Map<String, dynamic>;
        _lastReadTimestamps.clear();
        
        timestampsMap.forEach((chatId, timestampStr) {
          _lastReadTimestamps[chatId] = DateTime.parse(timestampStr as String);
        });
        
        debugPrint('⏰ Loaded last read timestamps for ${_lastReadTimestamps.length} chats');
      } catch (e) {
        debugPrint('❌ Error loading last read timestamps: $e');
        await _prefs!.remove('last_read_timestamps');
      }
    }
  }

  /// Cache messages for a specific chat
  Future<void> cacheMessages(String chatId, List<Message> messages) async {
    if (!_isInitialized || _prefs == null) return;

    try {
      // Limit cache size to prevent excessive storage usage
      final limitedMessages = messages.length > maxMessagesPerChat
          ? messages.sublist(messages.length - maxMessagesPerChat)
          : messages;

      _messageCache[chatId] = List.from(limitedMessages);

      // Save to persistent storage
      final messagesJson = jsonEncode(
        limitedMessages.map((message) => message.toJson()).toList(),
      );
      
      await _prefs!.setString('messages_$chatId', messagesJson);
      
      // Update cached chat IDs list
      final cachedChatIds = _prefs!.getStringList('cached_chat_ids') ?? [];
      if (!cachedChatIds.contains(chatId)) {
        cachedChatIds.add(chatId);
        await _prefs!.setStringList('cached_chat_ids', cachedChatIds);
      }

      debugPrint('💾 Cached ${limitedMessages.length} messages for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error caching messages for chat $chatId: $e');
    }
  }

  /// Get cached messages for a chat
  List<Message> getCachedMessages(String chatId) {
    return List.from(_messageCache[chatId] ?? []);
  }

  /// Get list of chat IDs that have cached messages
  List<String> getCachedChatIds() {
    return _messageCache.keys.toList();
  }

  /// Add a new message to cache
  Future<void> addMessageToCache(String chatId, Message message) async {
    if (!_isInitialized) return;

    final messages = _messageCache[chatId] ?? [];
    
    // Check if message already exists (prevent duplicates)
    final existingIndex = messages.indexWhere((m) => m.id == message.id);
    if (existingIndex != -1) {
      // Update existing message
      messages[existingIndex] = message;
    } else {
      // Add new message
      messages.add(message);
      
      // Sort by timestamp to maintain order
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Limit cache size
      if (messages.length > maxMessagesPerChat) {
        messages.removeAt(0);
      }
    }

    await cacheMessages(chatId, messages);
  }

  /// Update message status in cache
  Future<void> updateMessageStatus(String chatId, String messageId, MessageStatus status) async {
    final messages = _messageCache[chatId];
    if (messages == null) return;

    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final updatedMessage = messages[messageIndex].copyWith(status: status);
      messages[messageIndex] = updatedMessage;
      await cacheMessages(chatId, messages);
      
      debugPrint('📝 Updated message $messageId status to ${status.name}');
    }
  }

  /// Save scroll state for a chat
  Future<void> saveScrollState(String chatId, ChatScrollState scrollState) async {
    if (!_isInitialized || _prefs == null) return;

    try {
      _scrollStates[chatId] = scrollState;
      
      // Save all scroll states to persistent storage
      final scrollStatesJson = jsonEncode(
        _scrollStates.map((key, value) => MapEntry(key, value.toJson())),
      );
      
      await _prefs!.setString('scroll_states', scrollStatesJson);
      
      debugPrint('📍 Saved scroll state for chat $chatId: ${scrollState.scrollOffset}');
    } catch (e) {
      debugPrint('❌ Error saving scroll state for chat $chatId: $e');
    }
  }

  /// Get scroll state for a chat
  ChatScrollState? getScrollState(String chatId) {
    return _scrollStates[chatId];
  }

  /// Save draft message for a chat
  Future<void> saveDraftMessage(String chatId, String draft) async {
    if (!_isInitialized || _prefs == null) return;

    try {
      if (draft.trim().isEmpty) {
        _draftMessages.remove(chatId);
      } else {
        _draftMessages[chatId] = draft;
      }
      
      // Save all draft messages to persistent storage
      await _prefs!.setString('draft_messages', jsonEncode(_draftMessages));
      
      debugPrint('✏️ Saved draft message for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error saving draft message for chat $chatId: $e');
    }
  }

  /// Get draft message for a chat
  String? getDraftMessage(String chatId) {
    return _draftMessages[chatId];
  }

  /// Update last read timestamp for a chat
  Future<void> updateLastReadTimestamp(String chatId) async {
    if (!_isInitialized || _prefs == null) return;

    try {
      final now = DateTime.now();
      _lastReadTimestamps[chatId] = now;
      
      // Save all timestamps to persistent storage
      final timestampsJson = jsonEncode(
        _lastReadTimestamps.map((key, value) => MapEntry(key, value.toIso8601String())),
      );
      
      await _prefs!.setString('last_read_timestamps', timestampsJson);
      
      debugPrint('⏰ Updated last read timestamp for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error updating last read timestamp for chat $chatId: $e');
    }
  }

  /// Get last read timestamp for a chat
  DateTime? getLastReadTimestamp(String chatId) {
    return _lastReadTimestamps[chatId];
  }

  /// Check if there are newer messages than last read
  bool hasUnreadMessages(String chatId) {
    final messages = _messageCache[chatId];
    final lastRead = _lastReadTimestamps[chatId];
    
    if (messages == null || messages.isEmpty || lastRead == null) {
      return false;
    }

    return messages.any((message) => message.timestamp.isAfter(lastRead));
  }

  /// Get unread message count for a chat
  int getUnreadMessageCount(String chatId) {
    final messages = _messageCache[chatId];
    final lastRead = _lastReadTimestamps[chatId];
    
    if (messages == null || messages.isEmpty || lastRead == null) {
      return 0;
    }

    return messages.where((message) => message.timestamp.isAfter(lastRead)).length;
  }

  /// Clear cache for a specific chat
  Future<void> clearChatCache(String chatId) async {
    if (!_isInitialized || _prefs == null) return;

    try {
      _messageCache.remove(chatId);
      _scrollStates.remove(chatId);
      _draftMessages.remove(chatId);
      _lastReadTimestamps.remove(chatId);
      
      // Remove from persistent storage
      await _prefs!.remove('messages_$chatId');
      
      final cachedChatIds = _prefs!.getStringList('cached_chat_ids') ?? [];
      cachedChatIds.remove(chatId);
      await _prefs!.setStringList('cached_chat_ids', cachedChatIds);
      
      await _prefs!.setString('scroll_states', jsonEncode(
        _scrollStates.map((key, value) => MapEntry(key, value.toJson())),
      ));
      await _prefs!.setString('draft_messages', jsonEncode(_draftMessages));
      await _prefs!.setString('last_read_timestamps', jsonEncode(
        _lastReadTimestamps.map((key, value) => MapEntry(key, value.toIso8601String())),
      ));
      
      debugPrint('🗑️ Cleared cache for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error clearing cache for chat $chatId: $e');
    }
  }

  /// Clear all cache data
  Future<void> clearAllCache() async {
    if (!_isInitialized || _prefs == null) return;

    try {
      _messageCache.clear();
      _scrollStates.clear();
      _draftMessages.clear();
      _lastReadTimestamps.clear();
      
      // Clear from persistent storage
      final cachedChatIds = _prefs!.getStringList('cached_chat_ids') ?? [];
      for (final chatId in cachedChatIds) {
        await _prefs!.remove('messages_$chatId');
      }
      
      await _prefs!.remove('cached_chat_ids');
      await _prefs!.remove('scroll_states');
      await _prefs!.remove('draft_messages');
      await _prefs!.remove('last_read_timestamps');
      
      debugPrint('🗑️ Cleared all cache data');
    } catch (e) {
      debugPrint('❌ Error clearing all cache: $e');
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    final totalMessages = _messageCache.values.fold<int>(
      0,
      (sum, messages) => sum + messages.length,
    );

    return {
      'totalChats': _messageCache.length,
      'totalMessages': totalMessages,
      'scrollStates': _scrollStates.length,
      'draftMessages': _draftMessages.length,
      'lastReadTimestamps': _lastReadTimestamps.length,
      'initialized': _isInitialized,
    };
  }

  /// Cleanup expired cache entries
  Future<void> cleanupExpiredCache() async {
    if (!_isInitialized || _prefs == null) return;

    try {
      final cutoffTime = DateTime.now().subtract(cacheExpiration);
      final chatsToRemove = <String>[];

      for (final entry in _lastReadTimestamps.entries) {
        if (entry.value.isBefore(cutoffTime)) {
          chatsToRemove.add(entry.key);
        }
      }

      for (final chatId in chatsToRemove) {
        await clearChatCache(chatId);
      }

      if (chatsToRemove.isNotEmpty) {
        debugPrint('🧹 Cleaned up expired cache for ${chatsToRemove.length} chats');
      }
    } catch (e) {
      debugPrint('❌ Error during cache cleanup: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _messageCache.clear();
    _scrollStates.clear();
    _draftMessages.clear();
    _lastReadTimestamps.clear();
    _isInitialized = false;
  }
}

/// Represents the scroll state of a chat screen
class ChatScrollState {
  final double scrollOffset;
  final DateTime timestamp;
  final bool wasAtBottom;
  final String? lastVisibleMessageId;

  const ChatScrollState({
    required this.scrollOffset,
    required this.timestamp,
    this.wasAtBottom = false,
    this.lastVisibleMessageId,
  });

  factory ChatScrollState.fromJson(Map<String, dynamic> json) {
    return ChatScrollState(
      scrollOffset: (json['scrollOffset'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      wasAtBottom: json['wasAtBottom'] as bool? ?? false,
      lastVisibleMessageId: json['lastVisibleMessageId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scrollOffset': scrollOffset,
      'timestamp': timestamp.toIso8601String(),
      'wasAtBottom': wasAtBottom,
      'lastVisibleMessageId': lastVisibleMessageId,
    };
  }

  ChatScrollState copyWith({
    double? scrollOffset,
    DateTime? timestamp,
    bool? wasAtBottom,
    String? lastVisibleMessageId,
  }) {
    return ChatScrollState(
      scrollOffset: scrollOffset ?? this.scrollOffset,
      timestamp: timestamp ?? this.timestamp,
      wasAtBottom: wasAtBottom ?? this.wasAtBottom,
      lastVisibleMessageId: lastVisibleMessageId ?? this.lastVisibleMessageId,
    );
  }

  @override
  String toString() {
    return 'ChatScrollState{scrollOffset: $scrollOffset, wasAtBottom: $wasAtBottom, lastVisibleMessageId: $lastVisibleMessageId}';
  }
}