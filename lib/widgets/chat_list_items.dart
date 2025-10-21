import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/chat_state_manager.dart';
import 'online_indicator.dart';

class OptimizedChatListItem extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;

  const OptimizedChatListItem({
    super.key,
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ChatStateManager, String>(
      selector: (context, chatManager) => chatManager.getCurrentUserIdForUI(),
      builder: (context, currentUserId, child) => _buildChatItem(context, currentUserId),
    );
  }

  Widget _buildChatItem(BuildContext context, String currentUserId) {
    final displayName = _getSafeDisplayName(chat, currentUserId);
    final displayImage = chat.getDisplayImage(currentUserId);
    final hasUnreadMessages = chat.hasUnreadMessages;
    final lastActivity = chat.lastActivity;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: hasUnreadMessages ? Colors.grey.withValues(alpha: 0.05) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAvatar(displayName, displayImage, currentUserId),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: _buildLastMessageRow(chat, hasUnreadMessages, currentUserId),
        trailing: _buildTrailing(lastActivity, hasUnreadMessages, chat.unreadCount),
        onTap: onTap,
      ),
    );
  }

  Widget _buildAvatar(String displayName, String? displayImage, String currentUserId) {
    if (chat.isDirectChat) {
      final otherUserId = chat.getOtherUserId(currentUserId);
      if (otherUserId != null) {
        return PresenceAwareAvatar(
          userId: otherUserId,
          imageUrl: displayImage,
          displayName: displayName,
          radius: 20.0,
          showIndicator: true,
          showPulse: true,
          backgroundColor: AppColors.primary,
        );
      }
    }
    
    return CircleAvatar(
      backgroundColor: AppColors.primary,
      child: displayImage != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: displayImage,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 40,
                  height: 40,
                  color: Colors.grey[300],
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => _buildAvatarText(displayName),
                fadeInDuration: const Duration(milliseconds: 200),
                fadeOutDuration: const Duration(milliseconds: 100),
                memCacheWidth: 80,
                memCacheHeight: 80,
              ),
            )
          : _buildAvatarText(displayName),
    );
  }

  Widget _buildAvatarText(String displayName) {
    return Text(
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTrailing(DateTime lastActivity, bool hasUnreadMessages, int unreadCount) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _formatTime(lastActivity),
          style: TextStyle(
            fontSize: 12,
            color: hasUnreadMessages ? AppColors.primary : Colors.grey[600],
            fontWeight: hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (hasUnreadMessages) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              unreadCount.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLastMessageRow(Chat chat, bool hasUnreadMessages, String currentUserId) {
    return Consumer<ChatStateManager>(
      builder: (context, chatManager, child) {
        if (chat.isDirectChat) {
          final otherUserId = chat.getOtherUserId(currentUserId);
          if (otherUserId != null && chatManager.isUserOnline(otherUserId)) {
            return Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'online',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            );
          }
        }
        return _buildMessageContent(chat.lastMessage, hasUnreadMessages);
      },
    );
  }

  Widget _buildMessageContent(Message? lastMessage, bool hasUnreadMessages) {
    if (lastMessage == null) {
      return Text(
        'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
          fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
        ),
      );
    }

    final messageData = _getMessageData(lastMessage);
    
    return Row(
      children: [
        if (messageData.icon != null) ...[
          Icon(
            messageData.icon,
            size: 16,
            color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            messageData.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
              fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  _MessageData _getMessageData(Message message) {
    switch (message.type) {
      case MessageType.image:
        return _MessageData(Icons.photo, 'Photo');
      case MessageType.video:
        return _MessageData(Icons.videocam, 'Video');
      case MessageType.audio:
        return _MessageData(Icons.mic, 'Voice message');
      case MessageType.file:
        return _MessageData(Icons.attach_file, 'File');
      case MessageType.text:
        return _MessageData(null, message.content);
    }
  }

  String _getSafeDisplayName(Chat chat, String currentUserId) {
    try {
      return chat.getDisplayName(currentUserId);
    } catch (e) {
      debugPrint('Error getting display name for chat ${chat.id}: $e');
      return chat.name.isNotEmpty ? chat.name : 'New Chat';
    }
  }

  String _formatTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inDays > 0) return '${difference.inDays}d';
    if (difference.inHours > 0) return '${difference.inHours}h';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m';
    return 'now';
  }
}

class _MessageData {
  final IconData? icon;
  final String text;
  
  _MessageData(this.icon, this.text);
}