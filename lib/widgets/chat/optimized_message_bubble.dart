import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/chat_state_manager.dart';
import '../../services/local_media_cache_service.dart';
import '../../widgets/chat/image_message_card_enhanced.dart';
import '../../widgets/chat/audio_message_card.dart';

class OptimizedMessageBubble extends StatelessWidget {
  final Message message;
  final bool isCurrentUser;
  final Chat chat;
  final Function(Message)? onRetry;
  final Function(Message)? onEdit;
  final Function(Message)? onReply;
  final Function(String)? onScrollToMessage;
  final bool isHighlighted;

  const OptimizedMessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.chat,
    this.onRetry,
    this.onEdit,
    this.onReply,
    this.onScrollToMessage,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Swipe right to reply (for left-aligned messages) or
          // Swipe left to reply (for right-aligned messages)
          final velocity = details.primaryVelocity ?? 0;
          final threshold = 300.0; // Minimum swipe velocity
          
          debugPrint('📱 Swipe detected: velocity=$velocity, isCurrentUser=$isCurrentUser');
          
          if (isCurrentUser && velocity < -threshold) {
            // Right-aligned message swiped left
            debugPrint('👈 Swiped left on current user message');
            onReply?.call(message);
          } else if (!isCurrentUser && velocity > threshold) {
            // Left-aligned message swiped right
            debugPrint('👉 Swiped right on other user message');
            onReply?.call(message);
          } else {
            debugPrint('🚫 Swipe velocity too low or wrong direction');
          }
        },
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
                onLongPress: () =>
                    _showMessageOptions(context, message, isCurrentUser),
                child: (message.isImage || message.isVideo || message.isAudio)
                    ? message.isAudio
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.7,
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
                          color: isCurrentUser 
                              ? null 
                              : isHighlighted 
                                  ? Colors.amber.withValues(alpha: 0.3)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isCurrentUser ? 20 : 4),
                            bottomRight: Radius.circular(
                              isCurrentUser ? 4 : 20,
                            ),
                          ),
                          border: isHighlighted
                              ? Border.all(
                                  color: Colors.amber.withValues(alpha: 0.8),
                                  width: 2,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: isHighlighted 
                                  ? Colors.amber.withValues(alpha: 0.3)
                                  : isCurrentUser
                                      ? AppColors.primary.withValues(alpha: 0.2)
                                      : Colors.black.withValues(alpha: 0.05),
                              blurRadius: isHighlighted ? 12 : 8,
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
      ),
    );
  }

  Widget _buildOptimizedAvatar(BuildContext context) {
    final currentUserId = context
        .read<ChatStateManager>()
        .getCurrentUserIdForUI();
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
    // Get actual sender name from participants
    try {
      final sender = chat.participants.firstWhere(
        (participant) => participant.id.toString() == message.senderId,
      );
      return sender.username;
    } catch (e) {
      // Fallback if sender not found in participants
      return 'Unknown User';
    }
  }

  String _getReplyDisplayText() {
    final replyMessage = message.replyToMessage;
    if (replyMessage != null) {
      return replyMessage.displayText;
    }
    
    // If we only have the reply ID, show a generic message
    return 'Tap to view original message';
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
        // Reply context display
        if (message.isReply)
          _buildReplyContext(context),
          
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
              ] else
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(_getStatusIcon(), size: 16, color: _getStatusColor()),
                ),
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
    // For current user messages (blue background), use light colors
    // For other user messages (light grey background), use darker colors
    if (isCurrentUser) {
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
          return Colors.lightBlue[100]!;
        case MessageStatus.failed:
          return Colors.red[300]!;
      }
    } else {
      // Other user messages - use darker colors for better visibility on light background
      switch (message.status) {
        case MessageStatus.pending:
          return Colors.grey[600]!;
        case MessageStatus.sending:
          return Colors.grey[600]!;
        case MessageStatus.sent:
          return Colors.grey[600]!;
        case MessageStatus.delivered:
          return Colors.blue[600]!;
        case MessageStatus.read:
          return Colors.blue[700]!;
        case MessageStatus.failed:
          return Colors.red[600]!;
      }
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

  void _showMessageOptions(
    BuildContext context,
    Message message,
    bool isCurrentUser,
  ) {
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
      debugPrint(
        '📝 Message ${message.id} is $minutesOld minutes old - edit disabled (limit: 10 minutes)',
      );
    }

    return canEdit;
  }

  void _replyToMessage(BuildContext context, Message message) {
    // Reply button tapped
    // Use the onReply callback directly instead of finding ancestor state
    if (onReply != null) {
      debugPrint('📞 Calling onReply callback');
      onReply?.call(message);
    } else {
      debugPrint('❌ onReply callback is null!');
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
    final chatStateManager = Provider.of<ChatStateManager>(
      context,
      listen: false,
    );
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
        final CachedNetworkImageProvider imageProvider =
            CachedNetworkImageProvider(fileUrl);
        await imageProvider.evict();
        // Image cache cleared
      }

      // For locally cached media (audio, video, images), use LocalMediaCacheService
      if (message.isAudio || message.isVideo || message.isImage) {
        try {
          // The message content might contain a timestamp used as cache key
          final timestamp = message.content;
          if (timestamp.isNotEmpty) {
            final LocalMediaCacheService cacheService =
                LocalMediaCacheService();
            await cacheService.initialize();

            // Get cached media metadata to check if it exists
            final metadata = cacheService.getMediaMetadata(timestamp);
            if (metadata != null) {
              // Delete the actual cached file
              final cachedFile = File(metadata.localPath);
              if (await cachedFile.exists()) {
                await cachedFile.delete();
                // Cached file deleted
              }

              // Delete thumbnail if it exists (for videos)
              if (metadata.thumbnailPath != null) {
                final thumbnailFile = File(metadata.thumbnailPath!);
                if (await thumbnailFile.exists()) {
                  await thumbnailFile.delete();
                  debugPrint(
                    '🗑️ Deleted thumbnail: ${metadata.thumbnailPath}',
                  );
                }
              }

              debugPrint(
                '🗑️ Cleaned up local cache for ${message.type}: $timestamp',
              );
            } else {
              debugPrint(
                'ℹ️ No local cache metadata found for ${message.type}: $timestamp',
              );
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

  Widget _buildReplyContext(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Check if this message is a reply (has either full context or just ID)
    final replyMessage = message.replyToMessage;
    final replyToMessageId = message.replyToMessageId;
    
    if (replyMessage == null && replyToMessageId == null) {
      return const SizedBox.shrink();
    }

    // Determine what ID to use for scrolling
    final scrollToId = replyMessage?.id ?? replyToMessageId!;
    
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: GestureDetector(
        onTap: () {
          // Scrolling to replied message
          onScrollToMessage?.call(scrollToId);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark 
              ? Colors.grey[800]?.withValues(alpha: 0.5)
              : Colors.grey[200]?.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: const Color(0xFF007AFF), // iOS blue
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.reply,
                size: 14,
                color: const Color(0xFF007AFF),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        replyMessage?.sender.username ?? 'Unknown User',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_upward,
                        size: 10,
                        color: const Color(0xFF007AFF),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getReplyDisplayText(),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
