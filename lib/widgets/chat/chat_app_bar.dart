// widgets/chat/chat_app_bar.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/chat.dart';
import '../../services/chat_state_manager.dart';
import '../../services/call_signaling_service.dart';
import '../../constants/app_theme.dart';
import '../../screens/calls/outgoing_call_screen.dart';
import '../online_indicator.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Chat chat;
  final VoidCallback onBackPressed;
  final VoidCallback onChatInfoPressed;
  final VoidCallback onTestReply;

  const ChatAppBar({
    super.key,
    required this.chat,
    required this.onBackPressed,
    required this.onChatInfoPressed,
    required this.onTestReply,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final chatStateManager = context.read<ChatStateManager>();
    final currentUserId = chatStateManager.getCurrentUserIdForUI();

    return AppBar(
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
          onPressed: onBackPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
      title: _buildTitle(context, currentUserId),
      actions: _buildActions(context),
    );
  }

  Widget _buildTitle(BuildContext context, String currentUserId) {
    return Row(
      children: [
        // Presence-aware avatar for direct chats
        chat.isDirectChat
            ? PresenceAwareAvatar(
                userId: chat.getOtherUserId(currentUserId) ?? '',
                imageUrl: chat.getDisplayImage(currentUserId),
                displayName: chat.getDisplayName(currentUserId),
                radius: 20.0,
                showIndicator: chat.getOtherUserId(currentUserId) != null,
                showPulse: true,
                backgroundColor: AppColors.primary,
              )
            : _buildGroupAvatar(currentUserId),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chat.getDisplayName(currentUserId),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              _buildSubtitle(context, currentUserId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupAvatar(String currentUserId) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primary,
      child: chat.getDisplayImage(currentUserId) != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: chat.getDisplayImage(currentUserId)!,
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
                  chat.getDisplayName(currentUserId)[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                memCacheWidth: 80,
                memCacheHeight: 80,
              ),
            )
          : Text(
              chat.getDisplayName(currentUserId)[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildSubtitle(BuildContext context, String currentUserId) {
    if (chat.isDirectChat) {
      return Consumer<ChatStateManager>(
        builder: (context, chatManager, child) {
          final otherUserId = chat.getOtherUserId(currentUserId);
          if (otherUserId == null) return const SizedBox.shrink();

          final isOnline = chatManager.isUserOnline(otherUserId);
          final userPresence = chatManager.getUserPresence(otherUserId);

          if (isOnline) {
            return Row(
              mainAxisSize: MainAxisSize.min,
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
                Text(
                  'online',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }

          if (userPresence?.displayStatus != null &&
              userPresence?.displayStatus != 'offline') {
            return Text(
              userPresence!.displayStatus,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            );
          }

          return Selector<ChatStateManager, bool>(
            selector: (context, chatStateManager) => chatStateManager.isConnected,
            builder: (context, isConnected, child) {
              return Text(
                isConnected ? 'offline' : 'Connecting...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isConnected ? Colors.grey[600] : Colors.orange,
                ),
              );
            },
          );
        },
      );
    } else {
      return Text(
        '${chat.participantIds.length} members',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.grey[600],
        ),
      );
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      // Debug button for testing reply functionality
      IconButton(
        icon: const Icon(Icons.reply, color: Colors.orange),
        onPressed: onTestReply,
      ),
      IconButton(
        icon: const Icon(Icons.call),
        onPressed: () => _initiateCall(context, isVideoCall: false),
      ),
      IconButton(
        icon: const Icon(Icons.videocam),
        onPressed: () => _initiateCall(context, isVideoCall: true),
      ),
      PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'info':
              onChatInfoPressed();
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
    ];
  }

  /// Initiate a call with the chat user
  void _initiateCall(BuildContext context, {required bool isVideoCall}) async {
    try {
      debugPrint(
          '📞 ChatAppBar: Initiating ${isVideoCall ? 'video' : 'voice'} call with ${chat.name}');

      final signalingService = CallSignalingService();
      final channelName = 'call_${chat.id}_${DateTime.now().millisecondsSinceEpoch}';
      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}_${chat.id}';

      debugPrint('📞 ChatAppBar: Created call - ID: $callId, Channel: $channelName');

      // Navigate to outgoing call screen FIRST (so it can listen for responses)
      if (context.mounted) {
        debugPrint('📞 ChatAppBar: Navigating to OutgoingCallScreen...');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OutgoingCallScreen(
              channelName: channelName,
              remoteUserName: chat.name,
              remoteUserId: chat.id.toString(),
              isVideoCall: isVideoCall,
              callId: callId,
            ),
          ),
        );
        debugPrint('📞 ChatAppBar: Navigation initiated');
      }

      // THEN send call invitation (screen is already listening)
      debugPrint('📞 ChatAppBar: Sending call invitation...');
      await signalingService.sendCallInvitation(
        callId: callId,
        toUserId: chat.id,
        toUserName: chat.name,
        channelName: channelName,
        isVideoCall: isVideoCall,
      );
      debugPrint('📞 ChatAppBar: Call invitation sent successfully');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Calling ${chat.name}... (${isVideoCall ? 'video' : 'voice'} call)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ ChatAppBar: Error initiating call: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}