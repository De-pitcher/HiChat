import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/chat.dart';
import '../../models/user.dart';
import '../../services/auth_state_manager.dart';
import '../../widgets/online_indicator.dart';
import '../../widgets/loading_overlay.dart';

class ChatInfoScreen extends StatefulWidget {
  final Chat chat;

  const ChatInfoScreen({
    super.key,
    required this.chat,
  });

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  bool _isLoading = false;
  bool _isMuted = false; // TODO: Get from chat settings
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // TODO: Load chat settings to check if muted
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authManager = Provider.of<AuthStateManager>(context);
    final currentUser = authManager.currentUser;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Chat Info',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Chat Header
              _buildChatHeader(theme, currentUser),
              
              // Error Message
              if (_errorMessage != null) _buildErrorMessage(theme),
              
              // Participants Section
              _buildParticipantsSection(theme, currentUser),
              
              // Shared Media Section
              _buildSharedMediaSection(theme),
              
              // Chat Settings Section
              _buildChatSettingsSection(theme),
              
              // Danger Zone Section
              _buildDangerZoneSection(theme),
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatHeader(ThemeData theme, User? currentUser) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        children: [
          // Chat Image
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                width: 3,
              ),
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: theme.colorScheme.surface,
              backgroundImage: _getChatImage(),
              child: _getChatImage() == null
                  ? Icon(
                      widget.chat.isGroupChat ? Icons.group : Icons.person_outline,
                      size: 60,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    )
                  : null,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Chat Name
          Text(
            widget.chat.name,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          // Chat Description/Status
          _buildChatDescription(theme, currentUser),
        ],
      ),
    );
  }

  ImageProvider? _getChatImage() {
    if (widget.chat.isGroupChat && widget.chat.groupImageUrl?.isNotEmpty == true) {
      return CachedNetworkImageProvider(widget.chat.groupImageUrl!);
    } else if (widget.chat.isDirectChat) {
      final authManager = context.read<AuthStateManager>();
      final otherUser = widget.chat.getOtherUser(authManager.currentUser?.id);
      if (otherUser?.profileImageUrl?.isNotEmpty == true) {
        return CachedNetworkImageProvider(otherUser!.profileImageUrl!);
      }
    }
    return null;
  }

  Widget _buildChatDescription(ThemeData theme, User? currentUser) {
    if (widget.chat.isGroupChat) {
      return Column(
        children: [
          if (widget.chat.description?.isNotEmpty == true) ...[
            Text(
              widget.chat.description!,
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            '${widget.chat.participants.length} participants',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      );
    } else {
      // Direct chat - show other user's status
      final otherUser = widget.chat.getOtherUser(currentUser?.id);
      if (otherUser != null) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OnlineIndicator(
              isOnline: otherUser.isOnline,
              size: 12,
            ),
            const SizedBox(width: 8),
            Text(
              otherUser.isOnline 
                  ? 'Online' 
                  : 'Last seen ${_formatLastSeen(otherUser.lastSeen)}',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        );
      }
    }
    return const SizedBox.shrink();
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'recently';
    
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return 'long time ago';
    }
  }

  Widget _buildErrorMessage(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection(ThemeData theme, User? currentUser) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.people_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.chat.isGroupChat ? 'Participants' : 'Participant',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.chat.participants.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Participants list
          ...widget.chat.participants.map((user) => _buildParticipantTile(theme, user, currentUser)),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(ThemeData theme, User user, User? currentUser) {
    final isCurrentUser = user.id == currentUser?.id;
    
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.surface,
            backgroundImage: user.profileImageUrl?.isNotEmpty == true
                ? CachedNetworkImageProvider(user.profileImageUrl!)
                : null,
            child: user.profileImageUrl?.isEmpty != false
                ? Icon(
                    Icons.person_outline,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )
                : null,
          ),
          if (!isCurrentUser)
            Positioned(
              bottom: 0,
              right: 0,
              child: OnlineIndicator(
                isOnline: user.isOnline,
                size: 12,
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              user.username,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (isCurrentUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      subtitle: user.about?.isNotEmpty == true
          ? Text(
              user.about!,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: isCurrentUser ? null : () {
        // TODO: Navigate to user profile or start direct chat
      },
    );
  }

  Widget _buildSharedMediaSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.photo_library_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'Shared Media',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            onTap: () {
              // TODO: Navigate to shared media screen
              _showComingSoon(context, 'Shared Media');
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.attach_file_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'Shared Files',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            onTap: () {
              // TODO: Navigate to shared files screen
              _showComingSoon(context, 'Shared Files');
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.link_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'Shared Links',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            onTap: () {
              // TODO: Navigate to shared links screen
              _showComingSoon(context, 'Shared Links');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatSettingsSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              _isMuted ? Icons.notifications_off_outlined : Icons.notifications_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'Mute Notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              _isMuted ? 'You won\'t receive notifications' : 'Receive all notifications',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            value: _isMuted,
            activeColor: theme.colorScheme.primary,
            onChanged: _toggleMute,
          ),
          if (widget.chat.isGroupChat) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                'Edit Group',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Change group name, photo and description',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              onTap: () {
                // TODO: Navigate to edit group screen
                _showComingSoon(context, 'Edit Group');
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDangerZoneSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.orange.shade600,
            ),
            title: Text(
              'Clear Chat History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade600,
              ),
            ),
            subtitle: Text(
              'Delete all messages in this chat',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            onTap: () => _showClearChatDialog(context),
          ),
          if (widget.chat.isDirectChat) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.block_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Block User',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
              subtitle: Text(
                'Block and delete this chat',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              onTap: () => _showBlockUserDialog(context),
            ),
          ] else ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.exit_to_app_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Leave Group',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
              subtitle: Text(
                'Leave this group chat',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              onTap: () => _showLeaveGroupDialog(context),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleMute(bool value) {
    setState(() {
      _isMuted = value;
    });
    
    // TODO: Implement mute/unmute functionality with backend
    final action = value ? 'muted' : 'unmuted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Chat $action'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feature),
        content: Text('$feature feature is coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showClearChatDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat History'),
        content: const Text(
          'Are you sure you want to delete all messages in this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearChatHistory();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showBlockUserDialog(BuildContext context) {
    final authManager = context.read<AuthStateManager>();
    final otherUser = widget.chat.getOtherUser(authManager.currentUser?.id);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${otherUser?.username ?? 'this user'}? They won\'t be able to send you messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _blockUser();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text(
          'Are you sure you want to leave "${widget.chat.name}"? You won\'t receive any more messages from this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _leaveGroup();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _clearChatHistory() {
    setState(() {
      _isLoading = true;
    });

    // TODO: Implement clear chat history with backend
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat history cleared'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Navigate back to chat list
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  void _blockUser() {
    setState(() {
      _isLoading = true;
    });

    // TODO: Implement block user with backend
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User blocked'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Navigate back to chat list
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  void _leaveGroup() {
    setState(() {
      _isLoading = true;
    });

    // TODO: Implement leave group with backend
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Left group'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Navigate back to chat list
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }
}