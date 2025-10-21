import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hichat_app/constants/app_constants.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../constants/app_theme.dart';
import '../../services/auth_state_manager.dart';
import '../../services/chat_state_manager.dart';
import '../../widgets/chat_list_items.dart';
import '../../widgets/chat_list_states.dart';

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
  Timer? _errorDisplayTimer;
  String? _lastDisplayedError;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _errorDisplayTimer?.cancel();
    super.dispose();
  }

  List<Chat> _filterChats(List<Chat> chats) {
    if (_searchQuery.isEmpty) return chats;

    return chats.where((chat) {
      final chatName = _getChatName(chat).toLowerCase();
      if (chatName.contains(_searchQuery)) return true;

      final lastMessageContent = chat.lastMessage?.content.toLowerCase() ?? '';
      return lastMessageContent.contains(_searchQuery);
    }).toList();
  }

  String _getChatName(Chat chat) {
    final currentUserId = context.read<AuthStateManager>().currentUser?.id;
    return chat.getDisplayName(currentUserId);
  }

  Future<void> _refreshChats() async {
    final chatStateManager = context.read<ChatStateManager>();

    try {
      debugPrint('ChatListScreen: Starting refresh...');
      await chatStateManager.refreshChats();

      if (mounted && !chatStateManager.hasError) {
        _showSnackBar(
          'Chats refreshed successfully',
          Colors.green,
          Icons.check_circle,
        );
      }
    } catch (e) {
      debugPrint('Refresh failed: $e');

      if (mounted && !chatStateManager.hasError) {
        _showSnackBar(
          'Failed to refresh chats: $e',
          Colors.red,
          Icons.error_outline,
        );
      }
    }
  }

  void _showSnackBar(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        duration: Duration(seconds: color == Colors.green ? 2 : 3),
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _navigateToChat(Chat chat) {
    Navigator.of(context).pushNamed('/chat', arguments: chat);
  }

  void _handleLogout() async {
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
        await context.read<AuthStateManager>().logout();
        if (mounted) {
          Navigator.pop(context);
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
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
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              )
            : const Text('HiChat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Camera',
            onPressed: () => Navigator.pushNamed(context, '/camera'),
          ),
          IconButton(
            icon: const Icon(Icons.location_on),
            tooltip: 'Location',
            onPressed: () {
              final username =
                  context.read<AuthStateManager>().currentUser?.username ??
                  'User';
              Navigator.pushNamed(
                context,
                AppConstants.locationSharingRoute,
                arguments: username,
              );
            },
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchQuery = '';
              }
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.pushNamed(context, '/profile');
                  break;
                case 'settings':
                  break; // TODO: Navigate to settings screen
                case 'logout':
                  _handleLogout();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'logout', child: Text('Logout')),
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

          if (isLoading && chats.isEmpty) return const ChatListShimmerLoading();
          if (hasError && _shouldDisplayError(errorMessage) && chats.isEmpty) {
            return ChatListErrorState(
              errorMessage: errorMessage!,
              onRetry: () async {
                chatManager.clearError();
                await _refreshChats();
              },
            );
          }
          if (chats.isEmpty && !isLoading) {
            return RefreshIndicator(
              onRefresh: _refreshChats,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - 200, // Account for app bar
                  child: ChatListEmptyState(
                    isConnected: chatManager.isConnected,
                    isSearching: _isSearching && _searchQuery.isNotEmpty,
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshChats,
            color: AppColors.primary,
            child: Column(
              children: [
                if (isLoading && chats.isNotEmpty)
                  SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                if (hasError &&
                    _shouldDisplayError(errorMessage) &&
                    chats.isNotEmpty)
                  ChatListErrorBanner(
                    errorMessage: errorMessage!,
                    onDismiss: () => chatManager.clearError(),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: chats.length,
                    itemExtent: 80.0,
                    itemBuilder: (context, index) => OptimizedChatListItem(
                      key: ValueKey(chats[index].id),
                      chat: chats[index],
                      onTap: () => _navigateToChat(chats[index]),
                    ),
                    cacheExtent: 1000.0,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
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
          FloatingActionButton(
            onPressed: () => Navigator.of(context).pushNamed('/calls'),
            heroTag: "calls_fab",
            backgroundColor: Colors.green.withValues(alpha: 0.9),
            elevation: 4,
            child: const Icon(Icons.call, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () => Navigator.of(context).pushNamed('/contacts'),
            heroTag: "contacts_fab",
            backgroundColor: AppColors.primary.withValues(alpha: 0.9),
            elevation: 4,
            child: const Icon(Icons.contacts, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () => Navigator.of(context).pushNamed('/user-search'),
            heroTag: "new_chat_fab",
            backgroundColor: AppColors.primary,
            elevation: 6,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }

  bool _shouldDisplayError(String? errorMessage) {
    if (errorMessage == null) {
      _lastDisplayedError = null;
      _errorDisplayTimer?.cancel();
      return false;
    }

    if (_lastDisplayedError != errorMessage) {
      _lastDisplayedError = errorMessage;
      _errorDisplayTimer?.cancel();
      _errorDisplayTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() {});
      });
      return false;
    }

    return _errorDisplayTimer?.isActive != true;
  }
}

// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:hichat_app/constants/app_constants.dart';
// import 'package:provider/provider.dart';
// import 'package:shimmer/shimmer.dart';
// import 'package:cached_network_image/cached_network_image.dart';
// import '../../models/chat.dart';
// import '../../models/message.dart';
// import '../../constants/app_theme.dart';
// import '../../services/auth_state_manager.dart';
// import '../../services/chat_state_manager.dart';
// import '../../widgets/online_indicator.dart';

// class ChatListScreen extends StatefulWidget {
//   const ChatListScreen({super.key});

//   @override
//   State<ChatListScreen> createState() => _ChatListScreenState();
// }

// class _ChatListScreenState extends State<ChatListScreen> {
//   late final ScrollController _scrollController;
//   late final TextEditingController _searchController;
//   bool _isSearching = false;
//   String _searchQuery = '';
//   Timer? _errorDisplayTimer;
//   String? _lastDisplayedError;

//   @override
//   void initState() {
//     super.initState();
//     _scrollController = ScrollController();
//     _searchController = TextEditingController();
//   }

//   @override
//   void dispose() {
//     _scrollController.dispose();
//     _searchController.dispose();
//     _errorDisplayTimer?.cancel();
//     super.dispose();
//   }

//   List<Chat> _filterChats(List<Chat> chats) {
//     if (_searchQuery.isEmpty) return chats;

//     return chats.where((chat) {
//       final chatName = _getChatName(chat).toLowerCase();
//       if (chatName.contains(_searchQuery)) return true;

//       final lastMessageContent = chat.lastMessage?.content.toLowerCase() ?? '';
//       return lastMessageContent.contains(_searchQuery);
//     }).toList();
//   }

//   String _getChatName(Chat chat) {
//     final currentUserId = context.read<AuthStateManager>().currentUser?.id;
//     return chat.getDisplayName(currentUserId);
//   }

//   Future<void> _refreshChats() async {
//     final chatStateManager = context.read<ChatStateManager>();

//     try {
//       debugPrint('ChatListScreen: Starting refresh...');
//       await chatStateManager.refreshChats();

//       if (mounted && !chatStateManager.hasError) {
//         _showSnackBar(
//           'Chats refreshed successfully',
//           Colors.green,
//           Icons.check_circle,
//         );
//       }
//     } catch (e) {
//       debugPrint('Refresh failed: $e');

//       if (mounted && !chatStateManager.hasError) {
//         _showSnackBar(
//           'Failed to refresh chats: $e',
//           Colors.red,
//           Icons.error_outline,
//         );
//       }
//     }
//   }

//   void _showSnackBar(String message, Color color, IconData icon) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             Icon(icon, color: Colors.white, size: 20),
//             const SizedBox(width: 8),
//             Expanded(child: Text(message)),
//           ],
//         ),
//         backgroundColor: color,
//         duration: Duration(seconds: color == Colors.green ? 2 : 3),
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//       ),
//     );
//   }

//   void _navigateToChat(Chat chat) {
//     Navigator.of(context).pushNamed('/chat', arguments: chat);
//   }

//   Widget _buildShimmerLoading() {
//     return ListView.builder(
//       itemCount: 8,
//       itemBuilder: (context, index) => Shimmer.fromColors(
//         baseColor: Colors.grey[300]!,
//         highlightColor: Colors.grey[100]!,
//         child: Container(
//           margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//           child: Row(
//             children: [
//               Container(
//                 width: 50,
//                 height: 50,
//                 decoration: const BoxDecoration(
//                   color: Colors.white,
//                   shape: BoxShape.circle,
//                 ),
//               ),
//               const SizedBox(width: 16),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Container(
//                       height: 16,
//                       width: double.infinity,
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     Container(
//                       height: 14,
//                       width: MediaQuery.of(context).size.width * 0.6,
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Container(
//                 width: 40,
//                 height: 12,
//                 decoration: BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(6),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildErrorState(
//     String errorMessage,
//     ChatStateManager chatStateManager,
//   ) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(32.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.red[50],
//                 shape: BoxShape.circle,
//               ),
//               child: Icon(
//                 Icons.error_outline,
//                 size: 48,
//                 color: Colors.red[400],
//               ),
//             ),
//             const SizedBox(height: 24),
//             Text(
//               'Something went wrong',
//               style: Theme.of(context).textTheme.headlineSmall?.copyWith(
//                 fontWeight: FontWeight.bold,
//                 color: Colors.red[700],
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               errorMessage,
//               textAlign: TextAlign.center,
//               style: Theme.of(
//                 context,
//               ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
//             ),
//             const SizedBox(height: 32),
//             ElevatedButton.icon(
//               onPressed: () async {
//                 chatStateManager.clearError();
//                 await _refreshChats();
//               },
//               icon: const Icon(Icons.refresh),
//               label: const Text('Try Again'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: AppColors.primary,
//                 foregroundColor: Colors.white,
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 24,
//                   vertical: 12,
//                 ),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(24),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildEmptyState(bool isConnected) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(32.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               padding: const EdgeInsets.all(24),
//               decoration: BoxDecoration(
//                 color: AppColors.primary.withValues(alpha: 0.1),
//                 shape: BoxShape.circle,
//               ),
//               child: Icon(
//                 Icons.chat_bubble_outline,
//                 size: 64,
//                 color: AppColors.primary,
//               ),
//             ),
//             const SizedBox(height: 24),
//             Text(
//               'No chats yet',
//               style: Theme.of(context).textTheme.headlineSmall?.copyWith(
//                 fontWeight: FontWeight.bold,
//                 color: Colors.grey[700],
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Start a conversation by tapping the + button below',
//               textAlign: TextAlign.center,
//               style: Theme.of(
//                 context,
//               ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
//             ),
//             if (!isConnected) ...[
//               const SizedBox(height: 16),
//               Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 12,
//                   vertical: 8,
//                 ),
//                 decoration: BoxDecoration(
//                   color: Colors.orange[50],
//                   borderRadius: BorderRadius.circular(16),
//                   border: Border.all(color: Colors.orange[200]!),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     SizedBox(
//                       width: 16,
//                       height: 16,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         valueColor: AlwaysStoppedAnimation<Color>(
//                           Colors.orange[600]!,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Text(
//                       'Connecting...',
//                       style: TextStyle(
//                         fontSize: 12,
//                         color: Colors.orange[700],
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildNoSearchResults() {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(32.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               padding: const EdgeInsets.all(24),
//               decoration: BoxDecoration(
//                 color: Colors.grey.withValues(alpha: 0.1),
//                 shape: BoxShape.circle,
//               ),
//               child: const Icon(Icons.search_off, size: 64, color: Colors.grey),
//             ),
//             const SizedBox(height: 24),
//             Text(
//               'No chats found',
//               style: Theme.of(context).textTheme.headlineSmall?.copyWith(
//                 fontWeight: FontWeight.bold,
//                 color: Colors.grey[700],
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Try a different search term or check your spelling',
//               textAlign: TextAlign.center,
//               style: Theme.of(
//                 context,
//               ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildErrorBanner(
//     String errorMessage,
//     ChatStateManager chatStateManager,
//   ) {
//     return Container(
//       width: double.infinity,
//       color: Colors.red[50],
//       padding: const EdgeInsets.all(12),
//       child: Row(
//         children: [
//           Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 20),
//           const SizedBox(width: 8),
//           Expanded(
//             child: Text(
//               'Connection issue: $errorMessage',
//               style: TextStyle(
//                 color: Colors.red[700],
//                 fontSize: 12,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//           TextButton(
//             onPressed: () => chatStateManager.clearError(),
//             child: Text(
//               'Dismiss',
//               style: TextStyle(
//                 color: Colors.red[600],
//                 fontSize: 12,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   void _handleLogout() async {
//     final shouldLogout = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Logout'),
//         content: const Text('Are you sure you want to logout?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Logout'),
//           ),
//         ],
//       ),
//     );

//     if (shouldLogout == true && mounted) {
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (context) => const AlertDialog(
//           content: Row(
//             children: [
//               CircularProgressIndicator(),
//               SizedBox(width: 16),
//               Text('Logging out...'),
//             ],
//           ),
//         ),
//       );

//       try {
//         await context.read<AuthStateManager>().logout();
//         if (mounted) {
//           Navigator.pop(context);
//           Navigator.popUntil(context, (route) => route.isFirst);
//         }
//       } catch (e) {
//         if (mounted) {
//           Navigator.pop(context);
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text('Logout failed: $e'),
//               backgroundColor: Colors.red,
//             ),
//           );
//         }
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: _isSearching
//             ? TextField(
//                 controller: _searchController,
//                 autofocus: true,
//                 decoration: const InputDecoration(
//                   hintText: 'Search chats...',
//                   border: InputBorder.none,
//                   hintStyle: TextStyle(color: Colors.white54),
//                 ),
//                 style: const TextStyle(color: Colors.white),
//                 onChanged: (value) =>
//                     setState(() => _searchQuery = value.toLowerCase()),
//               )
//             : const Text('HiChat'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.camera_alt),
//             tooltip: 'Camera',
//             onPressed: () => Navigator.pushNamed(context, '/camera'),
//           ),
//           IconButton(
//             icon: const Icon(Icons.location_on),
//             tooltip: 'Location',
//             onPressed: () {
//               final username =
//                   context.read<AuthStateManager>().currentUser?.username ??
//                   'User';
//               Navigator.pushNamed(
//                 context,
//                 AppConstants.locationSharingRoute,
//                 arguments: username,
//               );
//             },
//           ),
//           IconButton(
//             icon: Icon(_isSearching ? Icons.close : Icons.search),
//             onPressed: () => setState(() {
//               _isSearching = !_isSearching;
//               if (!_isSearching) {
//                 _searchController.clear();
//                 _searchQuery = '';
//               }
//             }),
//           ),
//           PopupMenuButton<String>(
//             onSelected: (value) {
//               switch (value) {
//                 case 'profile':
//                   Navigator.pushNamed(context, '/profile');
//                   break;
//                 case 'settings':
//                   break; // TODO: Navigate to settings screen
//                 case 'logout':
//                   _handleLogout();
//                   break;
//               }
//             },
//             itemBuilder: (context) => const [
//               PopupMenuItem(value: 'profile', child: Text('Profile')),
//               PopupMenuItem(value: 'settings', child: Text('Settings')),
//               PopupMenuItem(value: 'logout', child: Text('Logout')),
//             ],
//           ),
//         ],
//       ),
//       body: Consumer<ChatStateManager>(
//         builder: (context, chatManager, child) {
//           final chats = _filterChats(chatManager.chats);
//           final isLoading = chatManager.isLoading;
//           final hasError = chatManager.hasError;
//           final errorMessage = chatManager.errorMessage;

//           if (isLoading && chats.isEmpty) return _buildShimmerLoading();
//           if (hasError && _shouldDisplayError(errorMessage) && chats.isEmpty)
//             return _buildErrorState(errorMessage!, chatManager);
//           if (chats.isEmpty && !isLoading) {
//             if (_isSearching && _searchQuery.isNotEmpty)
//               return _buildNoSearchResults();
//             return _buildEmptyState(chatManager.isConnected);
//           }

//           return RefreshIndicator(
//             onRefresh: _refreshChats,
//             color: AppColors.primary,
//             child: Column(
//               children: [
//                 if (isLoading && chats.isNotEmpty)
//                   SizedBox(
//                     height: 3,
//                     child: LinearProgressIndicator(
//                       backgroundColor: Colors.transparent,
//                       valueColor: AlwaysStoppedAnimation<Color>(
//                         AppColors.primary,
//                       ),
//                     ),
//                   ),
//                 if (hasError &&
//                     _shouldDisplayError(errorMessage) &&
//                     chats.isNotEmpty)
//                   _buildErrorBanner(errorMessage!, chatManager),
//                 Expanded(
//                   child: ListView.builder(
//                     controller: _scrollController,
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     itemCount: chats.length,
//                     itemExtent: 80.0,
//                     itemBuilder: (context, index) => RepaintBoundary(
//                       child: _OptimizedChatListItem(
//                         key: ValueKey(chats[index].id),
//                         chat: chats[index],
//                         onTap: () => _navigateToChat(chats[index]),
//                       ),
//                     ),
//                     cacheExtent: 1000.0,
//                     addAutomaticKeepAlives: false,
//                     addRepaintBoundaries: true,
//                   ),
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//       floatingActionButton: Column(
//         mainAxisAlignment: MainAxisAlignment.end,
//         children: [
//           FloatingActionButton(
//             onPressed: () => Navigator.of(context).pushNamed('/calls'),
//             heroTag: "calls_fab",
//             backgroundColor: Colors.green.withValues(alpha: 0.9),
//             elevation: 4,
//             child: const Icon(Icons.call, color: Colors.white),
//           ),
//           const SizedBox(height: 16),
//           FloatingActionButton(
//             onPressed: () => Navigator.of(context).pushNamed('/contacts'),
//             heroTag: "contacts_fab",
//             backgroundColor: AppColors.primary.withValues(alpha: 0.9),
//             elevation: 4,
//             child: const Icon(Icons.contacts, color: Colors.white),
//           ),
//           const SizedBox(height: 16),
//           FloatingActionButton(
//             onPressed: () => Navigator.of(context).pushNamed('/user-search'),
//             heroTag: "new_chat_fab",
//             backgroundColor: AppColors.primary,
//             elevation: 6,
//             child: const Icon(Icons.add, color: Colors.white),
//           ),
//         ],
//       ),
//     );
//   }

//   bool _shouldDisplayError(String? errorMessage) {
//     if (errorMessage == null) {
//       _lastDisplayedError = null;
//       _errorDisplayTimer?.cancel();
//       return false;
//     }

//     if (_lastDisplayedError != errorMessage) {
//       _lastDisplayedError = errorMessage;
//       _errorDisplayTimer?.cancel();
//       _errorDisplayTimer = Timer(const Duration(seconds: 2), () {
//         if (mounted) setState(() {});
//       });
//       return false;
//     }

//     return _errorDisplayTimer?.isActive != true;
//   }
// }

// class _OptimizedChatListItem extends StatelessWidget {
//   final Chat chat;
//   final VoidCallback onTap;

//   const _OptimizedChatListItem({
//     super.key,
//     required this.chat,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Selector<ChatStateManager, String>(
//       selector: (context, chatManager) => chatManager.getCurrentUserIdForUI(),
//       builder: (context, currentUserId, child) =>
//           _buildChatItem(context, currentUserId),
//     );
//   }

//   Widget _buildChatItem(BuildContext context, String currentUserId) {
//     final displayName = _getSafeDisplayName(chat, currentUserId);
//     final displayImage = chat.getDisplayImage(currentUserId);
//     final hasUnreadMessages = chat.hasUnreadMessages;
//     final lastActivity = chat.lastActivity;

//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(8),
//         color: hasUnreadMessages ? Colors.grey.withValues(alpha: 0.05) : null,
//       ),
//       child: ListTile(
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         leading: _buildAvatar(displayName, displayImage, currentUserId),
//         title: Text(
//           displayName,
//           style: TextStyle(
//             fontWeight: hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
//           ),
//         ),
//         subtitle: _buildLastMessageRow(chat, hasUnreadMessages, currentUserId),
//         trailing: _buildTrailing(
//           lastActivity,
//           hasUnreadMessages,
//           chat.unreadCount,
//         ),
//         onTap: onTap,
//       ),
//     );
//   }

//   Widget _buildAvatar(
//     String displayName,
//     String? displayImage,
//     String currentUserId,
//   ) {
//     if (chat.isDirectChat) {
//       final otherUserId = chat.getOtherUserId(currentUserId);
//       if (otherUserId != null) {
//         return PresenceAwareAvatar(
//           userId: otherUserId,
//           imageUrl: displayImage,
//           displayName: displayName,
//           radius: 20.0,
//           showIndicator: true,
//           showPulse: true,
//           backgroundColor: AppColors.primary,
//         );
//       }
//     }

//     return CircleAvatar(
//       backgroundColor: AppColors.primary,
//       child: displayImage != null
//           ? ClipRRect(
//               borderRadius: BorderRadius.circular(20),
//               child: CachedNetworkImage(
//                 imageUrl: displayImage,
//                 width: 40,
//                 height: 40,
//                 fit: BoxFit.cover,
//                 placeholder: (context, url) => Container(
//                   width: 40,
//                   height: 40,
//                   color: Colors.grey[300],
//                   child: const Center(
//                     child: SizedBox(
//                       width: 20,
//                       height: 20,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     ),
//                   ),
//                 ),
//                 errorWidget: (context, url, error) =>
//                     _buildAvatarText(displayName),
//                 fadeInDuration: const Duration(milliseconds: 200),
//                 fadeOutDuration: const Duration(milliseconds: 100),
//                 memCacheWidth: 80,
//                 memCacheHeight: 80,
//               ),
//             )
//           : _buildAvatarText(displayName),
//     );
//   }

//   Widget _buildAvatarText(String displayName) => Text(
//     displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
//     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
//   );

//   Widget _buildTrailing(
//     DateTime lastActivity,
//     bool hasUnreadMessages,
//     int unreadCount,
//   ) {
//     return Column(
//       mainAxisAlignment: MainAxisAlignment.center,
//       crossAxisAlignment: CrossAxisAlignment.end,
//       children: [
//         Text(
//           _formatTime(lastActivity),
//           style: TextStyle(
//             fontSize: 12,
//             color: hasUnreadMessages ? AppColors.primary : Colors.grey[600],
//             fontWeight: hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
//           ),
//         ),
//         if (hasUnreadMessages) ...[
//           const SizedBox(height: 4),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//             decoration: const BoxDecoration(
//               color: AppColors.primary,
//               shape: BoxShape.circle,
//             ),
//             child: Text(
//               unreadCount.toString(),
//               style: const TextStyle(
//                 color: Colors.white,
//                 fontSize: 12,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//           ),
//         ],
//       ],
//     );
//   }

//   Widget _buildLastMessageRow(
//     Chat chat,
//     bool hasUnreadMessages,
//     String currentUserId,
//   ) {
//     return Consumer<ChatStateManager>(
//       builder: (context, chatManager, child) {
//         if (chat.isDirectChat) {
//           final otherUserId = chat.getOtherUserId(currentUserId);
//           if (otherUserId != null && chatManager.isUserOnline(otherUserId)) {
//             return Row(
//               children: [
//                 Container(
//                   width: 8,
//                   height: 8,
//                   decoration: const BoxDecoration(
//                     color: Colors.green,
//                     shape: BoxShape.circle,
//                   ),
//                 ),
//                 const SizedBox(width: 6),
//                 const Text(
//                   'online',
//                   style: TextStyle(
//                     color: Colors.green,
//                     fontSize: 13,
//                     fontStyle: FontStyle.italic,
//                   ),
//                 ),
//               ],
//             );
//           }
//         }
//         return _buildMessageContent(chat.lastMessage, hasUnreadMessages);
//       },
//     );
//   }

//   Widget _buildMessageContent(Message? lastMessage, bool hasUnreadMessages) {
//     if (lastMessage == null)
//       return Text(
//         'No messages yet',
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//         style: TextStyle(
//           color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
//           fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
//         ),
//       );

//     final messageData = _getMessageData(lastMessage);

//     return Row(
//       children: [
//         if (messageData.icon != null) ...[
//           Icon(
//             messageData.icon,
//             size: 16,
//             color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
//           ),
//           const SizedBox(width: 6),
//         ],
//         Expanded(
//           child: Text(
//             messageData.text,
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//             style: TextStyle(
//               color: hasUnreadMessages ? Colors.black87 : Colors.grey[600],
//               fontWeight: hasUnreadMessages
//                   ? FontWeight.w500
//                   : FontWeight.normal,
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   _MessageData _getMessageData(Message message) {
//     switch (message.type) {
//       case MessageType.image:
//         return _MessageData(Icons.photo, 'Photo');
//       case MessageType.video:
//         return _MessageData(Icons.videocam, 'Video');
//       case MessageType.audio:
//         return _MessageData(Icons.mic, 'Voice message');
//       case MessageType.file:
//         return _MessageData(Icons.attach_file, 'File');
//       case MessageType.text:
//         return _MessageData(null, message.content);
//     }
//   }

//   String _getSafeDisplayName(Chat chat, String currentUserId) {
//     try {
//       return chat.getDisplayName(currentUserId);
//     } catch (e) {
//       debugPrint('Error getting display name for chat ${chat.id}: $e');
//       return chat.name.isNotEmpty ? chat.name : 'New Chat';
//     }
//   }

//   String _formatTime(DateTime time) {
//     final difference = DateTime.now().difference(time);
//     if (difference.inDays > 0) return '${difference.inDays}d';
//     if (difference.inHours > 0) return '${difference.inHours}h';
//     if (difference.inMinutes > 0) return '${difference.inMinutes}m';
//     return 'now';
//   }
// }

// class _MessageData {
//   final IconData? icon;
//   final String text;

//   _MessageData(this.icon, this.text);
// }
