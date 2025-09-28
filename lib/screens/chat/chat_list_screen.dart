import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../models/user.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/auth_state_manager.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Chat> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: Replace with actual API call
      await Future.delayed(const Duration(seconds: 1)); // Simulate loading
      
      // Mock data for demonstration
      _chats = _generateMockChats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load chats: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Chat> _generateMockChats() {
    final now = DateTime.now();
    return [
      Chat(
        id: '1',
        name: 'John Doe',
        type: ChatType.direct,
        participantIds: ['user1', 'currentUser'],
        participants: [
          User(
            id: 1,
            username: 'John Doe',
            email: 'john@example.com',
            isOnline: true,
            createdAt: now.subtract(const Duration(days: 30)),
          ),
        ],
        lastMessage: Message(
          id: 'msg1',
          chatId: '1',
          senderId: 'user1',
          content: 'Hey! How are you doing?',
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        lastActivity: now.subtract(const Duration(minutes: 5)),
        unreadCount: 2,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Chat(
        id: '2',
        name: 'Flutter Developers',
        type: ChatType.group,
        participantIds: ['user2', 'user3', 'currentUser'],
        participants: [
          User(
            id: 2,
            username: 'Alice Smith',
            email: 'alice@example.com',
            isOnline: false,
            lastSeen: now.subtract(const Duration(hours: 2)),
            createdAt: now.subtract(const Duration(days: 60)),
          ),
          User(
            id: 3,
            username: 'Bob Johnson',
            email: 'bob@example.com',
            isOnline: true,
            createdAt: now.subtract(const Duration(days: 45)),
          ),
        ],
        lastMessage: Message(
          id: 'msg2',
          chatId: '2',
          senderId: 'user2',
          content: 'Check out this new Flutter update!',
          timestamp: now.subtract(const Duration(hours: 1)),
        ),
        lastActivity: now.subtract(const Duration(hours: 1)),
        unreadCount: 0,
        createdAt: now.subtract(const Duration(days: 7)),
      ),
    ];
  }

  void _navigateToChat(Chat chat) {
    Navigator.of(context).pushNamed('/chat', arguments: chat);
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
  }

  @override
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No chats yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.builder(
                    itemCount: _chats.length,
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Navigate to new chat screen
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
    const currentUserId = 'currentUser'; // TODO: Get from auth service
    
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
                    return Text(
                      chat.getDisplayName(currentUserId)[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              )
            : Text(
                chat.getDisplayName(currentUserId)[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(
        chat.getDisplayName(currentUserId),
        style: TextStyle(
          fontWeight: chat.hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        chat.lastMessage?.content ?? 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chat.hasUnreadMessages ? Colors.black87 : Colors.grey[600],
          fontWeight: chat.hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
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