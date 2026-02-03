import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'chat_websocket_service.dart';

/// Call signaling service for sending/receiving call invitations via WebSocket
/// Integrates with the existing chat WebSocket to handle call state synchronization
class CallSignalingService {
  static const String _tag = 'CallSignalingService';
  
  static final CallSignalingService _instance = CallSignalingService._internal();
  
  factory CallSignalingService() => _instance;
  
  CallSignalingService._internal();
  
  late ChatWebSocketService _chatWebSocketService;
  bool _initialized = false;
  
  // Stream for incoming call invitations
  final StreamController<CallInvitation> _incomingCallController = StreamController<CallInvitation>.broadcast();
  Stream<CallInvitation> get incomingCalls => _incomingCallController.stream;
  
  // Stream for call state changes
  final StreamController<CallStateChange> _callStateController = StreamController<CallStateChange>.broadcast();
  Stream<CallStateChange> get callStateChanges => _callStateController.stream;
  
  String? _currentUserId;
  
  /// Ensure the signaling service is initialized - lazy initialization
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    
    try {
      _chatWebSocketService = ChatWebSocketService.instance;
      _initialized = true;
      debugPrint('✅ CallSignalingService: Lazy initialized');
    } catch (e) {
      debugPrint('❌ CallSignalingService: Lazy initialization failed: $e');
      developer.log('Signaling service init error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// Initialize the signaling service
  Future<void> initialize(String userId) async {
    try {
      _currentUserId = userId;
      await _ensureInitialized();
      debugPrint('✅ CallSignalingService: Initialized for user $userId');
    } catch (e) {
      debugPrint('❌ CallSignalingService: Initialization failed: $e');
      developer.log('Signaling service init error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /* Unused - call signaling messages are sent via WebSocket, not received here yet
  void _handleSignalingMessage(Map<String, dynamic> message) {
    try {
      final messageType = message['type'] as String?;
      
      switch (messageType) {
        case 'call_invitation':
          _handleCallInvitation(message);
          break;
          
        case 'call_accepted':
          _handleCallAccepted(message);
          break;
          
        case 'call_rejected':
          _handleCallRejected(message);
          break;
          
        case 'call_ended':
          _handleCallEnded(message);
          break;
          
        case 'call_missed':
          _handleCallMissed(message);
          break;
          
        default:
          // Not a call-related message
          break;
      }
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error handling message: $e');
      developer.log('Message handling error: $e', name: _tag, level: 1000);
    }
  }
  
  /// Handle incoming call invitation
  void _handleCallInvitation(Map<String, dynamic> message) {
    try {
      final invitation = CallInvitation(
        callId: message['call_id'] as String,
        fromUserId: message['from_user_id'] as String,
        fromUserName: message['from_user_name'] as String,
        channelName: message['channel_name'] as String,
        isVideoCall: message['is_video_call'] as bool? ?? false,
        timestamp: DateTime.parse(message['timestamp'] as String? ?? DateTime.now().toIso8601String()),
      );
      
      debugPrint('📞 CallSignalingService: Incoming call invitation from ${invitation.fromUserName}');
      _incomingCallController.add(invitation);
      
      _callStateController.add(CallStateChange(
        type: CallStateType.incomingCall,
        callId: invitation.callId,
        fromUserId: invitation.fromUserId,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error handling call invitation: $e');
      developer.log('Invitation handling error: $e', name: _tag, level: 1000);
    }
  }
  
  /// Handle call acceptance notification
  void _handleCallAccepted(Map<String, dynamic> message) {
    try {
      final callId = message['call_id'] as String?;
      final channelName = message['channel_name'] as String?;
      
      debugPrint('✅ CallSignalingService: Call $callId accepted');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callAccepted,
        callId: callId,
        channelName: channelName,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error handling call accepted: $e');
    }
  }
  
  /// Handle call rejection notification
  void _handleCallRejected(Map<String, dynamic> message) {
    try {
      final callId = message['call_id'] as String?;
      final reason = message['reason'] as String? ?? 'User declined';
      
      debugPrint('❌ CallSignalingService: Call $callId rejected - $reason');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callRejected,
        callId: callId,
        message: reason,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error handling call rejected: $e');
    }
  }
  
  /// Handle call ended notification
  void _handleCallEnded(Map<String, dynamic> message) {
    try {
      final callId = message['call_id'] as String?;
      final duration = message['duration'] as int?; // seconds
      
      debugPrint('🎤 CallSignalingService: Call $callId ended (duration: ${duration}s)');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callEnded,
        callId: callId,
        duration: duration,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error handling call ended: $e');
    }
  }
  
  /// Handle missed call notification
  void _handleCallMissed(Map<String, dynamic> message) {
    try {
      final callId = message['call_id'] as String?;
      final fromUserName = message['from_user_name'] as String?;
      
      debugPrint('📵 CallSignalingService: Missed call from $fromUserName');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callMissed,
        callId: callId,
        message: 'Missed call from $fromUserName',
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error handling missed call: $e');
    }
  }
  */ // End unused handlers
  
  /// Send call invitation via WebSocket
  Future<void> sendCallInvitation({
    required String callId,
    required String toUserId,
    required String toUserName,
    required String channelName,
    required bool isVideoCall,
  }) async {
    try {
      await _ensureInitialized();
      
      // Create message payload
      final message = {
        'type': 'call_invitation',
        'call_id': callId,
        'from_user_id': _currentUserId,
        'to_user_id': toUserId,
        'to_user_name': toUserName,
        'channel_name': channelName,
        'is_video_call': isVideoCall,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send via ChatWebSocketService using proper interface
      final toUserIdInt = int.tryParse(toUserId) ?? 0;
      _chatWebSocketService.sendMessage(
        chatId: toUserIdInt.toString(), // Convert to string for chat ID
        receiverId: toUserIdInt,
        content: jsonEncode(message),
        type: 'call_invitation',
      );
      
      debugPrint('📞 CallSignalingService: Call invitation sent to $toUserName (ID: $callId)');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callInitiated,
        callId: callId,
        toUserId: toUserId,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error sending call invitation: $e');
      developer.log('Send invitation error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// Accept incoming call
  Future<void> acceptCall(
    String callId, {
    String? channelName,
    String? chatId,
    String? toUserId,
  }) async {
    try {
      await _ensureInitialized();
      final message = {
        'type': 'call_accepted',
        'call_id': callId,
        'channel_name': channelName,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send to the correct chat and user who initiated the call
      final receiverIdInt = int.tryParse(toUserId ?? '0') ?? 0;
      
      _chatWebSocketService.sendMessage(
        chatId: chatId ?? '0',
        receiverId: receiverIdInt,
        content: jsonEncode(message),
        type: 'call_accepted',
      );
      debugPrint('✅ CallSignalingService: Call $callId accepted, sent to chat $chatId, user $toUserId');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callAccepted,
        callId: callId,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error accepting call: $e');
      developer.log('Accept call error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// Reject incoming call
  Future<void> rejectCall(
    String callId, {
    String reason = 'User declined',
    String? chatId,
    String? toUserId,
  }) async {
    try {
      await _ensureInitialized();
      final message = {
        'type': 'call_rejected',
        'call_id': callId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send to the correct chat and user who initiated the call
      final receiverIdInt = int.tryParse(toUserId ?? '0') ?? 0;
      
      _chatWebSocketService.sendMessage(
        chatId: chatId ?? '0',
        receiverId: receiverIdInt,
        content: jsonEncode(message),
        type: 'call_rejected',
      );
      debugPrint('❌ CallSignalingService: Call $callId rejected - $reason, sent to chat $chatId, user $toUserId');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callRejected,
        callId: callId,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error rejecting call: $e');
      developer.log('Reject call error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// Cancel outgoing call (before it's answered)
  Future<void> sendCallCancellation({
    required String toUserId,
    required String callId,
  }) async {
    try {
      await _ensureInitialized();
      final message = {
        'type': 'call_cancelled',
        'call_id': callId,
        'from_user_id': _currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final toUserIdInt = int.tryParse(toUserId) ?? 0;
      _chatWebSocketService.sendMessage(
        chatId: toUserIdInt.toString(),
        receiverId: toUserIdInt,
        content: jsonEncode(message),
        type: 'call_cancelled',
      );
      debugPrint('📵 CallSignalingService: Call $callId cancelled');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callCancelled,
        callId: callId,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error cancelling call: $e');
      developer.log('Cancel call error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// End call
  Future<void> endCall(String callId, {int? durationSeconds}) async {
    try {
      await _ensureInitialized();
      final message = {
        'type': 'call_ended',
        'call_id': callId,
        'duration': durationSeconds ?? 0,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      _chatWebSocketService.sendMessage(
        chatId: '0', // Use numeric string for system messages
        receiverId: 0,
        content: jsonEncode(message),
        type: 'call_ended',
      );
      debugPrint('🎤 CallSignalingService: Call $callId ended');
      
      _callStateController.add(CallStateChange(
        type: CallStateType.callEnded,
        callId: callId,
      ));
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error ending call: $e');
      developer.log('End call error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// Generate unique call ID
  
  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _incomingCallController.close();
      await _callStateController.close();
      debugPrint('✅ CallSignalingService: Disposed');
    } catch (e) {
      debugPrint('❌ CallSignalingService: Error disposing: $e');
    }
  }
}

/// Call invitation model
class CallInvitation {
  final String callId;
  final String fromUserId;
  final String fromUserName;
  final String channelName;
  final bool isVideoCall;
  final DateTime timestamp;
  final String? chatId; // Chat ID to send responses to
  
  CallInvitation({
    required this.callId,
    required this.fromUserId,
    required this.fromUserName,
    required this.channelName,
    required this.isVideoCall,
    required this.timestamp,
    this.chatId,
  });
  
  @override
  String toString() => 'CallInvitation(callId: $callId, from: $fromUserName, video: $isVideoCall, chat: $chatId)';
}

/// Call state change model
class CallStateChange {
  final CallStateType type;
  final String? callId;
  final String? fromUserId;
  final String? toUserId;
  final String? channelName;
  final String? message;
  final int? duration;
  final DateTime timestamp;
  
  CallStateChange({
    required this.type,
    this.callId,
    this.fromUserId,
    this.toUserId,
    this.channelName,
    this.message,
    this.duration,
  }) : timestamp = DateTime.now();
  
  @override
  String toString() => 'CallStateChange(type: $type, callId: $callId)';
}

/// Call state types
enum CallStateType {
  callInitiated,        // Outgoing call started
  incomingCall,         // Incoming call received
  callAccepted,         // Call accepted
  callRejected,         // Call rejected
  callCancelled,        // Call cancelled by caller
  callEnded,            // Call ended
  callMissed,           // Call missed
  error,                // Error occurred
}
