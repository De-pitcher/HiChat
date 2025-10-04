import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/chat_state_manager.dart';
import '../../services/auth_state_manager.dart';
import '../../services/native_camera_service.dart';
import '../../services/audio_recording_service.dart';

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

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Note: Floating date indicator variables can be added here for future enhancement

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
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

  /// Send text message
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

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
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
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
                      child: Image.network(
                        widget.chat.getDisplayImage(currentUserId)!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            widget.chat
                                .getDisplayName(currentUserId)[0]
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
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
                    Text(
                      'Online', // TODO: Get actual online status
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.green),
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
                  final messages = chatStateManager.getMessagesForChat(
                    widget.chat.id,
                  );
                  final isLoading = chatStateManager.isLoading;

                  if (isLoading && messages.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 3),
                    );
                  }

                  if (messages.isEmpty) {
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
                          if (!chatStateManager.isConnected) ...[
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
                    if (messages.isNotEmpty) {
                      _scrollToBottom();
                    }
                  });

                  // Group messages by date and insert date separators
                  final groupedItems = date_utils.DateUtils.groupMessagesByDate(
                    messages,
                  );

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    itemCount: groupedItems.length,
                    itemBuilder: (context, index) {
                      final item = groupedItems[index];

                      // Check if this is a date separator
                      if (item is date_utils.DateSeparatorItem) {
                        return DateSeparator(date: item.date);
                      }

                      // Otherwise it's a message
                      final message = item as Message;
                      final isCurrentUser = message.senderId == currentUserId;

                      return _MessageBubble(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        chat: widget.chat,
                        onRetry: _handleMessageRetry,
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
    // Pre-fill the message input with current content for editing
    _messageController.text = message.content;

    // TODO: Implement edit mode with different send behavior
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message editing not yet implemented'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final Message message;
  final bool isCurrentUser;
  final Chat chat;
  final Function(Message)? onRetry;

  const _MessageBubble({
    required this.message,
    required this.isCurrentUser,
    required this.chat,
    this.onRetry,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation =
        Tween<double>(
          begin: widget.isCurrentUser ? 30.0 : -30.0,
          end: 0.0,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Build message content based on message type
  Widget _buildMessageContent() {
    // For image and video messages, use the enhanced media card
    if (widget.message.isImage || widget.message.isVideo) {
      return ImageMessageCard(
        message: widget.message,
        isCurrentUser: widget.isCurrentUser,
        onRetry: widget.onRetry != null
            ? () => widget.onRetry!(widget.message)
            : null,
      );
    }

    // For audio messages, return standalone audio card
    if (widget.message.isAudio) {
      return AudioMessageCard(
        message: widget.message,
        isCurrentUser: widget.isCurrentUser,
        onRetry: widget.onRetry != null
            ? () => widget.onRetry!(widget.message)
            : null,
      );
    }

    // For text and other message types, use the regular content
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.isCurrentUser && widget.chat.isGroupChat) ...[
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
        if (widget.message.isText) ...[
          Text(
            widget.message.content,
            style: TextStyle(
              color: widget.isCurrentUser ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.4,
              letterSpacing: 0.1,
            ),
          ),
        ] else if (widget.message.isFile) ...[
          // File message placeholder
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isCurrentUser
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.attach_file,
                  color: widget.isCurrentUser ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.message.content,
                    style: TextStyle(
                      color: widget.isCurrentUser
                          ? Colors.white
                          : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Timestamp and status (only for non-media messages)
        if (!widget.message.isImage && !widget.message.isVideo) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(widget.message.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isCurrentUser
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (widget.isCurrentUser) ...[
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: widget.message.status == MessageStatus.failed
                      ? GestureDetector(
                          onTap: () => _handleRetryMessage(),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getStatusIcon(),
                              key: ValueKey(widget.message.status),
                              size: 16,
                              color: _getStatusColor(),
                            ),
                          ),
                        )
                      : Icon(
                          _getStatusIcon(),
                          key: ValueKey(widget.message.status),
                          size: 16,
                          color: _getStatusColor(),
                        ),
                ),
              ],
            ],
          ),
        ],
      
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_slideAnimation.value, 0),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: EdgeInsets.only(bottom: 8, left: 16, right: 16),
              child: Row(
                mainAxisAlignment: widget.isCurrentUser
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!widget.isCurrentUser) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 8, bottom: 4),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        child: Text(
                          _getSenderName()[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],

                  Flexible(
                    fit: FlexFit.loose,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onLongPress: () => _showMessageOptions(context),
                        // borderRadius: BorderRadius.circular(20),
                        child:
                            (widget.message.isImage ||
                                widget.message.isVideo ||
                                widget.message.isAudio)
                            ? _buildMessageContent()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: widget.isCurrentUser
                                      ? LinearGradient(
                                          colors: [
                                            AppColors.primary,
                                            AppColors.primary.withValues(
                                              alpha: 0.8,
                                            ),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: widget.isCurrentUser
                                      ? null
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: Radius.circular(
                                      widget.isCurrentUser ? 20 : 4,
                                    ),
                                    bottomRight: Radius.circular(
                                      widget.isCurrentUser ? 4 : 20,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.isCurrentUser
                                          ? AppColors.primary.withValues(
                                              alpha: 0.2,
                                            )
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: _buildMessageContent(),
                              ),
                      ),
                    ),
                  ),
                
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMessageOptions(BuildContext context) {
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
                _copyMessage();
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
                _replyToMessage();
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
                _forwardMessage();
              },
            ),

            // Show edit and delete only for current user's messages
            if (widget.isCurrentUser) ...[
              ListTile(
                leading: Icon(Icons.edit, color: theme.iconTheme.color),
                title: Text(
                  'Edit',
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _editMessage();
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
                  _deleteMessage();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getSenderName() {
    // TODO: Get actual sender name from participants
    return 'User';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  IconData _getStatusIcon() {
    switch (widget.message.status) {
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
    switch (widget.message.status) {
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

  void _handleRetryMessage() {
    debugPrint('🔄 Retry button tapped for message: ${widget.message.id}');

    // Show retry confirmation
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Retry Message'),
          content: Text('Retry sending this ${widget.message.type.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onRetry?.call(widget.message);
              },
              child: const Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message copied to clipboard'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _replyToMessage() {
    // Find the parent ChatScreen state to handle reply
    final chatScreenState = context.findAncestorStateOfType<_ChatScreenState>();
    if (chatScreenState != null) {
      chatScreenState._setReplyToMessage(widget.message);
    }
  }

  void _forwardMessage() {
    // Navigate to contact selection for forwarding
    Navigator.pushNamed(context, '/forward-message', arguments: widget.message);
  }

  void _editMessage() {
    // Find the parent ChatScreen state to handle editing
    final chatScreenState = context.findAncestorStateOfType<_ChatScreenState>();
    if (chatScreenState != null) {
      chatScreenState._editMessage(widget.message);
    }
  }

  void _deleteMessage() {
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
                _performDeleteMessage();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _performDeleteMessage() {
    // TODO: Implement actual delete functionality
    // final chatStateManager = context.read<ChatStateManager>();
    // chatStateManager.deleteMessage(widget.message.chatId, widget.message.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message deletion not yet implemented'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onGalleryPressed;
  final Chat chat;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.chat,
    this.onCameraPressed,
    this.onGalleryPressed,
  });

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput>
    with TickerProviderStateMixin {
  bool _hasText = false;
  bool _isRecording = false;
  late AnimationController _animationController;
  late AnimationController _micAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _micPulseAnimation;
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

    _micAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _micPulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _animationController.dispose();
    _micAnimationController.dispose();
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

      _micAnimationController.repeat(reverse: true);
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

      _micAnimationController.stop();
      _micAnimationController.reset();
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
      _micAnimationController.stop();
      _micAnimationController.reset();
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

      _micAnimationController.stop();
      _micAnimationController.reset();
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
      _micAnimationController.stop();
      _micAnimationController.reset();
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
            child: _isRecording
                ? _buildRecordingInterface()
                : _buildNormalInterface(),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalInterface() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Attachment button
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
                hintText: 'Type a message...',
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
                        child: const Icon(
                          Icons.send_rounded,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                )
              : AnimatedBuilder(
                  animation: _micPulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRecording ? _micPulseAnimation.value : 1.0,
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
                  animation: _micAnimationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.8 + (_micPulseAnimation.value - 1.0) * 0.2,
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
