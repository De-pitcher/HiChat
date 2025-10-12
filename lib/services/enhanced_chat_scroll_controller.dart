import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import 'chat_cache_service.dart';

/// Enhanced scroll controller for WhatsApp-like chat scrolling behavior
/// 
/// Features:
/// - Smooth scroll-to-bottom with animations
/// - Intelligent auto-scroll detection
/// - Scroll position preservation and restoration
/// - Smart scroll behavior based on user interaction
/// - Unread message indicators and jump-to-unread
class EnhancedChatScrollController extends ChangeNotifier {
  final ScrollController scrollController;
  final String chatId;
  final ChatCacheService _cacheService = ChatCacheService.instance;
  
  EnhancedChatScrollController({
    required this.chatId,
    ScrollController? scrollController,
  }) : scrollController = scrollController ?? ScrollController() {
    _setupScrollListener();
  }

  // State tracking
  bool _isAtBottom = true;
  bool _isUserScrolling = false;
  bool _shouldAutoScroll = true;
  bool _isRestoring = false;
  Timer? _scrollDebounceTimer;
  Timer? _autoScrollTimer;
  
  // Configuration
  static const Duration scrollAnimationDuration = Duration(milliseconds: 300);
  static const Curve scrollAnimationCurve = Curves.easeOutCubic;
  static const double bottomThreshold = 100.0; // pixels from bottom to consider "at bottom"
  static const Duration debounceDelay = Duration(milliseconds: 100);
  static const Duration autoScrollDelay = Duration(milliseconds: 500);

  // Getters
  bool get isAtBottom => _isAtBottom;
  bool get shouldShowScrollToBottomButton => !_isAtBottom && !_isUserScrolling;
  bool get hasScrollController => scrollController.hasClients;

  /// Setup scroll listener for state tracking
  void _setupScrollListener() {
    scrollController.addListener(_onScroll);
  }

  /// Handle scroll events
  void _onScroll() {
    if (_isRestoring || !scrollController.hasClients) return;

    final position = scrollController.position;
    final isNearBottom = position.maxScrollExtent - position.pixels <= bottomThreshold;
    
    // Update bottom state
    if (_isAtBottom != isNearBottom) {
      _isAtBottom = isNearBottom;
      notifyListeners();
    }

    // Track user scrolling
    _isUserScrolling = true;
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(debounceDelay, () {
      _isUserScrolling = false;
      _saveScrollState();
    });

    // Update auto-scroll behavior
    _shouldAutoScroll = isNearBottom;
  }

  /// Save current scroll state to cache
  void _saveScrollState() {
    if (!scrollController.hasClients) return;
    
    final scrollState = ChatScrollState(
      scrollOffset: scrollController.offset,
      timestamp: DateTime.now(),
      wasAtBottom: _isAtBottom,
    );

    _cacheService.saveScrollState(chatId, scrollState);
  }

  /// Restore scroll position from cache
  Future<void> restoreScrollPosition() async {
    if (!scrollController.hasClients) return;
    
    final cachedState = _cacheService.getScrollState(chatId);
    if (cachedState == null) {
      // No cached state, scroll to bottom
      await scrollToBottom(animate: false);
      return;
    }

    _isRestoring = true;
    
    try {
      // Check if we should restore the exact position or go to bottom
      final shouldGoToBottom = cachedState.wasAtBottom || 
          DateTime.now().difference(cachedState.timestamp).inMinutes > 5;

      if (shouldGoToBottom) {
        await scrollToBottom(animate: false);
      } else {
        // Restore the exact scroll position
        scrollController.jumpTo(
          cachedState.scrollOffset.clamp(
            0.0,
            scrollController.position.maxScrollExtent,
          ),
        );
        
        _isAtBottom = cachedState.wasAtBottom;
        _shouldAutoScroll = cachedState.wasAtBottom;
        notifyListeners();
      }

      debugPrint('📍 Restored scroll position for chat $chatId: ${cachedState.scrollOffset}');
    } catch (e) {
      debugPrint('❌ Error restoring scroll position: $e');
      await scrollToBottom(animate: false);
    } finally {
      _isRestoring = false;
    }
  }

  /// Scroll to bottom with animation
  Future<void> scrollToBottom({bool animate = true}) async {
    if (!scrollController.hasClients) return;

    try {
      final maxExtent = scrollController.position.maxScrollExtent;
      
      if (animate && maxExtent > 0) {
        await scrollController.animateTo(
          maxExtent,
          duration: scrollAnimationDuration,
          curve: scrollAnimationCurve,
        );
      } else if (maxExtent > 0) {
        scrollController.jumpTo(maxExtent);
      }

      _isAtBottom = true;
      _shouldAutoScroll = true;
      notifyListeners();
      
      debugPrint('📜 Scrolled to bottom for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error scrolling to bottom: $e');
    }
  }

