import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';

import 'chat_cache_service.dart';
import 'enhanced_chat_scroll_controller.dart';
import 'message_preloading_service.dart';

/// Chat state persistence manager for maintaining UI state across sessions
/// 
/// Features:
/// - Draft message preservation
/// - Scroll position restoration
/// - Typing indicator state
/// - UI preferences per chat
/// - Seamless state recovery
class ChatStatePersistenceManager extends ChangeNotifier {
  final String chatId;
  final ChatCacheService _cacheService = ChatCacheService.instance;
  
  ChatStatePersistenceManager({required this.chatId});

  // Controllers and services
  late final TextEditingController _messageController;
  late final EnhancedChatScrollController _scrollController;
  late final MessagePreloadingService _preloadingService;

  // State variables
  bool _isInitialized = false;
  bool _isTyping = false;
  bool _hasUnsavedDraft = false;
  Timer? _draftSaveTimer;
  Timer? _typingTimer;
  
  // Configuration
  static const Duration draftSaveDelay = Duration(milliseconds: 500);
  static const Duration typingIndicatorDelay = Duration(seconds: 3);

  // Getters
  TextEditingController get messageController => _messageController;
  EnhancedChatScrollController get scrollController => _scrollController;
  MessagePreloadingService get preloadingService => _preloadingService;
  bool get isInitialized => _isInitialized;
  bool get isTyping => _isTyping;
  bool get hasUnsavedDraft => _hasUnsavedDraft;

  /// Initialize the state persistence manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🔄 ChatStatePersistenceManager: Initializing for chat $chatId');

      // Initialize controllers
      _messageController = TextEditingController();
      _scrollController = EnhancedChatScrollController(chatId: chatId);
      _preloadingService = MessagePreloadingService(chatId: chatId);

      // Setup listeners
      _setupMessageControllerListener();
      
      // Initialize services
      await _preloadingService.initialize();
      
      // Restore saved state
      await _restoreState();

