import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_theme.dart';
import '../../services/sms_service.dart';
import '../../services/auth_state_manager.dart';
import '../../services/api_service.dart';
import '../../models/sms_message.dart';
import '../../models/bulk_upload_models.dart';

class SMSScreen extends StatefulWidget {
  const SMSScreen({super.key});

  @override
  State<SMSScreen> createState() => _SMSScreenState();
}

class _SMSScreenState extends State<SMSScreen> {
  late SMSService _smsService;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _smsService = SMSService();
    _initializeSMSService();
  }

  Future<void> _initializeSMSService() async {
    debugPrint('SMSScreen: Initializing SMS service...');
    await _smsService.initialize();
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
      
      // Upload SMS messages in bulk after loading
      if (_smsService.hasPermission && _smsService.smsMessages.isNotEmpty) {
        await _uploadSMSBulk(_smsService.smsMessages);
      }
    }
  }

  Future<void> _uploadSMSBulk(List<SMSMessage> smsMessages) async {
    try {
      final authManager = context.read<AuthStateManager>();
      final currentUser = authManager.currentUser;
      
      if (currentUser == null) {
        debugPrint('Cannot upload SMS: No authenticated user found');
        return;
      }

      debugPrint('Starting bulk SMS upload for ${smsMessages.length} SMS messages');

      // Convert SMS messages to API format
      final List<SMSData> smsData = smsMessages.map((sms) {
        return SMSData(
          address: sms.address,
          body: sms.body,
        );
      }).where((sms) => sms.address.isNotEmpty && sms.body.isNotEmpty).toList();

      if (smsData.isEmpty) {
        debugPrint('No valid SMS messages to upload');
        return;
      }

      // Upload to server
      final apiService = ApiService();
      final response = await apiService.uploadSMSBulk(
        owner: currentUser.id.toString(),
        smsList: smsData,
      );

      debugPrint('Bulk SMS upload successful: ${response.message}');
      debugPrint('Created: ${response.created}, Skipped: ${response.skipped}, Total: ${response.totalProcessed}');

      // Show success message to user
      if (mounted) {
        final successMessage = response.created > 0 
            ? 'SMS synced: ${response.created} uploaded successfully'
            : 'All ${response.totalProcessed} SMS messages were already synced';
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: response.created > 0 ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      debugPrint('Error uploading SMS in bulk: $e');
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync SMS: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Messages'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _smsService.refresh(),
            tooltip: 'Refresh SMS messages',
          ),
          if (_smsService.totalUnreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_smsService.totalUnreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized || _smsService.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading SMS messages...'),
          ],
        ),
      );
    }

    if (!_smsService.hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.message,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Permission Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'HiChat needs access to your SMS messages to display them here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _smsService.showPermissionDialog(context),
              icon: const Icon(Icons.settings),
              label: const Text('Grant Permission'),
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
      );
    }

    if (_smsService.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading SMS',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _smsService.error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _smsService.clearError();
                _smsService.refresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _smsService,
      child: Consumer<SMSService>(
        builder: (context, smsService, child) {
          final conversations = smsService.conversations;
          
          if (conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: Theme.of(context).dividerColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No SMS Messages',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No SMS conversations found on this device.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => smsService.refresh(),
            child: Column(
              children: [
                // Debug info showing total conversations
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Total SMS Conversations: ${conversations.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Show ALL conversations without lazy loading to debug the issue
                Expanded(
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return _OptimizedConversationTile(
                        key: ValueKey(conversation.address),
                        conversation: conversation,
                        onTap: () => _openConversationDetail(conversation),
                        smsService: smsService,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConversationTile(SMSConversation conversation) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Text(
            _getContactInitials(conversation.contactName),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          conversation.contactName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conversation.lastMessagePreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(conversation.lastMessageDate),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        trailing: conversation.hasUnreadMessages
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () => _openConversationDetail(conversation),
      ),
    );
  }

  String _getContactInitials(String name) {
    if (name.isEmpty) return '?';
    
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else {
      return name[0].toUpperCase();
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _openConversationDetail(SMSConversation conversation) {
    debugPrint('Opening SMS conversation with ${conversation.address}');
    
    // Mark messages as read
    _smsService.markMessagesAsRead(conversation.address);
    
    // Navigate to conversation detail screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SMSConversationScreen(
          conversation: conversation,
          smsService: _smsService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// Lazy loaded SMS list with performance optimizations
class _LazyLoadedSMSList extends StatefulWidget {
  final List<SMSConversation> conversations;
  final Function(SMSConversation) onConversationTap;
  final SMSService smsService;

  const _LazyLoadedSMSList({
    required this.conversations,
    required this.onConversationTap,
    required this.smsService,
  });

  @override
  State<_LazyLoadedSMSList> createState() => _LazyLoadedSMSListState();
}

class _LazyLoadedSMSListState extends State<_LazyLoadedSMSList> {
  final ScrollController _scrollController = ScrollController();
  static const int _itemsPerPage = 20;
  int _currentPage = 1;
  bool _isLoadingMore = false;
  List<SMSConversation> _displayedConversations = [];

  @override
  void initState() {
    super.initState();
    _initializeList();
    _scrollController.addListener(_onScroll);
  }

  void _initializeList() {
    // Load initial batch of conversations
    _displayedConversations = widget.conversations
        .take(_itemsPerPage * _currentPage)
        .toList();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreConversations();
    }
  }

  Future<void> _loadMoreConversations() async {
    if (_isLoadingMore || 
        _displayedConversations.length >= widget.conversations.length) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    // Simulate slight delay for smooth loading
    await Future.delayed(const Duration(milliseconds: 200));

    final int startIndex = _displayedConversations.length;
    final int endIndex = (startIndex + _itemsPerPage)
        .clamp(0, widget.conversations.length);

    if (startIndex < widget.conversations.length) {
      setState(() {
        _displayedConversations.addAll(
          widget.conversations.sublist(startIndex, endIndex)
        );
        _currentPage++;
        _isLoadingMore = false;
      });
    } else {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Performance info (remove in production)
        if (_displayedConversations.length < widget.conversations.length)
          Container(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Showing ${_displayedConversations.length} of ${widget.conversations.length} conversations',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
        
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            // Performance optimizations
            cacheExtent: 1000, // Cache more items for smoother scrolling
            addAutomaticKeepAlives: false, // Don't keep inactive items alive
            addRepaintBoundaries: true, // Optimize repaints
            itemCount: _displayedConversations.length + 
                (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              // Loading indicator at the end
              if (index == _displayedConversations.length) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Loading more conversations...'),
                      ],
                    ),
                  ),
                );
              }

              final conversation = _displayedConversations[index];
              return _OptimizedConversationTile(
                key: ValueKey(conversation.address), // Key for better performance
                conversation: conversation,
                onTap: () => widget.onConversationTap(conversation),
                smsService: widget.smsService,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

/// Optimized conversation tile with better performance
class _OptimizedConversationTile extends StatelessWidget {
  final SMSConversation conversation;
  final VoidCallback onTap;
  final SMSService smsService;

  const _OptimizedConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.smsService,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2, // Subtle shadow for better visual separation
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar with hero animation for smooth transitions
              Hero(
                tag: 'avatar_${conversation.address}',
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    _getContactInitials(conversation.contactName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Conversation details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact name and unread badge row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.contactName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.hasUnreadMessages)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, 
                              vertical: 4
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // Last message preview
                    Text(
                      conversation.lastMessagePreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 14,
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // Date and message count
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(conversation.lastMessageDate),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.message,
                          size: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${conversation.messages.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Navigation arrow
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getContactInitials(String name) {
    if (name.isEmpty) return '?';
    
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else {
      return name[0].toUpperCase();
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// Lazy loaded messages list for conversation details
class _LazyLoadedMessagesList extends StatefulWidget {
  final ScrollController controller;
  final List<SMSMessage> messages;

  const _LazyLoadedMessagesList({
    required this.controller,
    required this.messages,
  });

  @override
  State<_LazyLoadedMessagesList> createState() => _LazyLoadedMessagesListState();
}

class _LazyLoadedMessagesListState extends State<_LazyLoadedMessagesList> {
  static const int _messagesPerPage = 30;
  int _currentPage = 1;
  List<SMSMessage> _displayedMessages = [];
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _initializeMessages();
    widget.controller.addListener(_onScroll);
  }

  void _initializeMessages() {
    // Load initial batch (most recent messages)
    final startIndex = (widget.messages.length - (_messagesPerPage * _currentPage))
        .clamp(0, widget.messages.length);
    _displayedMessages = widget.messages.sublist(startIndex);
  }

  void _onScroll() {
    // Load more when scrolling towards the top (older messages)
    if (widget.controller.position.pixels <= 200 && 
        _displayedMessages.length < widget.messages.length) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    await Future.delayed(const Duration(milliseconds: 150));

    final currentStartIndex = widget.messages.length - _displayedMessages.length;
    final newStartIndex = (currentStartIndex - _messagesPerPage).clamp(0, currentStartIndex);
    
    if (newStartIndex < currentStartIndex) {
      final newMessages = widget.messages.sublist(newStartIndex, currentStartIndex);
      
      setState(() {
        _displayedMessages.insertAll(0, newMessages);
        _currentPage++;
        _isLoadingMore = false;
      });

      // Maintain scroll position
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.controller.hasClients) {
          widget.controller.jumpTo(
            widget.controller.offset + (newMessages.length * 100) // Approximate message height
          );
        }
      });
    } else {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Loading indicator for older messages
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Loading older messages...'),
              ],
            ),
          ),

        Expanded(
          child: ListView.builder(
            controller: widget.controller,
            padding: const EdgeInsets.all(16),
            reverse: false,
            // Performance optimizations
            cacheExtent: 2000,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: _displayedMessages.length,
            itemBuilder: (context, index) {
              final message = _displayedMessages[index];
              return _OptimizedMessageBubble(
                key: ValueKey('${message.id}_${message.date.millisecondsSinceEpoch}'),
                message: message,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }
}

/// Optimized message bubble with better performance
class _OptimizedMessageBubble extends StatelessWidget {
  final SMSMessage message;

  const _OptimizedMessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isReceived = message.isReceived;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isReceived ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isReceived 
                ? Theme.of(context).cardColor
                : AppColors.primary,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.body,
                style: TextStyle(
                  color: isReceived 
                      ? Theme.of(context).textTheme.bodyLarge?.color
                      : Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatMessageTime(message.date),
                    style: TextStyle(
                      color: isReceived 
                          ? Theme.of(context).textTheme.bodySmall?.color
                          : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  if (!isReceived) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// Screen for displaying individual SMS conversation
class SMSConversationScreen extends StatefulWidget {
  final SMSConversation conversation;
  final SMSService smsService;

  const SMSConversationScreen({
    super.key,
    required this.conversation,
    required this.smsService,
  });

  @override
  State<SMSConversationScreen> createState() => _SMSConversationScreenState();
}

class _SMSConversationScreenState extends State<SMSConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Scroll to bottom when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversation.contactName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _callContact(),
            tooltip: 'Call contact',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _LazyLoadedMessagesList(
              controller: _scrollController,
              messages: widget.conversation.messages,
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(SMSMessage message) {
    final isReceived = message.isReceived;
    
    return Align(
      alignment: isReceived ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isReceived 
              ? Theme.of(context).cardColor
              : AppColors.primary,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: TextStyle(
                color: isReceived 
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatMessageTime(message.date),
              style: TextStyle(
                color: isReceived 
                    ? Theme.of(context).textTheme.bodySmall?.color
                    : Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send),
              color: Colors.white,
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMessageTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final success = await widget.smsService.sendSMS(
        address: widget.conversation.address,
        message: message,
      );

      if (success) {
        _messageController.clear();
        
        // Scroll to bottom to show new message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send SMS message'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending SMS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send SMS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _callContact() {
    debugPrint('Calling contact: ${widget.conversation.address}');
    // Here you would implement calling functionality
    // You could use url_launcher to open the phone dialer
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${widget.conversation.contactName}...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}