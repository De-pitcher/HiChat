import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/chat_state_manager.dart';
import '../../services/auth_state_manager.dart';
import '../../services/native_camera_service.dart';
import '../../services/audio_recording_service.dart';
import '../../services/local_media_cache_service.dart';

import '../../widgets/chat/image_message_card_enhanced.dart';
import '../../widgets/chat/audio_message_card.dart';
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
    return Object.hashAll(messages.map((m) => Object.hash(m.id, m.content, m.status, m.timestamp)));
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
  final ScrollController _scrollController = ScrollController();
  
  // Edit mode state
  Message? _editingMessage;
  bool get _isEditMode => _editingMessage != null;
  
  // Read receipts tracking
  Timer? _readReceiptsTimer;
  
  // Auto retry for failed messages
  Timer? _autoRetryTimer;
  
  // Note: Floating date indicator variables can be added here for future enhancement

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupReadReceipts();
    _setupAutoRetry();
  }

  @override
  void dispose() {
    _readReceiptsTimer?.cancel();
    _autoRetryTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final chatStateManager = context.read<ChatStateManager>();
    await chatStateManager.loadMessagesForChat(widget.chat.id);

    // Scroll to bottom after messages load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _setupReadReceipts() {
    // Set up periodic timer to check for unread messages in viewport
    _readReceiptsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _markVisibleMessagesAsRead();
    });

    // Also check when scroll position changes
    _scrollController.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    // Mark messages as read when scrolling stops (debounced)
    _readReceiptsTimer?.cancel();
    _readReceiptsTimer = Timer(const Duration(milliseconds: 500), () {
      _markVisibleMessagesAsRead();
    });
  }

  void _markVisibleMessagesAsRead() {
    try {
      final chatStateManager = Provider.of<ChatStateManager>(context, listen: false);
      final authManager = Provider.of<AuthStateManager>(context, listen: false);
      final currentUserId = authManager.currentUser?.id.toString();
      
      if (currentUserId == null) return;

      final messages = chatStateManager.getMessagesForChat(widget.chat.id);
      final unreadMessages = messages
          .where((message) => 
              message.senderId != currentUserId && // Not sent by current user
              !message.isRead && // Not already read
              _isMessageVisible(message))
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
    // For now, assume messages are visible if we've scrolled past them
    // This could be enhanced with more precise viewport detection
    return _scrollController.hasClients;
  }

  void _setupAutoRetry() {
    // Set up periodic timer to check for failed messages and retry them automatically
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _autoRetryFailedMessages();
    });
  }

  void _autoRetryFailedMessages() {
    try {
      final chatStateManager = Provider.of<ChatStateManager>(context, listen: false);
      final messages = chatStateManager.getMessagesForChat(widget.chat.id);
      
      final failedMessages = messages
          .where((message) => 
              message.isFailed && 
              _shouldRetryMessage(message))
          .toList();

      for (final message in failedMessages) {
        final retryCount = message.metadata?['retry_count'] ?? 0;
        if (retryCount < 3) { // Max 3 automatic retries
          debugPrint('🔄 Auto-retrying failed message: ${message.id} (attempt ${retryCount + 1})');
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

    _messageController.clear();
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
      );

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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Use jumpTo for better performance when scrolling distance is large
        final maxExtent = _scrollController.position.maxScrollExtent;
        final currentPosition = _scrollController.position.pixels;
        final shouldAnimate = (maxExtent - currentPosition) < 1000; // Only animate for small distances
        
        if (shouldAnimate) {
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(maxExtent);
        }
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final chatStateManager = context.read<ChatStateManager>();
    final currentUserId = chatStateManager.getCurrentUserIdForUI();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              size: 18,
              color: Theme.of(context).iconTheme.color,
            ),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary,
              child: widget.chat.getDisplayImage(currentUserId) != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: widget.chat.getDisplayImage(currentUserId)!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 40,
                          height: 40,
                          color: AppColors.primary.withValues(alpha: 0.1),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Text(
                          widget.chat
                              .getDisplayName(currentUserId)[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        memCacheWidth: 80, // Optimize memory usage
                        memCacheHeight: 80,
                      ),
                    )
                  : Text(
                      widget.chat
                          .getDisplayName(currentUserId)[0]
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.chat.getDisplayName(currentUserId),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.chat.isDirectChat) ...[
                    Selector<ChatStateManager, bool>(
                      selector: (context, chatStateManager) => chatStateManager.isConnected,
                      builder: (context, isConnected, child) {
                        return Text(
                          isConnected ? 'Online' : 'Connecting...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isConnected ? Colors.green : Colors.orange,
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    Text(
                      '${widget.chat.participantIds.length} members',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Debug button for testing queue functionality
          // IconButton(
          //   icon: const Icon(Icons.bug_report),
          //   onPressed: () {
          //     final chatStateManager = context.read<ChatStateManager>();
          //     chatStateManager.debugTestMessageQueue();
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(
          //         content: Text('🧪 Testing queue functionality - check logs'),
          //         duration: Duration(seconds: 2),
          //       ),
          //     );
          //   },
          // ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              // TODO: Implement voice call
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              // TODO: Implement video call
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'info':
                  // TODO: Show chat info
                  break;
                case 'mute':
                  // TODO: Mute chat
                  break;
                case 'clear':
                  // TODO: Clear chat history
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'info', child: Text('Chat info')),
              const PopupMenuItem(
                value: 'mute',
                child: Text('Mute notifications'),
              ),
              const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
            ],
          ),
        ],
      ),
      body: Container(
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
                    messages: chatStateManager.getMessagesForChat(widget.chat.id),
                    isLoading: chatStateManager.isLoading,
                    isConnected: chatStateManager.isConnected,
                  );
                  
                  debugPrint('🔄 Chat UI rebuilding - Message count: ${messagesState.messages.length}');
                  if (messagesState.isLoading && messagesState.messages.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 3),
                    );
                  }

                  if (messagesState.messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Send the first message to start the conversation!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                          if (!messagesState.isConnected) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Connecting...',
                              style: TextStyle(
                                color: Colors.orange[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  // Auto-scroll to bottom when messages are loaded
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (messagesState.messages.isNotEmpty) {
                      _scrollToBottom();
                    }
                  });

                  // Group messages by date and insert date separators
                  final groupedItems = date_utils.DateUtils.groupMessagesByDate(
                    messagesState.messages,
                  );

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    itemCount: groupedItems.length,
                    // Removed itemExtent to allow flexible heights for media messages
                    itemBuilder: (context, index) {
                      final item = groupedItems[index];

                      // Check if this is a date separator
                      if (item is date_utils.DateSeparatorItem) {
                        return RepaintBoundary(
                          child: DateSeparator(date: item.date),
                        );
                      }

                      // Otherwise it's a message
                      final message = item as Message;
                      final isCurrentUser = message.senderId == currentUserId;

                      return RepaintBoundary(
                        child: _OptimizedMessageBubble(
                          message: message,
                          isCurrentUser: isCurrentUser,
                          chat: widget.chat,
                          onRetry: _handleMessageRetry,
                          onEdit: _editMessage,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _MessageInput(
              controller: _messageController,
              onSend: _sendMessage,
              chat: widget.chat,
              onCameraPressed: _handleCameraResult,
              onGalleryPressed: _handleGallerySelection,
              isEditMode: _isEditMode,
              onCancelEdit: _cancelEdit,
              editingMessage: _editingMessage,
            ),
          ],
        ),
      ),
    );
  }

  // Message action methods
  void _setReplyToMessage(Message message) {
    // TODO: Implement reply functionality
    // For now, show a placeholder message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Replying to: "${message.content}"'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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
          content: Text('Messages can only be edited within 10 minutes of sending. This message is $minutesOld minutes old.'),
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
      await chatStateManager.editMessage(
        messageToEdit.id,
        newContent,
      );

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

class _OptimizedMessageBubble extends StatelessWidget {
  final Message message;
  final bool isCurrentUser;
  final Chat chat;
  final Function(Message)? onRetry;
  final Function(Message)? onEdit;

  const _OptimizedMessageBubble({
    required this.message,
    required this.isCurrentUser,
    required this.chat,
    this.onRetry,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: isCurrentUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[
            Container(
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              child: _buildOptimizedAvatar(context),
            ),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onLongPress: () => _showMessageOptions(context, message, isCurrentUser),
                child: (message.isImage ||
                    message.isVideo ||
                    message.isAudio)
                    ? message.isAudio 
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            child: _buildMessageContent(context),
                          )
                        : _buildMessageContent(context)
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: isCurrentUser
                              ? LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primary.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isCurrentUser ? null : Colors.grey[100],
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isCurrentUser ? 20 : 4),
                            bottomRight: Radius.circular(isCurrentUser ? 4 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isCurrentUser
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildMessageContent(context),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizedAvatar(BuildContext context) {
    final currentUserId = context.read<ChatStateManager>().getCurrentUserIdForUI();
    final displayImage = chat.getDisplayImage(currentUserId);
    
    if (displayImage != null) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: displayImage,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 32,
              height: 32,
              color: AppColors.primary.withValues(alpha: 0.1),
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Text(
              _getSenderName()[0].toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            memCacheWidth: 64, // Optimize memory usage
            memCacheHeight: 64,
          ),
        ),
      );
    }
    
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      child: Text(
        _getSenderName()[0].toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  String _getSenderName() {
    // TODO: Get actual sender name from participants
    return 'User';
  }

  /// Build message content based on message type
  Widget _buildMessageContent(BuildContext context) {
    // For image and video messages, use the enhanced media card
    if (message.isImage || message.isVideo) {
      return ImageMessageCard(
        message: message,
        isCurrentUser: isCurrentUser,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    // For audio messages, return standalone audio card
    if (message.isAudio) {
      return AudioMessageCard(
        message: message,
        isCurrentUser: isCurrentUser,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    // For text and other message types, use the regular content
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCurrentUser && chat.isGroupChat) ...[
          Text(
            _getSenderName(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
        ],

        // Message content
        if (message.isText) ...[
          Text(
            message.content,
            style: TextStyle(
              color: isCurrentUser ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.4,
              letterSpacing: 0.1,
            ),
          ),
        ] else if (message.isFile) ...[
          // File message placeholder
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.attach_file,
                  color: isCurrentUser ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: isCurrentUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Timestamp and status (only for non-media messages)
        if (!message.isImage && !message.isVideo) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrentUser
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (isCurrentUser) ...[
                const SizedBox(width: 6),
                message.status == MessageStatus.failed
                    ? GestureDetector(
                        onTap: () => _handleRetryMessage(context),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getStatusIcon(),
                            size: 16,
                            color: _getStatusColor(),
                          ),
                        ),
                      )
                    : Icon(
                        _getStatusIcon(),
                        size: 16,
                        color: _getStatusColor(),
                      ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  IconData _getStatusIcon() {
    switch (message.status) {
      case MessageStatus.pending:
        return Icons.schedule;
      case MessageStatus.sending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
      case MessageStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _getStatusColor() {
    switch (message.status) {
      case MessageStatus.pending:
        return Colors.white.withValues(alpha: 0.7);
      case MessageStatus.sending:
        return Colors.white.withValues(alpha: 0.7);
      case MessageStatus.sent:
        return Colors.white.withValues(alpha: 0.7);
      case MessageStatus.delivered:
        return Colors.white.withValues(alpha: 0.7);
      case MessageStatus.read:
        return Colors.lightBlue[200]!;
      case MessageStatus.failed:
        return Colors.red[300]!;
    }
  }

  void _handleRetryMessage(BuildContext context) {
    debugPrint('🔄 Retry button tapped for message: ${message.id}');

    // Show retry confirmation
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Retry Message'),
          content: Text('Retry sending this ${message.type.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onRetry?.call(message);
              },
              child: const Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  void _showMessageOptions(BuildContext context, Message message, bool isCurrentUser) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Copy action
            ListTile(
              leading: Icon(Icons.copy, color: theme.iconTheme.color),
              title: Text(
                'Copy',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
              onTap: () {
                Navigator.pop(context);
                _copyMessage(context, message);
              },
            ),

            // Reply action
            ListTile(
              leading: Icon(Icons.reply, color: theme.iconTheme.color),
              title: Text(
                'Reply',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
              onTap: () {
                Navigator.pop(context);
                _replyToMessage(context, message);
              },
            ),

            // Forward action
            ListTile(
              leading: Icon(Icons.forward, color: theme.iconTheme.color),
              title: Text(
                'Forward',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
              onTap: () {
                Navigator.pop(context);
                _forwardMessage(context, message);
              },
            ),

            // Show edit and delete only for current user's messages
            if (isCurrentUser) ...[
              // Edit option only for text messages within 10 minutes of creation
              if (message.type == MessageType.text && _canEditMessage(message))
                ListTile(
                  leading: Icon(Icons.edit, color: theme.iconTheme.color),
                  title: Text(
                    'Edit',
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit?.call(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(context, message);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _copyMessage(BuildContext context, Message message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message copied to clipboard'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Check if message can be edited (within 10 minutes of creation)
  bool _canEditMessage(Message message) {
    final now = DateTime.now();
    final messageAge = now.difference(message.timestamp);
    const editTimeLimit = Duration(minutes: 10);
    
    final canEdit = messageAge <= editTimeLimit;
    
    if (!canEdit) {
      final minutesOld = messageAge.inMinutes;
      debugPrint('📝 Message ${message.id} is $minutesOld minutes old - edit disabled (limit: 10 minutes)');
    }
    
    return canEdit;
  }

  void _replyToMessage(BuildContext context, Message message) {
    // Find the parent ChatScreen state to handle reply
    final chatScreenState = context.findAncestorStateOfType<_ChatScreenState>();
    if (chatScreenState != null) {
      chatScreenState._setReplyToMessage(message);
    }
  }

  void _forwardMessage(BuildContext context, Message message) {
    // Navigate to contact selection for forwarding
    Navigator.pushNamed(context, '/forward-message', arguments: message);
  }



  void _deleteMessage(BuildContext context, Message message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Message'),
          content: const Text('Are you sure you want to delete this message?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _performDeleteMessage(context, message);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _performDeleteMessage(BuildContext context, Message message) async {
    final chatStateManager = Provider.of<ChatStateManager>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    
    try {
      debugPrint('🗑️ Deleting message: ${message.id} (${message.type})');
      
      // If it's a media message, clean up cached files first
      if (message.isImage || message.isVideo || message.isAudio) {
        await _cleanupMediaCache(message);
      }
      
      // Send delete request via WebSocket and wait for response
      // The server will respond with 'message_deleted' event which will update the UI
      await chatStateManager.deleteMessage(message.id);
      
      // Show loading feedback while waiting for server response
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Deleting message...'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      
      // Note: The actual UI update will happen when the WebSocket receives 
      // the 'message_deleted' response from the server, which calls 
      // ChatStateManager.onMessageDeleted() and triggers notifyListeners()
      
    } catch (e) {
      debugPrint('❌ Error deleting message: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to delete message'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Clean up cached media files for deleted messages
  Future<void> _cleanupMediaCache(Message message) async {
    try {
      debugPrint('🧹 Cleaning up media cache for message: ${message.id}');
      
      // Get file URL from message metadata
      final fileUrl = message.fileUrl;
      
      // For cached_network_image, clear from cache if we have a URL
      if (message.isImage && fileUrl != null) {
        final CachedNetworkImageProvider imageProvider = CachedNetworkImageProvider(fileUrl);
        await imageProvider.evict();
        debugPrint('🖼️ Cleared image cache for: ${message.id}');
      }
      
      // For locally cached media (audio, video, images), use LocalMediaCacheService
      if (message.isAudio || message.isVideo || message.isImage) {
        try {
          // The message content might contain a timestamp used as cache key
          final timestamp = message.content;
          if (timestamp.isNotEmpty) {
            final LocalMediaCacheService cacheService = LocalMediaCacheService();
            await cacheService.initialize();
            
            // Get cached media metadata to check if it exists
            final metadata = cacheService.getMediaMetadata(timestamp);
            if (metadata != null) {
              // Delete the actual cached file
              final cachedFile = File(metadata.localPath);
              if (await cachedFile.exists()) {
                await cachedFile.delete();
                debugPrint('🗑️ Deleted cached file: ${metadata.localPath}');
              }
              
              // Delete thumbnail if it exists (for videos)
              if (metadata.thumbnailPath != null) {
                final thumbnailFile = File(metadata.thumbnailPath!);
                if (await thumbnailFile.exists()) {
                  await thumbnailFile.delete();
                  debugPrint('🗑️ Deleted thumbnail: ${metadata.thumbnailPath}');
                }
              }
              
              debugPrint('🗑️ Cleaned up local cache for ${message.type}: $timestamp');
            } else {
              debugPrint('ℹ️ No local cache metadata found for ${message.type}: $timestamp');
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error removing local media cache: $e');
        }
      }
      
    } catch (e) {
      debugPrint('⚠️ Error cleaning up media cache: $e');
      // Don't throw - cache cleanup failure shouldn't block message deletion
    }
  }
}

// Old _MessageBubble and _MessageBubbleState classes removed for performance optimization
// Now using _OptimizedMessageBubble (StatelessWidget) instead

class _MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onGalleryPressed;
  final Chat chat;
  final bool isEditMode;
  final VoidCallback? onCancelEdit;
  final Message? editingMessage;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.chat,
    this.onCameraPressed,
    this.onGalleryPressed,
    this.isEditMode = false,
    this.onCancelEdit,
    this.editingMessage,
  });

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput>
    with SingleTickerProviderStateMixin {
  bool _hasText = false;
  bool _isRecording = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late final AudioRecordingService _audioRecordingService;

  // Recording timer state
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  static const int maxRecordingSeconds = 300; // 5 minutes max

  @override
  void initState() {
    super.initState();
    _audioRecordingService = AudioRecordingService();
    widget.controller.addListener(_onTextChanged);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _animationController.dispose();
    _stopRecordingTimer();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
      if (hasText) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = Duration.zero;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration = Duration(
          seconds: _recordingDuration.inSeconds + 1,
        );
      });

      // Auto-stop recording at max duration
      if (_recordingDuration.inSeconds >= maxRecordingSeconds) {
        _stopRecording();
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingDuration = Duration.zero;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _sendAudioMessage(String audioFilePath) async {
    try {
      debugPrint('🎵 Sending audio message: $audioFilePath');

      final file = File(audioFilePath);
      if (!await file.exists()) {
        throw Exception('Audio file not found');
      }

      final duration = _recordingDuration;
      final chatStateManager = context.read<ChatStateManager>();

      await chatStateManager.sendAudioMessage(
        chatId: widget.chat.id,
        audioFilePath: audioFilePath,
        duration: duration,
        onUploadProgress: (progress) {
          debugPrint('🎵 Audio upload progress: ${(progress * 100).toInt()}%');
        },
      );

      debugPrint('✅ Audio message sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending audio message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send audio message: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _startRecording() async {
    // Check microphone permission
    final permission = await Permission.microphone.request();

    if (permission != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Microphone permission is required for voice messages',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    // Initialize audio recording
    final success = await _audioRecordingService.startRecording();

    if (success) {
      setState(() {
        _isRecording = true;
      });

      _animationController.repeat(reverse: true);
      _startRecordingTimer();

      // Listen to duration stream for UI updates
      _audioRecordingService.durationStream.listen((duration) {
        if (mounted) {
          setState(() {
            _recordingDuration = duration;
          });
        }
      });
    } else {
      debugPrint('❌ Failed to start recording');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to start recording. Please check microphone permissions.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      debugPrint('🎤 Stopping audio recording');
      final recordingPath = await _audioRecordingService.stopRecording();

      setState(() {
        _isRecording = false;
      });

      _animationController.stop();
      _animationController.reset();
      _stopRecordingTimer();

      if (recordingPath != null) {
        debugPrint('✅ Recording completed: $recordingPath');
        await _sendAudioMessage(recordingPath);
      } else {
        debugPrint('⚠️ Recording was empty or too short');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording was too short or failed'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      setState(() {
        _isRecording = false;
      });
      _animationController.stop();
      _animationController.reset();
      _stopRecordingTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    try {
      debugPrint('🎤 Cancelling audio recording');
      await _audioRecordingService.cancelRecording();

      setState(() {
        _isRecording = false;
      });

      _animationController.stop();
      _animationController.reset();
      _stopRecordingTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording cancelled'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error cancelling recording: $e');
      setState(() {
        _isRecording = false;
      });
      _animationController.stop();
      _animationController.reset();
      _stopRecordingTimer();
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Edit message indicator
                if (widget.isEditMode && widget.editingMessage != null)
                  _buildEditIndicator(),
                
                // Input area
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: _isRecording
                      ? _buildRecordingInterface()
                      : _buildNormalInterface(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditIndicator() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF2A2A2A) 
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF404040) 
              : const Color(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF25D366), // WhatsApp green
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.edit_rounded,
            size: 16,
            color: const Color(0xFF25D366),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF25D366),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.editingMessage!.content.length > 40
                      ? '${widget.editingMessage!.content.substring(0, 40)}...'
                      : widget.editingMessage!.content,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onCancelEdit,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalInterface() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [

        // Attachment button (hidden in edit mode)
        if (!widget.isEditMode)
          Container(
          margin: const EdgeInsets.only(right: 8, bottom: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showAttachmentOptions(context),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add,
                  size: 24,
                  color: Theme.of(
                    context,
                  ).iconTheme.color?.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),

        // Text input field with integrated emoji button
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, maxHeight: 120),
            child: TextField(
              controller: widget.controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                hintText: widget.isEditMode ? 'Edit message...' : 'Type a message...',
                hintStyle: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                suffixIcon: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: Icon(
                      Icons.emoji_emotions_outlined,
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withValues(alpha: 0.7),
                      size: 24,
                    ),
                    onPressed: () {
                      // TODO: Show emoji picker
                    },
                    splashRadius: 20,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    tooltip: 'Emoji',
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 56,
                  minHeight: 48,
                ),
              ),
              onSubmitted: (_) {
                if (_hasText) widget.onSend();
              },
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Send or Voice button
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: _hasText
              ? ScaleTransition(
                  scale: _scaleAnimation,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onSend,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        key: const ValueKey('send'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isEditMode ? Icons.check_rounded : Icons.send_rounded,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                )
              : AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRecording ? (1.0 + _animationController.value * 0.2) : 1.0,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _toggleRecording,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            key: const ValueKey('mic'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isRecording
                                  ? Colors.red
                                  : Theme.of(context).cardColor,
                              shape: BoxShape.circle,
                              boxShadow: _isRecording
                                  ? [
                                      BoxShadow(
                                        color: Colors.red.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop : Icons.mic,
                              size: 24,
                              color: _isRecording
                                  ? Colors.white
                                  : Theme.of(
                                      context,
                                    ).iconTheme.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingInterface() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Recording status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Recording indicator
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.8 + _animationController.value * 0.4,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Recording time
              Text(
                _formatDuration(_recordingDuration),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),

              const Spacer(),

              // Max duration indicator
              Text(
                'Max ${_formatDuration(Duration(seconds: maxRecordingSeconds))}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),

        // Recording controls
        Row(
          children: [
            // Cancel button
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _cancelRecording,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[300]!, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close, size: 20, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Stop and send button
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _stopRecording,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send, size: 20, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Send',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onCameraPressed?.call();
                  },
                ),
                _AttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onGalleryPressed?.call();
                  },
                ),
                _AttachmentOption(
                  icon: Icons.location_on,
                  label: 'Location',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Share location
                  },
                ),
                _AttachmentOption(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Pick document
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
