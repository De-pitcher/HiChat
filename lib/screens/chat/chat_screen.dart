import 'dart:async';

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../services/chat_state_manager.dart';
import '../../services/auth_state_manager.dart';
import '../../services/native_camera_service.dart';

import '../../widgets/chat/optimized_message_bubble.dart';
import '../../widgets/chat/message_input.dart';

// In the imports section, add:
import '../../widgets/chat/chat_app_bar.dart';
import '../../widgets/chat/empty_chat_state.dart';
import '../../widgets/chat/scroll_to_bottom_fab.dart';

// import 'package:file_picker/file_picker.dart'; // Temporarily disabled - backend support needed

import '../../widgets/chat/date_separator.dart';

import '../../utils/date_utils.dart' as date_utils;

/// String extension for capitalize method
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

/// Optimized state class for message list to minimize rebuilds
class ChatMessagesState {
  final List<Message> messages;
  final bool isLoading;
  final bool isConnected;

  const ChatMessagesState({
    required this.messages,
    required this.isLoading,
    required this.isConnected,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessagesState &&
          runtimeType == other.runtimeType &&
          messages.length == other.messages.length &&
          isLoading == other.isLoading &&
          isConnected == other.isConnected &&
          _messagesEqual(messages, other.messages);

  @override
  int get hashCode =>
      Object.hash(messages.length, isLoading, isConnected, _getMessagesHash());

  bool _messagesEqual(List<Message> a, List<Message> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // Compare all important properties to detect any changes
      if (a[i].id != b[i].id ||
          a[i].status != b[i].status ||
          a[i].content != b[i].content ||
          a[i].timestamp != b[i].timestamp ||
          a[i].type != b[i].type) {
        return false;
      }
    }
    return true;
  }

  int _getMessagesHash() {
    return Object.hashAll(
      messages.map((m) => Object.hash(m.id, m.content, m.status, m.timestamp)),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  // Edit mode state
  Message? _editingMessage;
  bool get _isEditMode => _editingMessage != null;

  // Reply mode state
  Message? _replyingToMessage;
  bool get _isReplyMode => _replyingToMessage != null;

  // Read receipts tracking
  Timer? _readReceiptsTimer;

  // Auto retry for failed messages
  Timer? _autoRetryTimer;

  // Message highlighting for scroll-to functionality
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  // Timestamp to prevent auto-scroll briefly after manual scroll-to-message
  DateTime? _lastManualScrollTime;

  // Scroll state management
  bool _isUserScrolledUp = false;
  bool _showScrollToBottomFab = false;
  int _unreadMessageCount = 0;

  // Simplified scroll management
  bool _isInitialLoad = true;
  bool _wasAtBottomOnLastExit = true; // Simple persistence flag

  // FAB auto-hide functionality
  Timer? _fabHideTimer;
  bool _isScrolling = false;

  // Performance optimization: Cache grouped messages
  List<dynamic>? _cachedGroupedMessages;
  List<Message>? _lastProcessedMessages;

  // Note: Floating date indicator variables can be added here for future enhancement

  @override
  void initState() {
    super.initState();
    _loadSavedScrollPosition();
    _loadMessages();
    _setupReadReceipts();
    _setupAutoRetry();
  }

  @override
  void dispose() {
    // Save state before disposal
    _saveScrollPosition();

    // Cancel all timers to prevent memory leaks
    _readReceiptsTimer?.cancel();
    _readReceiptsTimer = null;
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _fabHideTimer?.cancel();
    _fabHideTimer = null;

    // Clear cached data to free memory
    _cachedGroupedMessages = null;
    _lastProcessedMessages = null;

    // Dispose controllers
    _messageController.dispose();

    // ItemScrollController doesn't need explicit disposal
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final chatStateManager = context.read<ChatStateManager>();
    await chatStateManager.loadMessagesForChat(widget.chat.id);

    // Restore scroll position or scroll to bottom after messages load
    _restoreScrollPositionOrBottom();
  }

  void _setupReadReceipts() {
    // Set up optimized periodic timer (reduced frequency)
    _readReceiptsTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _markVisibleMessagesAsRead();
      }
    });

    // Listen to item position changes for read receipts and scroll state
    _itemPositionsListener.itemPositions.addListener(() {
      if (mounted) {
        _onScrollChanged();
        _updateScrollState();
      }
    });
  }

