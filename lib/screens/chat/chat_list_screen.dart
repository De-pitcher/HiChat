import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hichat_app/constants/app_constants.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/auth_state_manager.dart';
import '../../services/chat_state_manager.dart';
import '../../widgets/online_indicator.dart';

/// Connection status enum for better state management
enum ConnectionStatus {
  connected,
  connecting,
  disconnected,
  reconnecting,
  failed,
}

/// Enhanced state class for chat list with better error handling
class ChatListState {
  final List<Chat> chats;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;
  final ConnectionStatus connectionStatus;
  final int reconnectAttempts;
  final DateTime? lastConnected;
  final bool showConnectionIndicator;

  const ChatListState({
    required this.chats,
    required this.isLoading,
    required this.hasError,
    required this.errorMessage,
    required this.connectionStatus,
    this.reconnectAttempts = 0,
    this.lastConnected,
    this.showConnectionIndicator = false,
  });
  
  bool get isConnected => connectionStatus == ConnectionStatus.connected;
  bool get isReconnecting => connectionStatus == ConnectionStatus.reconnecting;
  bool get isConnecting => connectionStatus == ConnectionStatus.connecting;
  bool get hasConnectionIssues => connectionStatus == ConnectionStatus.failed || 
                                  connectionStatus == ConnectionStatus.disconnected;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatListState &&
        other.chats.length == chats.length &&
        other.isLoading == isLoading &&
        other.hasError == hasError &&
        other.errorMessage == errorMessage &&
        other.connectionStatus == connectionStatus &&
        other.reconnectAttempts == reconnectAttempts &&
        other.showConnectionIndicator == showConnectionIndicator &&
        _listsEqual(other.chats, chats);
  }

  @override
  int get hashCode {
    return Object.hash(
      chats.length,
      isLoading,
      hasError,
      errorMessage,
      connectionStatus,
      reconnectAttempts,
      showConnectionIndicator,
    );
  }

  ChatListState copyWith({
    List<Chat>? chats,
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
    ConnectionStatus? connectionStatus,
    int? reconnectAttempts,
    DateTime? lastConnected,
    bool? showConnectionIndicator,
  }) {
    return ChatListState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      lastConnected: lastConnected ?? this.lastConnected,
      showConnectionIndicator: showConnectionIndicator ?? this.showConnectionIndicator,
    );
  }

  bool _listsEqual(List<Chat> a, List<Chat> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].lastActivity != b[i].lastActivity) {
        return false;
      }
    }
    return true;
  }
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  bool _isSearching = false;
  String _searchQuery = '';
  
  // Simple error debouncing
  Timer? _errorDisplayTimer;
  String? _lastDisplayedError;
  

  
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    // ChatStateManager is automatically initialized via AuthStateManager
    // No need to manually load chats here
    

  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _errorDisplayTimer?.cancel();
    super.dispose();
  }
  
  List<Chat> _filterChats(List<Chat> chats) {
    if (_searchQuery.isEmpty) {
      return chats;
    }
    
    return chats.where((chat) {
      // Search in chat name
      final chatName = _getChatName(chat).toLowerCase();
      if (chatName.contains(_searchQuery)) {
        return true;
      }
      
      // Search in last message content
      if (chat.lastMessage != null) {
        final lastMessageContent = chat.lastMessage!.content.toLowerCase();
        if (lastMessageContent.contains(_searchQuery)) {
          return true;
        }
      }
      
      return false;
    }).toList();
  }

  String _getChatName(Chat chat) {
    final authManager = context.read<AuthStateManager>();
    final currentUserId = authManager.currentUser?.id;
    return chat.getDisplayName(currentUserId);
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

  Widget _buildEmptyState(bool isConnected) {
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
            if (!isConnected) ...[
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

  Widget _buildNoSearchResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // No results illustration
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off,
                size: 64,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            
            // No results title
            Text(
              'No chats found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            
            // No results description
            Text(
              'Try a different search term or check your spelling',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
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
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search chats...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            )
          : const Text('HiChat'),
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
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.pushNamed(context, '/profile');
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
        builder: (context, chatManager, child) {
          final chats = _filterChats(chatManager.chats);
          final isLoading = chatManager.isLoading;
          final hasError = chatManager.hasError;
          final errorMessage = chatManager.errorMessage;
          
          // Show shimmer loading effect
          if (isLoading && chats.isEmpty) {
            return _buildShimmerLoading();
          }
          
          // Show error state with retry option (with debouncing)
          if (hasError && _shouldDisplayError(errorMessage) && chats.isEmpty) {
            return _buildErrorState(errorMessage!, chatManager);
          }
          
          // Show empty state
          if (chats.isEmpty && !isLoading) {
            if (_isSearching && _searchQuery.isNotEmpty) {
              return _buildNoSearchResults();
            }
            return _buildEmptyState(chatManager.isConnected);
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
                
                // Show error banner if there's an error but we have cached chats (with debouncing)
                if (hasError && _shouldDisplayError(errorMessage) && chats.isNotEmpty)
                  _buildErrorBanner(errorMessage!, chatManager),
                
                // Chat list - optimized with performance improvements
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: chats.length,
                    itemExtent: 80.0, // Fixed item height for better performance
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return RepaintBoundary(
                        child: _OptimizedChatListItem(
                          key: ValueKey(chat.id), // Use ValueKey for better performance
                          chat: chat,
                          onTap: () => _navigateToChat(chat),
                        ),
                      );
                    },
                    // Performance optimizations
                    cacheExtent: 1000.0, // Cache more items for smooth scrolling
                    addAutomaticKeepAlives: false, // Don't keep alive items off-screen
                    addRepaintBoundaries: true, // Add repaint boundaries for better performance
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Calls FAB
          FloatingActionButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/calls');
            },
            heroTag: "calls_fab",
            backgroundColor: Colors.green.withValues(alpha: 0.9),
            elevation: 4,
            child: const Icon(Icons.call, color: Colors.white),
          ),
          const SizedBox(height: 16),
          
          // Contacts FAB
          FloatingActionButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/contacts');
            },
            heroTag: "contacts_fab",
            backgroundColor: AppColors.primary.withValues(alpha: 0.9),
            elevation: 4,
            child: const Icon(Icons.contacts, color: Colors.white),
          ),
          const SizedBox(height: 16),
          
          // Add new chat FAB
          FloatingActionButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/user-search');
            },
            heroTag: "new_chat_fab",
            backgroundColor: AppColors.primary,
            elevation: 6,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Check if we should display an error message with debouncing
  bool _shouldDisplayError(String? errorMessage) {
    if (errorMessage == null) {
      // Clear state when there's no error
      _lastDisplayedError = null;
      _errorDisplayTimer?.cancel();
      return false;
    }
    
    // If this is a new error, start debouncing
    if (_lastDisplayedError != errorMessage) {
      _lastDisplayedError = errorMessage;
      _errorDisplayTimer?.cancel();
      
      // Only show error after a delay to prevent flickering during reconnection
      _errorDisplayTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            // Trigger rebuild to show the error
          });
        }
      });
      
      return false; // Don't show immediately
    }
    
    // Show error if the timer has completed and we're still in error state
    return _errorDisplayTimer?.isActive != true;
  }
}

