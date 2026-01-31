import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../models/reply_message.dart';

/// Widget that displays the reply preview bar above the text input
class ReplyInputBar extends StatelessWidget {
  final Message replyToMessage;
  final VoidCallback onCancel;

  const ReplyInputBar({
    super.key,
    required this.replyToMessage,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        border: Border(
          left: BorderSide(
            color: theme.primaryColor,
            width: 4,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Reply icon
          Icon(
            Icons.reply,
            size: 18,
            color: theme.primaryColor,
          ),
          const SizedBox(width: 8),
          
          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sender name
                Text(
                  'Replying to ${_getSenderName()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                
                // Message preview
                Text(
                  _getMessagePreview(),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Cancel button
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  String _getSenderName() {
    if (replyToMessage.replyToMessage != null) {
      return replyToMessage.replyToMessage!.sender.username;
    }
    return replyToMessage.senderUsername ?? 'Unknown';
  }

  String _getMessagePreview() {
    // If there's a ReplyMessage object, use its display text
    if (replyToMessage.replyToMessage != null) {
      return replyToMessage.replyToMessage!.displayText;
    }
    
    // Otherwise, create preview based on message type
    switch (replyToMessage.type) {
      case MessageType.image:
        return '📷 Image';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.audio:
        return '🎵 Audio';
      case MessageType.file:
        return '📎 File';
      case MessageType.call:
        return '📞 Call';
      case MessageType.text:
        final content = replyToMessage.content.trim();
        if (content.isEmpty) return 'Message';
        return content.length > 50 
            ? '${content.substring(0, 50)}...' 
            : content;
    }
  }
}

/// A compact version of the reply bar that shows just the preview
class CompactReplyBar extends StatelessWidget {
  final ReplyMessage replyMessage;
  final bool showBorder;

  const CompactReplyBar({
    super.key,
    required this.replyMessage,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[700] : Colors.grey[50],
        border: showBorder ? Border(
          left: BorderSide(
            color: theme.primaryColor,
            width: 3,
          ),
        ) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.reply,
            size: 14,
            color: theme.primaryColor,
          ),
          const SizedBox(width: 6),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  replyMessage.sender.username,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryColor,
                  ),
                ),
                const SizedBox(height: 1),
                
                Text(
                  replyMessage.displayText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}