      _isInitialized = true;
      debugPrint('✅ ChatStatePersistenceManager: Initialized successfully');
    } catch (e) {
      debugPrint('❌ ChatStatePersistenceManager: Initialization failed: $e');
      rethrow;
    }
  }

  /// Setup message controller listener for draft saving
  void _setupMessageControllerListener() {
    _messageController.addListener(() {
      final text = _messageController.text;
      
      // Handle typing indicator
      _handleTypingIndicator(text.isNotEmpty);
      
      // Handle draft saving
      _scheduleDraftSave(text);
    });
  }

  /// Handle typing indicator logic
  void _handleTypingIndicator(bool isCurrentlyTyping) {
    if (_isTyping != isCurrentlyTyping) {
      _isTyping = isCurrentlyTyping;
      notifyListeners();
      
      // TODO: Send typing indicator to other users via WebSocket
      debugPrint('⌨️ Typing status changed: $_isTyping');
    }

    // Reset typing indicator after delay
    _typingTimer?.cancel();
    if (_isTyping) {
      _typingTimer = Timer(typingIndicatorDelay, () {
        if (_isTyping) {
          _isTyping = false;
          notifyListeners();
          debugPrint('⌨️ Typing indicator timeout');
        }
      });
    }
  }

  /// Schedule draft message saving
  void _scheduleDraftSave(String text) {
    _hasUnsavedDraft = true;
    
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(draftSaveDelay, () async {
      await _saveDraftMessage(text);
      _hasUnsavedDraft = false;
    });
  }

  /// Save draft message to cache
  Future<void> _saveDraftMessage(String text) async {
    try {
      await _cacheService.saveDraftMessage(chatId, text);
      debugPrint('✏️ Saved draft message for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error saving draft message: $e');
    }
  }

  /// Restore saved state from cache
  Future<void> _restoreState() async {
    try {
      // Restore draft message
      final draftMessage = _cacheService.getDraftMessage(chatId);
      if (draftMessage != null && draftMessage.isNotEmpty) {
        _messageController.text = draftMessage;
        debugPrint('✏️ Restored draft message: ${draftMessage.length} characters');
      }

      // Restore scroll position will be handled by the scroll controller
      // when the chat screen is built and messages are loaded
      
      debugPrint('🔄 State restoration completed for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error restoring state: $e');
    }
  }

  /// Handle when chat screen becomes visible
  Future<void> onChatVisible() async {
    try {
      // Mark messages as read when chat is visible and at bottom
      await _scrollController.onChatVisible();
      
      // Update last activity
      await _cacheService.updateLastReadTimestamp(chatId);
      
      debugPrint('👁️ Chat became visible: $chatId');
    } catch (e) {
      debugPrint('❌ Error handling chat visible: $e');
    }
  }

  /// Handle when chat screen becomes invisible
  Future<void> onChatInvisible() async {
    try {
      // Save current state
      await _saveCurrentState();
      
      // Handle scroll state
      await _scrollController.onChatInvisible();
      
      debugPrint('👁️ Chat became invisible: $chatId');
    } catch (e) {
      debugPrint('❌ Error handling chat invisible: $e');
    }
  }

  /// Save current state to cache
  Future<void> _saveCurrentState() async {
    try {
      // Save draft message
      final currentText = _messageController.text;
      if (currentText.isNotEmpty) {
        await _cacheService.saveDraftMessage(chatId, currentText);
      }
      
      // Stop typing indicator
      _isTyping = false;
      _typingTimer?.cancel();
      
      debugPrint('💾 Saved current state for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error saving current state: $e');
    }
  }

  /// Handle new message received
  Future<void> onMessageReceived(Message message) async {
    try {
      // Add to preloading service
      await _preloadingService.addMessage(message);
      
      // Handle scroll behavior
      await _scrollController.handleNewMessage(message, false);
      
      debugPrint('📨 Handled new message: ${message.id}');
    } catch (e) {
      debugPrint('❌ Error handling new message: $e');
    }
  }

  /// Handle message sent by current user
  Future<void> onMessageSent(Message message) async {
    try {
      // Clear draft message
      _messageController.clear();
      await _cacheService.saveDraftMessage(chatId, '');
      
      // Add to preloading service
      await _preloadingService.addMessage(message);
      
      // Handle scroll behavior
      await _scrollController.handleNewMessage(message, true);
      
      debugPrint('📤 Handled sent message: ${message.id}');
    } catch (e) {
      debugPrint('❌ Error handling sent message: $e');
    }
  }

  /// Handle message status update
  Future<void> onMessageStatusUpdate(String messageId, MessageStatus status) async {
    try {
      await _preloadingService.updateMessageStatus(messageId, status);
      debugPrint('📝 Updated message status: $messageId -> ${status.name}');
    } catch (e) {
      debugPrint('❌ Error updating message status: $e');
    }
  }

  /// Handle messages loaded from server/cache
  Future<void> onMessagesLoaded(List<Message> messages, {bool isInitialLoad = false}) async {
    try {
      await _scrollController.handleMessagesLoaded(messages, isInitialLoad: isInitialLoad);
      debugPrint('📚 Handled messages loaded: ${messages.length} messages');
    } catch (e) {
      debugPrint('❌ Error handling messages loaded: $e');
    }
  }

  /// Clear draft message
  Future<void> clearDraft() async {
    try {
      _messageController.clear();
      await _cacheService.saveDraftMessage(chatId, '');
      _hasUnsavedDraft = false;
      debugPrint('🗑️ Cleared draft message for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error clearing draft: $e');
    }
  }

  /// Get current draft text
  String getCurrentDraft() {
    return _messageController.text;
  }

  /// Check if there's a draft message
  bool hasDraft() {
    return _messageController.text.trim().isNotEmpty;
  }

  /// Force save current state
  Future<void> forceSaveState() async {
    _draftSaveTimer?.cancel();
    await _saveCurrentState();
  }

  /// Refresh chat data
  Future<void> refresh() async {
    try {
      await _preloadingService.refresh();
      debugPrint('🔄 Refreshed chat data for $chatId');
    } catch (e) {
      debugPrint('❌ Error refreshing chat data: $e');
      rethrow;
    }
  }

  /// Get state information for debugging
  Map<String, dynamic> getStateInfo() {
    return {
      'chatId': chatId,
      'isInitialized': _isInitialized,
      'isTyping': _isTyping,
      'hasUnsavedDraft': _hasUnsavedDraft,
      'draftLength': _messageController.text.length,
      'scrollInfo': _scrollController.hasScrollController ? {
        'isAtBottom': _scrollController.isAtBottom,
        'shouldShowScrollButton': _scrollController.shouldShowScrollToBottomButton,
      } : null,
      'preloadingInfo': _preloadingService.getPageInfo(),
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _typingTimer?.cancel();
    
    // Save state before disposing
    if (_isInitialized) {
      _saveCurrentState();
    }
    
    // Dispose controllers
    _messageController.dispose();
    _scrollController.dispose();
    _preloadingService.dispose();
    
    super.dispose();
    debugPrint('🗑️ Disposed ChatStatePersistenceManager for chat $chatId');
  }
}

/// Widget that provides state persistence for chat screens
class ChatStatePersistenceProvider extends StatefulWidget {
  final String chatId;
  final Widget Function(ChatStatePersistenceManager manager) builder;

  const ChatStatePersistenceProvider({
    super.key,
    required this.chatId,
    required this.builder,
  });

  @override
  State<ChatStatePersistenceProvider> createState() => _ChatStatePersistenceProviderState();
}

class _ChatStatePersistenceProviderState extends State<ChatStatePersistenceProvider>
    with WidgetsBindingObserver {
  late final ChatStatePersistenceManager _manager;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _manager = ChatStatePersistenceManager(chatId: widget.chatId);
    _initializeManager();
  }

  Future<void> _initializeManager() async {
    try {
      await _manager.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        await _manager.onChatVisible();
      }
    } catch (e) {
      debugPrint('❌ Error initializing chat state manager: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _manager.onChatInvisible();
        break;
      case AppLifecycleState.resumed:
        _manager.onChatVisible();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manager.onChatInvisible();
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ListenableBuilder(
      listenable: _manager,
      builder: (context, child) {
        return widget.builder(_manager);
      },
    );
  }
}