class _OptimizedChatListItem extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;

  const _OptimizedChatListItem({
    super.key,
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ChatStateManager, String>(
      selector: (context, chatManager) => chatManager.getCurrentUserIdForUI(),
      builder: (context, currentUserId, child) {
        return _buildChatItem(context, currentUserId);
      },
    );
  }

  Widget _buildChatItem(BuildContext context, String currentUserId) {
    // Cache expensive operations
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

  /// Optimized avatar building with presence awareness
  Widget _buildAvatar(String displayName, String? displayImage, String currentUserId) {
    // For direct chats, show presence-aware avatar
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
    
    // Fallback to regular avatar for group chats or when other user not found
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
                memCacheWidth: 80, // Optimize memory usage
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

  /// Optimized trailing section
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

  /// Build last message row with appropriate icon for media messages
  Widget _buildLastMessageRow(Chat chat, bool hasUnreadMessages, String currentUserId) {
    return Consumer<ChatStateManager>(
      builder: (context, chatManager, child) {
        final lastMessage = chat.lastMessage;
        
        // For direct chats, show presence status if user is online
        if (chat.isDirectChat) {
          final otherUserId = chat.getOtherUserId(currentUserId);
          if (otherUserId != null) {
            final isOnline = chatManager.isUserOnline(otherUserId);
            
            // If user is online, show "online" status
            if (isOnline) {
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
            
            // For offline users, just show the regular message content
            // The presence indicator on the avatar is sufficient
          }
        }
        
        // Default: show last message
        return _buildMessageContent(lastMessage, hasUnreadMessages);
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
            color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
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
              color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
              fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
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