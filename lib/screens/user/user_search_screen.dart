import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:developer' as developer;
import '../../models/user.dart';
import '../../constants/app_theme.dart';
import '../../constants/app_constants.dart';
import '../../services/user_search_service.dart';
import '../../services/auth_state_manager.dart';
import '../../services/chat_state_manager.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<User> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    
    // Auto-focus search field when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }
  
  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
  
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    
    developer.log(
      'Search input changed',
      name: 'UserSearchScreen',
      error: {
        'query': query,
        'queryLength': query.length,
        'isEmpty': query.isEmpty,
      },
      level: 800,
    );
    
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      developer.log(
        'Query is empty, clearing results',
        name: 'UserSearchScreen',
        level: 800,
      );
      setState(() {
        _searchResults.clear();
        _hasSearched = false;
      });
      return;
    }
    
    // Debounce search to avoid too many API calls
    developer.log(
      'Starting debounce timer for search',
      name: 'UserSearchScreen',
      error: {'query': query, 'debounceMs': 500},
      level: 800,
    );
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }
  
  Future<void> _performSearch(String query) async {
    developer.log(
      'Starting search performance',
      name: 'UserSearchScreen',
      error: {
        'query': query,
        'queryLength': query.length,
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: 800,
    );
    
    if (query.isEmpty) {
      developer.log(
        'Query is empty in _performSearch, aborting',
        name: 'UserSearchScreen',
        level: 800,
      );
      return;
    }
    
    setState(() {
      _isSearching = true;
    });
    
    developer.log(
      'Set searching state to true',
      name: 'UserSearchScreen',
      level: 800,
    );
    
    try {
      final authManager = context.read<AuthStateManager>();
      developer.log(
        'Retrieved auth manager',
        name: 'UserSearchScreen',
        error: {
          'currentUser': authManager.currentUser?.toString(),
          'isLoggedIn': authManager.isLoggedIn,
        },
        level: 800,
      );
      
      final authToken = authManager.currentUser?.token;
      developer.log(
        'Retrieved auth token',
        name: 'UserSearchScreen',
        error: {
          'hasToken': authToken != null,
          'tokenLength': authToken?.length ?? 0,
          'tokenPreview': authToken?.substring(0, 10) ?? 'null',
        },
        level: 800,
      );
      
      if (authToken == null) {
        developer.log(
          'Auth token is null, throwing exception',
          name: 'UserSearchScreen',
          level: 1000,
        );
        throw Exception('Not authenticated');
      }
      
      developer.log(
        'Calling UserSearchService.searchUsers',
        name: 'UserSearchScreen',
        error: {
          'query': query,
          'hasToken': true,
        },
        level: 800,
      );
      
      final searchResult = await UserSearchService.searchUsers(query, authToken);
      
      developer.log(
        'Received search result from service',
        name: 'UserSearchScreen',
        error: {
          'resultCount': searchResult.count,
          'actualResults': searchResult.results.length,
          'mounted': mounted,
        },
        level: 800,
      );
      
      if (mounted) {
        developer.log(
          'Widget is mounted, updating state with results',
          name: 'UserSearchScreen',
          error: {
            'newResultsCount': searchResult.results.length,
            'users': searchResult.results.map((u) => {
              'id': u.id,
              'username': u.username,
              'email': u.email,
            }).toList(),
          },
          level: 800,
        );
        
        setState(() {
          _searchResults = searchResult.results;
          _hasSearched = true;
          _isSearching = false;
        });
        
        developer.log(
          'Successfully updated UI state',
          name: 'UserSearchScreen',
          level: 800,
        );
      } else {
        developer.log(
          'Widget not mounted, skipping state update',
          name: 'UserSearchScreen',
          level: 900,
        );
      }
    } catch (e) {
      developer.log(
        'Error during search',
        name: 'UserSearchScreen',
        error: {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
          'stackTrace': e is Error ? e.stackTrace.toString() : 'No stack trace',
          'mounted': mounted,
        },
        level: 1000,
      );
      
      if (mounted) {
        setState(() {
          _searchResults.clear();
          _hasSearched = true;
          _isSearching = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _createChatWithUser(User user) async {
    developer.log(
      'Starting chat creation with user',
      name: 'UserSearchScreen',
      error: {
        'targetUser': {
          'id': user.id,
          'username': user.username,
          'email': user.email,
          'availability': user.availability,
        },
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: 800,
    );
    
    try {
      final chatStateManager = context.read<ChatStateManager>();
      developer.log(
        'Retrieved ChatStateManager',
        name: 'UserSearchScreen',
        error: {
          'chatsCount': chatStateManager.chats.length,
          'isConnected': chatStateManager.isConnected,
        },
        level: 800,
      );
      
      // Show loading indicator
      developer.log(
        'Showing loading dialog',
        name: 'UserSearchScreen',
        level: 800,
      );
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Creating chat...'),
            ],
          ),
        ),
      );
      
      // Create or get existing chat
      developer.log(
        'Calling createOrGetChatWithUser',
        name: 'UserSearchScreen',
        error: {'userId': user.id},
        level: 800,
      );
      
      final createdChat = await chatStateManager.createOrGetChatWithUser(user.id);
      
      developer.log(
        'Chat creation result',
        name: 'UserSearchScreen',
        error: {
          'userId': user.id,
          'chatCreated': createdChat != null,
          'chatId': createdChat?.id,
          'newChatsCount': chatStateManager.chats.length,
        },
        level: 800,
      );
      
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
        
        if (createdChat != null) {
          developer.log(
            'Chat created successfully, navigating to chat screen',
            name: 'UserSearchScreen',
            error: {
              'chatId': createdChat.id,
              'chatName': createdChat.name,
            },
            level: 800,
          );
          
          // Close search screen
          Navigator.pop(context);
          
          // Navigate directly to the chat screen
          Navigator.of(context).pushNamed(AppConstants.chatRoute, arguments: createdChat);
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chat with ${user.username} is ready!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          // Chat creation failed
          developer.log(
            'Chat creation failed',
            name: 'UserSearchScreen',
            level: 1000,
          );
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create chat. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        developer.log(
          'Widget not mounted after chat creation',
          name: 'UserSearchScreen',
          level: 900,
        );
      }
    } catch (e) {
      developer.log(
        'Error during chat creation',
        name: 'UserSearchScreen',
        error: {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
          'stackTrace': e is Error ? e.stackTrace.toString() : 'No stack trace',
          'userId': user.id,
          'username': user.username,
          'mounted': mounted,
        },
        level: 1000,
      );
      
      // Close loading dialog if still open
      if (mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Users'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search by username or email...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _performSearch,
            ),
          ),
          
          // Search Results
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching users...'),
          ],
        ),
      );
    }
    
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Search for users to start chatting',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter a username or email above',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with a different username or email',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _UserSearchItem(
          user: user,
          onTap: () => _createChatWithUser(user),
        );
      },
    );
  }
}

class _UserSearchItem extends StatelessWidget {
  final User user;
  final VoidCallback onTap;
  
  const _UserSearchItem({
    required this.user,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: AppColors.primary,
              child: user.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: Image.network(
                        user.imageUrl!,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            user.username[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          );
                        },
                      ),
                    )
                  : Text(
                      user.username[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
            ),
            // Availability status indicator
            if (user.availability != null)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _getAvailabilityColor(user.availability!),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          user.username,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Availability status
            if (user.availability != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getAvailabilityColor(user.availability!),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${user.availability![0].toUpperCase()}${user.availability!.substring(1)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            // About text
            if (user.about?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                user.about!,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Email (shown last)
            if (user.email?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                user.email!,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.chat, size: 18),
          label: const Text('Chat'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
  
  Color _getAvailabilityColor(String availability) {
    switch (availability.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'busy':
        return Colors.red;
      case 'offline':
      default:
        return Colors.grey;
    }
  }
}