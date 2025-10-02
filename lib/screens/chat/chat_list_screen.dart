import 'package:flutter/material.dart';
import 'package:hichat_app/constants/app_constants.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/auth_state_manager.dart';
import '../../services/chat_state_manager.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    // ChatStateManager is automatically initialized via AuthStateManager
    // No need to manually load chats here
  }
  
  Future<void> _refreshChats() async {
    final chatStateManager = context.read<ChatStateManager>();
    
    try {
      debugPrint('ChatListScreen: Starting refresh...');
      // Use the new refresh method that properly manages loading states
      await chatStateManager.refreshChats();
      
      // Show success feedback only if no error occurred
      if (mounted && !chatStateManager.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Chats refreshed successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      // Error handling is already done in ChatStateManager
      debugPrint('Refresh failed: $e');
      
      // Show error feedback if the error isn't already being displayed
      if (mounted && !chatStateManager.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to refresh chats: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }



  void _navigateToChat(Chat chat) {
    Navigator.of(context).pushNamed('/chat', arguments: chat);
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Avatar shimmer
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                
                // Content shimmer
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name shimmer
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Message shimmer
                      Container(
                        height: 14,
                        width: MediaQuery.of(context).size.width * 0.6,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Time shimmer
                Container(
                  width: 40,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(String errorMessage, ChatStateManager chatStateManager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red[400],
              ),
            ),
            const SizedBox(height: 24),
            
            // Error title
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            
            // Error message
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            
            // Retry button
            ElevatedButton.icon(
              onPressed: () async {
                chatStateManager.clearError();
                await _refreshChats();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ChatStateManager chatStateManager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Empty state illustration
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            
            // Empty state title
            Text(
              'No chats yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            
            // Empty state description
            Text(
              'Start a conversation by tapping the + button below',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            
            // Connection status
            if (!chatStateManager.isConnected) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[600]!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Connecting...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String errorMessage, ChatStateManager chatStateManager) {
    return Container(
      width: double.infinity,
      color: Colors.red[50],
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.red[600],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connection issue: $errorMessage',
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              chatStateManager.clearError();
            },
            child: Text(
              'Dismiss',
              style: TextStyle(
                color: Colors.red[600],
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Logging out...'),
            ],
          ),
        ),
      );

      try {
        // Logout using AuthStateManager
        await context.read<AuthStateManager>().logout();
        
        if (mounted) {
          // Pop the loading dialog
          Navigator.pop(context);
          
          // The AuthWrapper will automatically redirect to WelcomeScreen
          // when the auth state changes - just pop back to root
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          // Pop the loading dialog
          Navigator.pop(context);
          
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logout failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  }


}  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HiChat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Camera',
            onPressed: () {
              Navigator.pushNamed(context, '/camera');
            },
          ),
          IconButton(
            icon: const Icon(Icons.location_on),
            tooltip: 'Location',
            onPressed: () {
              final authManager = context.read<AuthStateManager>();
              final username = authManager.currentUser?.username ?? 'User';
              Navigator.pushNamed(
                context, 
                AppConstants.locationSharingRoute,
                arguments: username,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search functionality
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  // TODO: Navigate to profile screen
                  break;
                case 'settings':
                  // TODO: Navigate to settings screen
                  break;
                case 'logout':
                  _handleLogout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('Profile'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<ChatStateManager>(
        builder: (context, chatStateManager, child) {
          final chats = chatStateManager.chats;
          final isLoading = chatStateManager.isLoading;
          final hasError = chatStateManager.hasError;
          final errorMessage = chatStateManager.errorMessage;
          
          // Show shimmer loading effect
          if (isLoading && chats.isEmpty) {
            return _buildShimmerLoading();
          }
          
          // Show error state with retry option
          if (hasError && chats.isEmpty) {
            return _buildErrorState(errorMessage!, chatStateManager);
          }
          
          // Show empty state
          if (chats.isEmpty && !isLoading) {
            return _buildEmptyState(chatStateManager);
          }
          
          // Show chat list with pull-to-refresh
          return RefreshIndicator(
            onRefresh: _refreshChats,
            color: AppColors.primary,
            child: Column(
              children: [
                // Show subtle loading indicator when refreshing with existing chats
                if (isLoading && chats.isNotEmpty)
                  SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                
                // Show error banner if there's an error but we have cached chats
                if (hasError && chats.isNotEmpty)
                  _buildErrorBanner(errorMessage!, chatStateManager),
                
                // Chat list
                Expanded(
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return AnimatedContainer(
                        duration: Duration(milliseconds: 300 + (index * 50)),
                        curve: Curves.easeOutCubic,
                        child: _ChatListItem(
                          chat: chat,
                          onTap: () => _navigateToChat(chat),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushNamed('/user-search');
        },
        heroTag: "new_chat_fab",
        elevation: 6,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;

  const _ChatListItem({
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chatStateManager = context.read<ChatStateManager>();
    final currentUserId = chatStateManager.getCurrentUserIdForUI();
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.primary,
        child: chat.getDisplayImage(currentUserId) != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  chat.getDisplayImage(currentUserId)!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    final displayName = _getSafeDisplayName(chat, currentUserId);
                    return Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              )
            : Text(
                () {
                  final displayName = _getSafeDisplayName(chat, currentUserId);
                  return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
                }(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(
        _getSafeDisplayName(chat, currentUserId),
        style: TextStyle(
          fontWeight: chat.hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: _buildLastMessageRow(chat),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(chat.lastActivity),
            style: TextStyle(
              fontSize: 12,
              color: chat.hasUnreadMessages ? AppColors.primary : Colors.grey[600],
              fontWeight: chat.hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (chat.hasUnreadMessages) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                chat.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
      ),
    );
  }

  /// Build last message row with appropriate icon for media messages
  Widget _buildLastMessageRow(Chat chat) {
    final lastMessage = chat.lastMessage;
    
    if (lastMessage == null) {
      return Text(
        'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chat.hasUnreadMessages ? Colors.black87 : Colors.grey[600],
          fontWeight: chat.hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
        ),
      );
    }

    IconData? messageIcon;
    String messageText;
    
    // Determine icon and text based on message type
    switch (lastMessage.type) {
      case MessageType.image:
        messageIcon = Icons.photo;
        messageText = 'Photo';
        break;
      case MessageType.video:
        messageIcon = Icons.videocam;
        messageText = 'Video';
        break;
      case MessageType.audio:
        messageIcon = Icons.mic;
        messageText = 'Voice message';
        break;
      case MessageType.file:
        messageIcon = Icons.attach_file;
        messageText = 'File';
        break;
      case MessageType.text:
        messageIcon = null;
        messageText = lastMessage.content;
        break;
    }

    return Row(
      children: [
        // Show icon for media messages
        if (messageIcon != null) ...[
          Icon(
            messageIcon,
            size: 16,
            color: chat.hasUnreadMessages ? Colors.black87 : Colors.grey[600],
          ),
          const SizedBox(width: 6),
        ],
        
        // Message text
        Expanded(
          child: Text(
            messageText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: chat.hasUnreadMessages ? Colors.black87 : Colors.grey[600],
              fontWeight: chat.hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  String _getSafeDisplayName(Chat chat, String currentUserId) {
    try {
      return chat.getDisplayName(currentUserId);
    } catch (e) {
      // Fallback if there's an error getting display name
      debugPrint('Error getting display name for chat ${chat.id}: $e');
      if (chat.name.isNotEmpty) return chat.name;
      return 'New Chat';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}