  void _onScrollChanged() {
    // Set scrolling flag when scroll activity is detected
    _isScrolling = true;

    // Reset and restart the FAB hide timer on scroll activity
    _setupFabHideTimer();

    // Mark messages as read when scrolling stops (debounced)
    _readReceiptsTimer?.cancel();
    _readReceiptsTimer = Timer(const Duration(milliseconds: 500), () {
      _markVisibleMessagesAsRead();
      // Clear scrolling flag after scroll stops
      _isScrolling = false;
    });
  }

  void _handleScrollEvent() {
    if (!_itemScrollController.isAttached) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Get current position info
    final maxVisibleIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);
    final chatStateManager = context.read<ChatStateManager>();
    final messages = chatStateManager.getMessagesForChat(widget.chat.id);

    if (messages.isNotEmpty) {
      final groupedItems = _getGroupedMessages(messages);
      final totalItems = groupedItems.length;
      final isAtBottom = maxVisibleIndex >= (totalItems - 1);
      final isNearBottom = maxVisibleIndex >= (totalItems - 3);

      // Show FAB only if user scrolled up and not too close to bottom
      if (!isAtBottom && !isNearBottom && !_showScrollToBottomFab) {
        setState(() {
          _showScrollToBottomFab = true;
        });
        _setupFabHideTimer();
        debugPrint('📍 Showing FAB due to scroll event with 5-second timer');
      }
    }
  }

  /// Check if auto-scroll should happen (avoid interfering with recent manual scrolls)
  bool _shouldAutoScroll() {
    // Don't auto-scroll if user has manually scrolled up
    if (_isUserScrolledUp) return false;

    // Don't auto-scroll immediately after manual scrolling to specific message
    if (_lastManualScrollTime != null) {
      final timeSinceManualScroll = DateTime.now().difference(
        _lastManualScrollTime!,
      );
      if (timeSinceManualScroll.inSeconds <= 2) return false;
    }

    return true;
  }

  /// Update scroll state with improved FAB behavior
  void _updateScrollState() {
    if (!_itemScrollController.isAttached) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    try {
      // Get the highest visible index (closest to bottom)
      final maxVisibleIndex = positions
          .map((p) => p.index)
          .reduce((a, b) => a > b ? a : b);

      // Get chat data for calculations
      final chatStateManager = context.read<ChatStateManager>();
      final messages = chatStateManager.getMessagesForChat(widget.chat.id);

      if (messages.isNotEmpty) {
        final groupedItems = _getGroupedMessages(messages);
        final totalItems = groupedItems.length;

        // Check if we're at the very bottom (can see the last item)
        final isAtBottom = maxVisibleIndex >= (totalItems - 1);

        // Update scroll state
        final wasScrolledUp = _isUserScrolledUp;
        _isUserScrolledUp = !isAtBottom;

        // Update FAB visibility - hide immediately if at bottom
        if (isAtBottom) {
          _hideFabImmediately();
        }
        // Note: FAB showing is now handled by scroll events, not position updates

        // Update unread count logic
        if (_isUserScrolledUp && !wasScrolledUp) {
          _updateUnreadCount();
        } else if (!_isUserScrolledUp) {
          _unreadMessageCount = 0;
        }
      }
    } catch (e) {
      debugPrint('❌ Error in _updateScrollState: $e');
    }
  }

  /// Hide the FAB immediately (when at bottom)
  void _hideFabImmediately() {
    _fabHideTimer?.cancel();
    if (_showScrollToBottomFab) {
      setState(() {
        _showScrollToBottomFab = false;
      });
      debugPrint('📍 Hiding FAB - at bottom');
    }
  }

  /// Set up a timer to hide FAB after 5 seconds of no scroll activity
  void _setupFabHideTimer() {
    _fabHideTimer?.cancel();
    _fabHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showScrollToBottomFab && !_isScrolling) {
        // Only hide if we're not actively scrolling
        setState(() {
          _showScrollToBottomFab = false;
        });
        debugPrint('📍 Auto-hiding FAB after 5 seconds of no scroll');
      }
    });
  }

  /// Cache-optimized message grouping to prevent expensive recomputation
  List<dynamic> _getGroupedMessages(List<Message> messages) {
    // Check if we can use cached results
    if (_cachedGroupedMessages != null &&
        _lastProcessedMessages != null &&
        _areMessageListsEqual(_lastProcessedMessages!, messages)) {
      return _cachedGroupedMessages!;
    }

    // Compute new grouped messages and cache the result
    _cachedGroupedMessages = date_utils.DateUtils.groupMessagesByDate(messages);
    _lastProcessedMessages = List.from(messages);

    return _cachedGroupedMessages!;
  }

  /// Efficient message list equality check
  bool _areMessageListsEqual(List<Message> list1, List<Message> list2) {
    if (list1.length != list2.length) return false;

    // Quick check: compare last few messages (most likely to change)
    final checkCount = math.min(5, list1.length);
    for (int i = 0; i < checkCount; i++) {
      final index = list1.length - 1 - i;
      if (list1[index].id != list2[index].id ||
          list1[index].status != list2[index].status ||
          list1[index].timestamp != list2[index].timestamp) {
        return false;
      }
    }

    return true;
  }

  /// Clear message cache to force recomputation (call when messages are modified)
  void _invalidateMessageCache() {
    _cachedGroupedMessages = null;
    _lastProcessedMessages = null;
  }

  /// Update unread message count when user is scrolled up
  void _updateUnreadCount() {
    final chatStateManager = context.read<ChatStateManager>();
    final messages = chatStateManager.getMessagesForChat(widget.chat.id);
    final authManager = context.read<AuthStateManager>();
    final currentUserId = authManager.currentUser?.id.toString();

    if (currentUserId == null || messages.isEmpty) {
      _unreadMessageCount = 0;
      return;
    }

    // Count messages from others that are below the current viewport
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final lowestVisibleIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a < b ? a : b);
    final groupedItems = _getGroupedMessages(messages);

    int unreadCount = 0;
    for (int i = 0; i < lowestVisibleIndex && i < groupedItems.length; i++) {
      final item = groupedItems[i];
      if (item is Message && item.senderId != currentUserId) {
        unreadCount++;
      }
    }

    _unreadMessageCount = unreadCount;
  }

  /// Load simple scroll state - just whether user was at bottom or not
  Future<void> _loadSavedScrollPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_was_at_bottom_${widget.chat.id}';
      _wasAtBottomOnLastExit = prefs.getBool(key) ?? true; // Default to bottom
      debugPrint('📖 Chat opening - was at bottom: $_wasAtBottomOnLastExit');
    } catch (e) {
      debugPrint('❌ Error loading scroll state: $e');
      _wasAtBottomOnLastExit = true; // Safe default
    }
  }

  /// Save simple scroll state - just whether user is at bottom or not
  Future<void> _saveScrollPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_was_at_bottom_${widget.chat.id}';
      await prefs.setBool(key, !_isUserScrolledUp);
      debugPrint(
        '💾 Chat closing - saving was at bottom: ${!_isUserScrolledUp}',
      );
    } catch (e) {
      debugPrint('❌ Error saving scroll state: $e');
    }
  }

  /// Simple scroll to bottom - no complex calculations
  void _scrollToBottom() {
    if (!_isInitialLoad) return; // Only auto-scroll on initial load

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) return;

      // Simple approach: just scroll to a very large index, the controller will clamp it
      try {
        _itemScrollController.jumpTo(index: 999999);
        _isInitialLoad = false; // Mark that initial load is complete
        debugPrint('📍 Scrolled to bottom on initial load');
      } catch (e) {
        debugPrint('❌ Error scrolling to bottom: $e');
      }
    });
  }

  /// Restore scroll position - simple approach
  void _restoreScrollPositionOrBottom() {
    if (_wasAtBottomOnLastExit) {
      // User was at bottom when they left, scroll to bottom
      _scrollToBottom();
    } else {
      // User was scrolled up, don't auto-scroll (let them see where they were)
      debugPrint('🔄 User was scrolled up on last exit, not auto-scrolling');
      _isInitialLoad = false; // Prevent auto-scroll
    }
  }

  /// Scroll to bottom with animation - simplified and safe
  void _scrollToBottomAnimated() {
    if (!_itemScrollController.isAttached) return;

    try {
      // Hide FAB immediately when user taps it
      _hideFabImmediately();

      // Simple approach: scroll to a very large index, controller will clamp it safely
      _itemScrollController.scrollTo(
        index: 999999,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      // Reset scroll state
      setState(() {
        _isUserScrolledUp = false;
        _unreadMessageCount = 0;
      });

      debugPrint('📍 Animated scroll to bottom');
    } catch (e) {
      debugPrint('❌ Error in animated scroll: $e');
    }
  }

  void _markVisibleMessagesAsRead() {
    try {
      final chatStateManager = Provider.of<ChatStateManager>(
        context,
        listen: false,
      );
      final authManager = Provider.of<AuthStateManager>(context, listen: false);
      final currentUserId = authManager.currentUser?.id.toString();

      if (currentUserId == null) return;

      final messages = chatStateManager.getMessagesForChat(widget.chat.id);
      final unreadMessages = messages
          .where(
            (message) =>
                message.senderId != currentUserId && // Not sent by current user
                !message.isRead && // Not already read
                _isMessageVisible(message),
          )
          .toList();

      if (unreadMessages.isNotEmpty) {
        final messageIds = unreadMessages.map((m) => m.id).toList();
        chatStateManager.markMessagesAsSeen(widget.chat.id, messageIds);

        debugPrint('📖 Marked ${messageIds.length} messages as read');
      }
    } catch (e) {
      debugPrint('❌ Error marking messages as read: $e');
    }
  }

  bool _isMessageVisible(Message message) {
    // Simple implementation: assume messages are visible if the user has opened the chat
    // and the item scroll controller is attached. This will mark messages as read when they
    // enter the chat, which is reasonable behavior for most chat apps.
    return _itemScrollController.isAttached;
  }

  void _setupAutoRetry() {
    // Set up periodic timer to check for failed messages and retry them automatically
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _autoRetryFailedMessages();
    });
  }

  void _autoRetryFailedMessages() {
    try {
      final chatStateManager = Provider.of<ChatStateManager>(
        context,
        listen: false,
      );
      final messages = chatStateManager.getMessagesForChat(widget.chat.id);

      final failedMessages = messages
          .where((message) => message.isFailed && _shouldRetryMessage(message))
          .toList();

      for (final message in failedMessages) {
        final retryCount = message.metadata?['retry_count'] ?? 0;
        if (retryCount < 3) {
          // Max 3 automatic retries
          debugPrint(
            '🔄 Auto-retrying failed message: ${message.id} (attempt ${retryCount + 1})',
          );
          _handleMessageRetry(message);
        }
      }
    } catch (e) {
      debugPrint('❌ Error in auto-retry: $e');
    }
  }

  bool _shouldRetryMessage(Message message) {
    // Only retry messages that failed recently (within last 5 minutes)
    final now = DateTime.now();
    final messageAge = now.difference(message.timestamp);
    return messageAge.inMinutes <= 5;
  }

  /// Send text message or save edited message
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // Check if we're in edit mode
    if (_editingMessage != null) {
      await _saveEditedMessage();
      return;
    }

    final authManager = context.read<AuthStateManager>();
    final chatStateManager = context.read<ChatStateManager>();
    final currentUserId =
        authManager.currentUser?.id.toString() ?? 'currentUser';

    // Get reply context before clearing
    final replyToMessageId = _replyingToMessage?.id;

    _messageController.clear();

    // Clear reply state after getting the ID
    if (_replyingToMessage != null) {
      setState(() {
        _replyingToMessage = null;
      });
    }

    _scrollToBottom();

    try {
      // Get receiver ID - for direct chats, it's the other participant
      int? receiverId;
      if (widget.chat.type == ChatType.direct &&
          widget.chat.participants.isNotEmpty) {
        final otherParticipant = widget.chat.participants.firstWhere(
          (p) => p.id.toString() != currentUserId,
          orElse: () => widget.chat.participants.first,
        );
        receiverId = otherParticipant.id;
      }

      await chatStateManager.sendMessage(
        chatId: widget.chat.id,
        content: content,
        type: 'text',
        receiverId: receiverId,
        replyToMessageId: replyToMessageId,
      );

      // Invalidate cache after sending message
      _invalidateMessageCache();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  /// Send multimedia message (image, video, audio)
  Future<void> _sendMultimediaMessage(NativeCameraResult mediaResult) async {
    debugPrint(
      '💬 ChatScreen: Starting to send multimedia message - ${mediaResult.type.name}, size: ${mediaResult.formattedSize}',
    );

    final chatStateManager = context.read<ChatStateManager>();
    final authManager = context.read<AuthStateManager>();
    final currentUserId =
        authManager.currentUser?.id.toString() ?? 'currentUser';

    try {
      // Get receiver ID
      int? receiverId;
      if (widget.chat.type == ChatType.direct &&
          widget.chat.participants.isNotEmpty) {
        final otherParticipant = widget.chat.participants.firstWhere(
          (p) => p.id.toString() != currentUserId,
          orElse: () => widget.chat.participants.first,
        );
        receiverId = otherParticipant.id;
      }

      debugPrint(
        '💬 ChatScreen: Receiver ID: $receiverId, Chat ID: ${widget.chat.id}',
      );

      // Show upload progress indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text('Uploading ${mediaResult.type.name}...'),
            ],
          ),
          duration: const Duration(seconds: 30), // Long duration for upload
        ),
      );

      await chatStateManager.sendMultimediaMessage(
        chatId: widget.chat.id,
        mediaResult: mediaResult,
        receiverId: receiverId,
        onUploadProgress: (progress) {
          debugPrint('Upload progress: ${(progress * 100).round()}%');
        },
      );

      // Hide progress indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('${mediaResult.type.name.capitalize()} sent successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send multimedia message: $e');

      // Hide progress indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to send ${mediaResult.type.name}: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Handle native camera capture - show selection dialog for image or video
  Future<void> _handleCameraResult() async {
    try {
      debugPrint(
        '🎯 ChatScreen: Camera button pressed, showing media selection dialog...',
      );

      // Show media selection dialog for camera capture
      final result = await NativeCameraService.showMediaSelectionDialog(
        context,
        allowGallery: false, // Only camera options
        allowImage: true,
        allowVideo: true,
      );

      debugPrint('🎯 ChatScreen: Media selection result: $result');

      if (result != null) {
        debugPrint('🎯 ChatScreen: Sending multimedia message...');
        await _sendMultimediaMessage(result);
      } else {
        debugPrint('🎯 ChatScreen: No media selected or user cancelled');
      }
    } catch (e) {
      debugPrint('🎯 ChatScreen: Native camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle gallery selection using native camera service
  Future<void> _handleGallerySelection() async {
    try {
      // Show media selection dialog for gallery
      final result = await NativeCameraService.showMediaSelectionDialog(
        context,
        allowCamera: false, // Only gallery options
        allowGallery: true,
        allowImage: true,
        allowVideo: true,
      );

      if (result != null) {
        await _sendMultimediaMessage(result);
      }
    } catch (e) {
      debugPrint('Gallery selection error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Gallery error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Handle retry for failed messages
  Future<void> _handleMessageRetry(Message message) async {
    debugPrint(
      '🔄 ChatScreen: Retrying message - ID: ${message.id}, Type: ${message.type}',
    );

    final chatStateManager = context.read<ChatStateManager>();

    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text('Retrying ${message.type.name}...'),
            ],
          ),
          duration: const Duration(seconds: 30), // Long duration for retry
        ),
      );

      await chatStateManager.retryFailedMessage(message);

      // Hide loading indicator and show success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('${message.type.name.capitalize()} sent successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('🔄 ChatScreen: Retry failed: $e');

      // Hide loading indicator and show error
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Retry failed: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // Replace the entire build method with this simplified version:
  @override
  Widget build(BuildContext context) {
    final chatStateManager = context.read<ChatStateManager>();
    final currentUserId = chatStateManager.getCurrentUserIdForUI();

    return Scaffold(
      appBar: ChatAppBar(
        chat: widget.chat,
        onBackPressed: () => Navigator.pop(context),
        onChatInfoPressed: () {
          Navigator.pushNamed(context, '/chat-info', arguments: widget.chat);
        },
        onTestReply: _handleTestReply,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(context).cardColor,
                ],
                stops: const [0.0, 0.3],
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Consumer<ChatStateManager>(
                    builder: (context, chatStateManager, child) {
                      final messagesState = ChatMessagesState(
                        messages: chatStateManager.getMessagesForChat(
                          widget.chat.id,
                        ),
                        isLoading: chatStateManager.isLoading,
                        isConnected: chatStateManager.isConnected,
                      );

                      debugPrint(
                        '🔄 Chat UI rebuilding - Message count: ${messagesState.messages.length}',
                      );

                      if (messagesState.isLoading &&
                          messagesState.messages.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 3),
                        );
                      }

                      if (messagesState.messages.isEmpty) {
                        return EmptyChatState(
                          isLoading: messagesState.isLoading,
                          isConnected: messagesState.isConnected,
                        );
                      }

                      // Auto-scroll to bottom when messages are loaded (with debounce for manual scrolls)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (messagesState.messages.isNotEmpty &&
                            _shouldAutoScroll()) {
                          _scrollToBottom();
                        }
                      });

                      // Group messages by date and insert date separators (cached)
                      final groupedItems = _getGroupedMessages(
                        messagesState.messages,
                      );

                      return _buildMessageList(groupedItems, currentUserId);
                    },
                  ),
                ),
                MessageInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                  chat: widget.chat,
                  onCameraPressed: _handleCameraResult,
                  onGalleryPressed: _handleGallerySelection,
                  isEditMode: _isEditMode,
                  onCancelEdit: _cancelEdit,
                  editingMessage: _editingMessage,
                  isReplyMode: _isReplyMode,
                  onCancelReply: _cancelReply,
                  replyingToMessage: _replyingToMessage,
                ),
              ],
            ),
          ),
         // FAB positioned above the input
        Positioned(
          bottom: _getFabPosition(), // Dynamic positioning
          right: 16,
          child: ScrollToBottomFab(
            visible: _showScrollToBottomFab,
            unreadMessageCount: _unreadMessageCount,
            onPressed: _scrollToBottomAnimated,
          ),
        ),
        ],
      ),
      // floatingActionButton: ScrollToBottomFab(
      //   visible: _showScrollToBottomFab,
      //   unreadMessageCount: _unreadMessageCount,
      //   onPressed: _scrollToBottomAnimated,
      // ),
    );
  }

  double _getFabPosition() {
    // Adjust this value based on your input field height
    // Typical input field height is around 70-80 pixels
    return 80.0; // Position 80 pixels from bottom
  }

  // Add this helper method for building the message list
  Widget _buildMessageList(List<dynamic> groupedItems, String currentUserId) {
    return ScrollablePositionedList.builder(
      key: const PageStorageKey('chat_messages_list'),
      itemScrollController: _itemScrollController,
      scrollOffsetController: _scrollOffsetController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      itemCount: groupedItems.length,
      minCacheExtent: 200,
      itemBuilder: (context, index) {
        final item = groupedItems[index];

        // Check if this is a date separator
        if (item is date_utils.DateSeparatorItem) {
          return RepaintBoundary(
            key: ValueKey('date_${item.date.millisecondsSinceEpoch}'),
            child: DateSeparator(date: item.date),
          );
        }

        // Otherwise it's a message
        final message = item as Message;
        final isCurrentUser = message.senderId == currentUserId;

        return RepaintBoundary(
          key: ValueKey('message_${message.id}'),
          child: OptimizedMessageBubble(
            message: message,
            isCurrentUser: isCurrentUser,
            chat: widget.chat,
            onRetry: _handleMessageRetry,
            onEdit: _editMessage,
            onReply: _setReplyToMessage,
            onScrollToMessage: _scrollToMessage,
            isHighlighted: _highlightedMessageId == message.id,
          ),
        );
      },
    );
  }

  // Add this helper method for test reply functionality
  void _handleTestReply() {
    final chatStateManager = context.read<ChatStateManager>();
    final messages = chatStateManager.getMessagesForChat(widget.chat.id);

    if (messages.isNotEmpty) {
      final testMessage = messages.first;
      debugPrint(
        '🧪 Testing reply functionality with message: ${testMessage.id}',
      );
      _setReplyToMessage(testMessage);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🧪 Testing reply to: "${testMessage.content}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🧪 No messages available for testing'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Message action methods
  void _setReplyToMessage(Message message) {
    debugPrint(
      '🔄 Setting reply to message: ${message.id} - "${message.content}"',
    );
    setState(() {
      _replyingToMessage = message;
      // Clear edit mode if active
      _editingMessage = null;
    });

    // Focus on the text input
    FocusScope.of(context).requestFocus();
    debugPrint('✅ Reply mode activated');
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  /// Scroll to a specific message by ID and highlight it
  void _scrollToMessage(String messageId) async {
    debugPrint('🎯 Scrolling to message: $messageId');

    // Record manual scroll time to prevent auto-scroll interference
    _lastManualScrollTime = DateTime.now();

    final chatStateManager = context.read<ChatStateManager>();
    final messages = chatStateManager.getMessagesForChat(widget.chat.id);

    // Find the message index in the original messages list
    final messageIndex = messages.indexWhere((msg) => msg.id == messageId);

    if (messageIndex == -1) {
      debugPrint('❌ Message $messageId not found in current messages');

      // TODO: Implement lazy loading if message not found
      // This is where you would load older messages until the target is found
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message not found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    debugPrint('✅ Found message at index: $messageIndex');

    // Group messages by date to get the actual ListView items (includes date separators)
    final groupedItems = _getGroupedMessages(messages);

    // Find the target message in the grouped items
    int targetIndex = -1;
    for (int i = 0; i < groupedItems.length; i++) {
      if (groupedItems[i] is Message &&
          (groupedItems[i] as Message).id == messageId) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex == -1) {
      debugPrint('❌ Message $messageId not found in grouped items');
      return;
    }

    debugPrint('📍 Scrolling to grouped item index: $targetIndex');

    // Ensure scroll controller is ready
    if (!_itemScrollController.isAttached) {
      debugPrint('❌ ItemScrollController not attached');
      return;
    }

    try {
      _isScrolling = true;

      // Smooth scroll to the target message using precise index
      await _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );

      // Check if we should show FAB after scroll completes
      // Small delay to let the scroll settle and positions update
      await Future.delayed(const Duration(milliseconds: 100));

      // Get current messages and check position relative to bottom
      final currentMessages = chatStateManager.getMessagesForChat(
        widget.chat.id,
      );
      if (currentMessages.isNotEmpty) {
        final currentGroupedItems = _getGroupedMessages(currentMessages);
        final totalItems = currentGroupedItems.length;

        // If the target message is not near the bottom, show FAB
        final isNearBottom = targetIndex >= (totalItems - 3);
        final isAtBottom = targetIndex >= (totalItems - 1);

        if (!isAtBottom && !isNearBottom) {
          // Show FAB since we're not at bottom
          setState(() {
            _showScrollToBottomFab = true;
            _isUserScrolledUp = true;
          });
          _setupFabHideTimer(); // Start 5-second timer
          debugPrint(
            '📍 Showing FAB after scroll-to-message (not at bottom) with 5-second timer',
          );
        } else {
          // Hide FAB since we're at or near bottom
          _hideFabImmediately();
          debugPrint('📍 Hiding FAB after scroll-to-message (at bottom)');
        }
      }

      // Highlight the message temporarily
      setState(() {
        _highlightedMessageId = messageId;
      });

      // Clear highlighting after 2 seconds
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });

      debugPrint(
        '✅ Successfully scrolled to and highlighted message $messageId',
      );
    } catch (e) {
      debugPrint('❌ Error scrolling to message: $e');
    }
  }

  void _editMessage(Message message) {
    // Check if message can still be edited (within 10 minutes)
    final now = DateTime.now();
    final messageAge = now.difference(message.timestamp);
    const editTimeLimit = Duration(minutes: 10);

    if (messageAge > editTimeLimit) {
      final minutesOld = messageAge.inMinutes;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Messages can only be edited within 10 minutes of sending. This message is $minutesOld minutes old.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Enter edit mode
    setState(() {
      _editingMessage = message;
      _messageController.text = message.content;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  Future<void> _saveEditedMessage() async {
    if (_editingMessage == null || _messageController.text.trim().isEmpty) {
      return;
    }

    final newContent = _messageController.text.trim();
    final messageToEdit = _editingMessage!;

    try {
      // Call ChatStateManager to edit message
      final chatStateManager = context.read<ChatStateManager>();
      await chatStateManager.editMessage(messageToEdit.id, newContent);

      // Invalidate cache after editing message
      _invalidateMessageCache();

      // Exit edit mode
      setState(() {
        _editingMessage = null;
        _messageController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Message updated'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error editing message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to edit message: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
