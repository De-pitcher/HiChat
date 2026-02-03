// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/chat_state_manager.dart';
import '../../services/auth_state_manager.dart';
import '../../services/native_camera_service.dart';
import '../../services/chat_state_persistence_manager.dart';
import '../../services/enhanced_chat_scroll_controller.dart';
import '../../services/call_signaling_service.dart';
import '../../screens/calls/outgoing_call_screen.dart';

import '../../widgets/chat/image_message_card_enhanced.dart';
import '../../widgets/chat/audio_message_card.dart';
import '../../widgets/chat/call_message_card.dart';
import '../../widgets/chat/date_separator.dart';
import '../../utils/date_utils.dart' as date_utils;

/// String extension for capitalize method
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

/// Enhanced Chat Screen with WhatsApp-like caching and scroll behavior
class EnhancedChatScreen extends StatefulWidget {
  final Chat chat;

  const EnhancedChatScreen({super.key, required this.chat});

  @override
  State<EnhancedChatScreen> createState() => _EnhancedChatScreenState();
}

class _EnhancedChatScreenState extends State<EnhancedChatScreen>
    with WidgetsBindingObserver {
  
  ChatStatePersistenceManager? _persistenceManager;
  int _lastMessageCount = 0;
  bool _isInitialLoad = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Load messages for this chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _persistenceManager?.onChatInvisible();
        break;
      case AppLifecycleState.resumed:
        _persistenceManager?.onChatVisible();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Load messages for this chat
  Future<void> _loadMessages() async {
    final chatStateManager = context.read<ChatStateManager>();
    final authStateManager = context.read<AuthStateManager>();
    final currentUserId = authStateManager.currentUser?.id.toString();
    
    if (currentUserId != null) {
      // Initialize chat state manager if needed
      if (!chatStateManager.isInitialized) {
        await chatStateManager.initialize(currentUserId);
      }
      
      // Load messages (will use cache first, then WebSocket)
      await chatStateManager.loadMessagesForChat(widget.chat.id);
      
      debugPrint('📱 Enhanced chat messages loaded for chat: ${widget.chat.id}');
    }
  }

  /// Clinical scroll implementation - waits for proper render cycle
  void _scrollToBottom(EnhancedChatScrollController scrollController) {
    // Step 1: Wait for current build cycle to complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.scrollController.hasClients) return;
      
      // Step 2: Wait for layout pass to complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.scrollController.hasClients) return;
        
        // Step 3: Give additional time for media widgets to initialize
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && scrollController.scrollController.hasClients) {
            final position = scrollController.scrollController.position;
            // Jump directly to max extent (no animation to avoid timing issues)
            position.jumpTo(position.maxScrollExtent);
            debugPrint('📱 Clinical scroll completed: jumped to ${position.maxScrollExtent}');
          }
        });
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Send text message using persistence manager
  Future<void> _sendMessage(ChatStatePersistenceManager manager) async {
    final content = manager.messageController.text.trim();
    if (content.isEmpty) return;

    final authManager = context.read<AuthStateManager>();
    final chatStateManager = context.read<ChatStateManager>();
    final currentUserId = authManager.currentUser?.id.toString() ?? 'currentUser';

    try {
      // Get receiver ID - for direct chats, it's the other participant
      int? receiverId;
      if (widget.chat.type == ChatType.direct && widget.chat.participants.isNotEmpty) {
        final otherParticipant = widget.chat.participants.firstWhere(
          (p) => p.id.toString() != currentUserId,
          orElse: () => widget.chat.participants.first,
        );
        receiverId = otherParticipant.id;
      }

      // Create message for optimistic UI
      final message = Message(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: currentUserId,
        content: content,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.text,
      );

      // Handle in persistence manager
      await manager.onMessageSent(message);

      // Send via chat state manager
      await chatStateManager.sendMessage(
        chatId: widget.chat.id,
        content: content,
        type: 'text',
        receiverId: receiverId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  /// Send multimedia message
  Future<void> _sendMultimediaMessage(
    NativeCameraResult mediaResult,
    ChatStatePersistenceManager manager,
  ) async {
    debugPrint('💬 Enhanced ChatScreen: Starting multimedia message send');

    final chatStateManager = context.read<ChatStateManager>();
    final authManager = context.read<AuthStateManager>();
    final currentUserId = authManager.currentUser?.id.toString() ?? 'currentUser';

    try {
      // Get receiver ID
      int? receiverId;
      if (widget.chat.type == ChatType.direct && widget.chat.participants.isNotEmpty) {
        final otherParticipant = widget.chat.participants.firstWhere(
          (p) => p.id.toString() != currentUserId,
          orElse: () => widget.chat.participants.first,
        );
        receiverId = otherParticipant.id;
      }

      // Create optimistic message
      final message = Message(
        id: 'temp_media_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: currentUserId,
        content: 'Uploading ${mediaResult.type.name}...',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: mediaResult.isImage ? MessageType.image : MessageType.video,
        metadata: {
          'local_path': mediaResult.path,
          'file_size': mediaResult.size,
          'is_uploading': true,
        },
      );

      // Handle in persistence manager
      await manager.onMessageSent(message);

      // Show upload progress
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text('Uploading ${mediaResult.type.name}...'),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );

      await chatStateManager.sendMultimediaMessage(
        chatId: widget.chat.id,
        mediaResult: mediaResult,
        receiverId: receiverId,
        onUploadProgress: (progress) {
          debugPrint('Upload progress: ${(progress * 100).round()}%');
        },
      );

      // Hide progress and show success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('${mediaResult.type.name.capitalize()} sent successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Failed to send multimedia message: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to send ${mediaResult.type.name}: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Handle camera capture
  Future<void> _handleCameraResult(ChatStatePersistenceManager manager) async {
    try {
      final result = await NativeCameraService.showMediaSelectionDialog(
        context,
        allowGallery: false,
        allowImage: true,
        allowVideo: true,
      );

      if (result != null) {
        await _sendMultimediaMessage(result, manager);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle gallery selection
  Future<void> _handleGallerySelection(ChatStatePersistenceManager manager) async {
    try {
      final result = await NativeCameraService.showMediaSelectionDialog(
        context,
        allowCamera: false,
        allowGallery: true,
        allowImage: true,
        allowVideo: true,
      );

      if (result != null) {
        await _sendMultimediaMessage(result, manager);
      }
    } catch (e) {
      debugPrint('Gallery error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gallery error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle message retry
  Future<void> _handleMessageRetry(Message message, ChatStatePersistenceManager manager) async {
    debugPrint('🔄 Retrying message: ${message.id}');

    final chatStateManager = context.read<ChatStateManager>();

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text('Retrying ${message.type.name}...'),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );

      await chatStateManager.retryFailedMessage(message);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('${message.type.name.capitalize()} sent successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Retry failed: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChatStatePersistenceProvider(
      chatId: widget.chat.id,
      builder: (manager) {
        _persistenceManager = manager;
        
        return Scaffold(
          appBar: _buildAppBar(context),
          body: _buildBody(context, manager),
        );
      },
    );
  }

  AppBar _buildAppBar(BuildContext context) {
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
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary,
            child: widget.chat.getDisplayImage(currentUserId) != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      widget.chat.getDisplayImage(currentUserId)!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Text(
                          widget.chat.getDisplayName(currentUserId)[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  )
                : Text(
                    widget.chat.getDisplayName(currentUserId)[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.chat.getDisplayName(currentUserId),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.chat.isDirectChat) ...[
                  Text(
                    'Online', // TODO: Get actual online status
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                    ),
                  ),
                ] else ...[
                  Text(
                    '${widget.chat.participantIds.length} members',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.call,
            color: Theme.of(context).brightness == Brightness.light
                ? AppColors.primary
                : Colors.white,
          ),
          onPressed: () => _initiateCall(isVideoCall: false),
        ),
        IconButton(
          icon: Icon(
            Icons.videocam,
            color: Theme.of(context).brightness == Brightness.light
                ? AppColors.primary
                : Colors.white,
          ),
          onPressed: () => _initiateCall(isVideoCall: true),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'info':
                // TODO: Show chat info
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
            const PopupMenuItem(value: 'mute', child: Text('Mute notifications')),
            const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ChatStatePersistenceManager manager) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).cardColor,
          ],
          stops: const [0.0, 0.3],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildMessageList(context, manager),
                ScrollToBottomButton(scrollController: manager.scrollController),
              ],
            ),
          ),
          _buildMessageInput(context, manager),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, ChatStatePersistenceManager manager) {
    // Use Selector to explicitly watch the messages for this chat
    return Selector<ChatStateManager, List<Message>>(
      selector: (context, chatStateManager) {
        final messages = chatStateManager.getMessagesForChat(widget.chat.id);
        return messages;
      },
      builder: (context, messages, child) {
        final chatStateManager = context.read<ChatStateManager>();
        final currentUserId = chatStateManager.getCurrentUserIdForUI();
        final isLoading = chatStateManager.isLoading;

        // Clinical scroll behavior: always scroll to bottom for new content
        if (messages.isNotEmpty) {
          final currentMessageCount = messages.length;
          
          if (_isInitialLoad || currentMessageCount > _lastMessageCount) {
            // Scroll to bottom for initial load or new messages
            _scrollToBottom(manager.scrollController);
            
            if (_isInitialLoad) {
              _isInitialLoad = false;
            }
            _lastMessageCount = currentMessageCount;
          }
        }

        if (isLoading && messages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(strokeWidth: 3),
                SizedBox(height: 16),
                Text('Loading messages...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        if (messages.isEmpty && !isLoading) {
          return _buildEmptyState(context, chatStateManager);
        }

        // Group messages by date
        final groupedItems = date_utils.DateUtils.groupMessagesByDate(messages);

        return NotificationListener<ScrollNotification>(
          onNotification: (scrollNotification) {
            // Simple scroll handling - no complex logic
            return false;
          },
          child: ListView.builder(
            controller: manager.scrollController.scrollController,
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            physics: const ClampingScrollPhysics(), // More predictable scrolling
            itemCount: groupedItems.length,
            cacheExtent: 0, // Don't cache off-screen items that might affect scroll calculation
            itemBuilder: (context, index) {
              final item = groupedItems[index];

              // Date separator
              if (item is date_utils.DateSeparatorItem) {
                return DateSeparator(date: item.date);
              }

              // Message
              final message = item as Message;
              final isCurrentUser = message.senderId == currentUserId;

              return _EnhancedMessageBubble(
                key: ValueKey('message_${message.id}'),
                message: message,
                isCurrentUser: isCurrentUser,
                chat: widget.chat,
                onRetry: (msg) => _handleMessageRetry(msg, manager),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, ChatStateManager chatStateManager) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No messages yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send the first message to start the conversation!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
          if (!chatStateManager.isConnected) ...[
            const SizedBox(height: 16),
            Text(
              'Connecting...',
              style: TextStyle(
                color: Colors.orange[600],
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Initiate a call with the chat user
  void _initiateCall({required bool isVideoCall}) async {
    try {
      debugPrint(
          '📞 EnhancedChatScreen: Initiating ${isVideoCall ? 'video' : 'voice'} call with ${widget.chat.name}');

      final signalingService = CallSignalingService();
      final channelName = 'call_${widget.chat.id}_${DateTime.now().millisecondsSinceEpoch}';
      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}_${widget.chat.id}';

      debugPrint('📞 EnhancedChatScreen: Created call - ID: $callId, Channel: $channelName');

      // Navigate to outgoing call screen FIRST (so it can listen for responses)
      if (mounted) {
        debugPrint('📞 EnhancedChatScreen: Navigating to OutgoingCallScreen...');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OutgoingCallScreen(
              channelName: channelName,
              remoteUserName: widget.chat.name,
              remoteUserId: widget.chat.id.toString(),
              isVideoCall: isVideoCall,
              callId: callId,
            ),
          ),
        );
        debugPrint('📞 EnhancedChatScreen: Navigation initiated');
      }

      // THEN send call invitation (screen is already listening)
      debugPrint('📞 EnhancedChatScreen: Sending call invitation...');
      await signalingService.sendCallInvitation(
        toUserId: widget.chat.id,
        toUserName: widget.chat.name,
        channelName: channelName,
        isVideoCall: isVideoCall,
      );
      debugPrint('📞 EnhancedChatScreen: Call invitation sent successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Calling ${widget.chat.name}... (${isVideoCall ? 'video' : 'voice'} call)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ EnhancedChatScreen: Error initiating call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMessageInput(BuildContext context, ChatStatePersistenceManager manager) {
    return _EnhancedMessageInput(
      manager: manager,
      onSend: () => _sendMessage(manager),
      onCameraPressed: () => _handleCameraResult(manager),
      onGalleryPressed: () => _handleGallerySelection(manager),
      chat: widget.chat,
    );
  }
}

/// Enhanced message bubble with improved performance
class _EnhancedMessageBubble extends StatelessWidget {
  final Message message;
  final bool isCurrentUser;
  final Chat chat;
  final Function(Message)? onRetry;

  const _EnhancedMessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.chat,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: isCurrentUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[
            Container(
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  _getSenderName()[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: _buildMessageContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    // Handle different message types
    if (message.isImage || message.isVideo) {
      return ImageMessageCard(
        message: message,
        isCurrentUser: isCurrentUser,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    if (message.isAudio) {
      return AudioMessageCard(
        message: message,
        isCurrentUser: isCurrentUser,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    if (message.isCall) {
      return CallMessageCard(
        message: message,
        isCurrentUser: isCurrentUser,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    // Text message
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: () => _showMessageOptions(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: isCurrentUser
                ? LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isCurrentUser ? null : Colors.grey[100],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isCurrentUser ? 20 : 4),
              bottomRight: Radius.circular(isCurrentUser ? 4 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: isCurrentUser
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isCurrentUser && chat.isGroupChat) ...[
                Text(
                  _getSenderName(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.content,
                style: TextStyle(
                  color: isCurrentUser ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurrentUser
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.grey[600],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (isCurrentUser) ...[
                    const SizedBox(width: 6),
                    Icon(
                      _getStatusIcon(),
                      size: 16,
                      color: _getStatusColor(),
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

  void _showMessageOptions(BuildContext context) {
    // Implement message options (copy, reply, etc.)
    // Similar to original implementation
  }

  String _getSenderName() {
    // TODO: Get actual sender name from participants
    return 'User';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  IconData _getStatusIcon() {
    switch (message.status) {
      case MessageStatus.pending:
      case MessageStatus.sending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
      case MessageStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _getStatusColor() {
    switch (message.status) {
      case MessageStatus.pending:
      case MessageStatus.sending:
      case MessageStatus.sent:
      case MessageStatus.delivered:
        return Colors.white.withValues(alpha: 0.7);
      case MessageStatus.read:
        return Colors.lightBlue[200]!;
      case MessageStatus.failed:
        return Colors.red[300]!;
    }
  }
}

/// Enhanced message input with integrated controls
class _EnhancedMessageInput extends StatelessWidget {
  final ChatStatePersistenceManager manager;
  final VoidCallback onSend;
  final VoidCallback onCameraPressed;
  final VoidCallback onGalleryPressed;
  final Chat chat;

  const _EnhancedMessageInput({
    required this.manager,
    required this.onSend,
    required this.onCameraPressed,
    required this.onGalleryPressed,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button
            Container(
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showAttachmentOptions(context),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      size: 24,
                      color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),

            // Text input field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, maxHeight: 120),
                child: TextField(
                  controller: manager.messageController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    suffixIcon: Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: Icon(
                          Icons.emoji_emotions_outlined,
                          color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                          size: 24,
                        ),
                        onPressed: () {
                          // TODO: Show emoji picker
                        },
                        splashRadius: 20,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (manager.hasDraft()) onSend();
                  },
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: manager.hasDraft() ? onSend : null,
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: manager.hasDraft()
                        ? LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              Colors.grey[300]!,
                              Colors.grey[400]!,
                            ],
                          ),
                    shape: BoxShape.circle,
                    boxShadow: manager.hasDraft()
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    size: 24,
                    color: manager.hasDraft() ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    onCameraPressed();
                  },
                ),
                _AttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    onGalleryPressed();
                  },
                ),
                _AttachmentOption(
                  icon: Icons.location_on,
                  label: 'Location',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Share location
                  },
                ),
                _AttachmentOption(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Pick document
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}