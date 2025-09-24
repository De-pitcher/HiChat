import 'dart:async';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';

class ChatService {
  final List<Chat> _chats = [];
  final Map<String, List<Message>> _messages = {};
  final _chatsController = StreamController<List<Chat>>.broadcast();
  final _messagesController = StreamController<List<Message>>.broadcast();

  Stream<List<Chat>> get chatsStream => _chatsController.stream;
  Stream<List<Message>> get messagesStream => _messagesController.stream;

  List<Chat> get chats => List.unmodifiable(_chats);

  Future<List<Chat>> loadChats({required String userId}) async {
    // TODO: Implement actual API call to load chats
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Mock data for demonstration
    final mockChats = _generateMockChats();
    _chats.clear();
    _chats.addAll(mockChats);
    _chatsController.add(_chats);
    
    return _chats;
  }

  Future<List<Message>> loadMessages({required String chatId}) async {
    // TODO: Implement actual API call to load messages
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Mock data for demonstration
    final mockMessages = _generateMockMessages(chatId);
    _messages[chatId] = mockMessages;
    _messagesController.add(mockMessages);
    
    return mockMessages;
  }

  Future<Message> sendMessage({
    required String chatId,
    required String senderId,
    required String content,
    MessageType type = MessageType.text,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: senderId,
      content: content,
      type: type,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
      replyToMessageId: replyToMessageId,
      metadata: metadata,
    );

    // Add message to local storage immediately
    _addMessageToChat(message);

    try {
      // TODO: Send message to server
      await Future.delayed(const Duration(seconds: 1)); // Simulate API call

      // Update message status to sent
      final sentMessage = message.copyWith(status: MessageStatus.sent);
      _updateMessageInChat(sentMessage);

      // Update chat's last message and activity
      _updateChatLastMessage(chatId, sentMessage);

      return sentMessage;
    } catch (e) {
      // Update message status to failed
      final failedMessage = message.copyWith(status: MessageStatus.failed);
      _updateMessageInChat(failedMessage);
      rethrow;
    }
  }

  Future<Chat> createDirectChat({
    required String currentUserId,
    required String otherUserId,
    required User otherUser,
  }) async {
    // TODO: Implement actual API call to create chat
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    final chat = Chat(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: otherUser.username,
      type: ChatType.direct,
      participantIds: [currentUserId, otherUserId],
      participants: [otherUser],
      lastActivity: DateTime.now(),
      createdAt: DateTime.now(),
    );

    _chats.add(chat);
    _chatsController.add(_chats);
    
    return chat;
  }

  Future<Chat> createGroupChat({
    required String currentUserId,
    required String name,
    required List<String> participantIds,
    required List<User> participants,
    String? description,
    String? groupImageUrl,
  }) async {
    // TODO: Implement actual API call to create group chat
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    final chat = Chat(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: ChatType.group,
      participantIds: [currentUserId, ...participantIds],
      participants: participants,
      lastActivity: DateTime.now(),
      description: description,
      groupImageUrl: groupImageUrl,
      createdBy: currentUserId,
      createdAt: DateTime.now(),
    );

    _chats.add(chat);
    _chatsController.add(_chats);
    
    return chat;
  }

  Future<void> markMessagesAsRead({
    required String chatId,
    required String userId,
  }) async {
    // TODO: Implement actual API call to mark messages as read
    
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Update local chat unread count
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(unreadCount: 0);
      _chatsController.add(_chats);
    }
  }

  Future<void> deleteMessage({
    required String messageId,
    required String chatId,
  }) async {
    // TODO: Implement actual API call to delete message
    
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    final messages = _messages[chatId];
    if (messages != null) {
      messages.removeWhere((m) => m.id == messageId);
      _messagesController.add(messages);
    }
  }

  Future<List<User>> searchUsers({required String query}) async {
    // TODO: Implement actual API call to search users
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Mock search results
    return [
      User(
        id: 1,
        username: 'john_doe',
        email: 'john@example.com',
        isOnline: true,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      User(
        id: 2,
        username: 'alice_smith',
        email: 'alice@example.com',
        isOnline: false,
        lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
    ].where((user) => 
      user.username.toLowerCase().contains(query.toLowerCase()) ||
      user.email.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  void _addMessageToChat(Message message) {
    final messages = _messages[message.chatId] ?? [];
    messages.add(message);
    _messages[message.chatId] = messages;
    _messagesController.add(messages);
  }

  void _updateMessageInChat(Message updatedMessage) {
    final messages = _messages[updatedMessage.chatId];
    if (messages != null) {
      final index = messages.indexWhere((m) => m.id == updatedMessage.id);
      if (index != -1) {
        messages[index] = updatedMessage;
        _messagesController.add(messages);
      }
    }
  }

  void _updateChatLastMessage(String chatId, Message message) {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        lastMessage: message,
        lastActivity: message.timestamp,
      );
      _chatsController.add(_chats);
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

  List<Message> _generateMockMessages(String chatId) {
    final now = DateTime.now();
    return [
      Message(
        id: '1',
        chatId: chatId,
        senderId: 'user1',
        content: 'Hey! How are you doing?',
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      Message(
        id: '2',
        chatId: chatId,
        senderId: 'currentUser',
        content: 'I\'m doing great! Thanks for asking. How about you?',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 55)),
      ),
      Message(
        id: '3',
        chatId: chatId,
        senderId: 'user1',
        content: 'Pretty good! Just working on some Flutter projects.',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 50)),
      ),
      Message(
        id: '4',
        chatId: chatId,
        senderId: 'currentUser',
        content: 'That sounds awesome! Flutter is really great for mobile development.',
        timestamp: now.subtract(const Duration(minutes: 5)),
      ),
    ];
  }

  void dispose() {
    _chatsController.close();
    _messagesController.close();
  }
}