  /// Smart auto-scroll for new messages
  Future<void> handleNewMessage(Message message, bool isCurrentUser) async {
    if (!scrollController.hasClients) return;

    // Always auto-scroll for current user's messages
    if (isCurrentUser) {
      await scrollToBottom(animate: true);
      return;
    }

    // For other users' messages, only auto-scroll if user is near bottom
    if (_shouldAutoScroll && _isAtBottom) {
      // Add a small delay to allow message to be rendered
      _autoScrollTimer?.cancel();
      _autoScrollTimer = Timer(autoScrollDelay, () async {
        if (_shouldAutoScroll && _isAtBottom) {
          await scrollToBottom(animate: true);
        }
      });
    } else {
      // User is not at bottom, show new message indicator instead
      notifyListeners();
    }
  }

  /// Handle multiple messages being loaded (e.g., from cache or network)
  Future<void> handleMessagesLoaded(List<Message> messages, {bool isInitialLoad = false}) async {
    if (!scrollController.hasClients || messages.isEmpty) return;

    if (isInitialLoad) {
      // For initial load, restore the saved scroll position
      await restoreScrollPosition();
    } else {
      // For additional messages, maintain current position if user is not at bottom
      if (_isAtBottom) {
        await scrollToBottom(animate: false);
      }
      // If user is not at bottom, don't auto-scroll to preserve reading position
    }
  }

  /// Scroll to a specific message
  Future<void> scrollToMessage(String messageId, List<Message> messages) async {
    if (!scrollController.hasClients) return;

    try {
      final messageIndex = messages.indexWhere((m) => m.id == messageId);
      if (messageIndex == -1) return;

      // Estimate scroll position based on message index
      final totalMessages = messages.length;
      final scrollRatio = messageIndex / totalMessages;
      final targetOffset = scrollController.position.maxScrollExtent * scrollRatio;

      await scrollController.animateTo(
        targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
        duration: scrollAnimationDuration,
        curve: scrollAnimationCurve,
      );

      debugPrint('📍 Scrolled to message $messageId at index $messageIndex');
    } catch (e) {
      debugPrint('❌ Error scrolling to message: $e');
    }
  }

  /// Jump to first unread message
  Future<void> jumpToFirstUnreadMessage(List<Message> messages) async {
    if (!scrollController.hasClients) return;

    final lastReadTime = _cacheService.getLastReadTimestamp(chatId);
    if (lastReadTime == null) {
      await scrollToBottom();
      return;
    }

    try {
      final firstUnreadIndex = messages.indexWhere(
        (message) => message.timestamp.isAfter(lastReadTime),
      );

      if (firstUnreadIndex == -1) {
        // No unread messages, go to bottom
        await scrollToBottom();
        return;
      }

      // Scroll to first unread message with some padding
      final totalMessages = messages.length;
      final scrollRatio = (firstUnreadIndex - 2).clamp(0, totalMessages - 1) / totalMessages;
      final targetOffset = scrollController.position.maxScrollExtent * scrollRatio;

      await scrollController.animateTo(
        targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
        duration: scrollAnimationDuration,
        curve: scrollAnimationCurve,
      );

      debugPrint('📍 Jumped to first unread message at index $firstUnreadIndex');
    } catch (e) {
      debugPrint('❌ Error jumping to first unread message: $e');
      await scrollToBottom();
    }
  }

  /// Handle scroll to bottom button press
  Future<void> onScrollToBottomPressed() async {
    await scrollToBottom(animate: true);
    
    // Mark messages as read when user scrolls to bottom
    await _cacheService.updateLastReadTimestamp(chatId);
  }

  /// Check if should show unread message indicator
  bool shouldShowUnreadIndicator() {
    return !_isAtBottom && _cacheService.hasUnreadMessages(chatId);
  }

  /// Get unread message count for indicator
  int getUnreadMessageCount() {
    return _cacheService.getUnreadMessageCount(chatId);
  }

  /// Handle when chat becomes visible (mark as read)
  Future<void> onChatVisible() async {
    if (_isAtBottom) {
      await _cacheService.updateLastReadTimestamp(chatId);
    }
  }

  /// Handle when chat becomes invisible (save state)
  Future<void> onChatInvisible() async {
    _saveScrollState();
  }

  /// Dispose resources
  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _autoScrollTimer?.cancel();
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }
}

/// Widget that provides scroll-to-bottom button with unread count
class ScrollToBottomButton extends StatelessWidget {
  final EnhancedChatScrollController scrollController;
  final VoidCallback? onPressed;

  const ScrollToBottomButton({
    super.key,
    required this.scrollController,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scrollController,
      builder: (context, child) {
        if (!scrollController.shouldShowScrollToBottomButton) {
          return const SizedBox.shrink();
        }

        final unreadCount = scrollController.getUnreadMessageCount();
        final showUnreadIndicator = scrollController.shouldShowUnreadIndicator();

        return Positioned(
          bottom: 80,
          right: 16,
          child: AnimatedScale(
            scale: scrollController.shouldShowScrollToBottomButton ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Main button
                    InkWell(
                      onTap: onPressed ?? scrollController.onScrollToBottomPressed,
                      borderRadius: BorderRadius.circular(28),
                      child: const Center(
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    
                    // Unread count badge
                    if (showUnreadIndicator && unreadCount > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}