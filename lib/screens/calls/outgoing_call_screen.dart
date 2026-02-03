import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/call_signaling_service.dart';
import '../../services/agora_call_service.dart';
import '../../services/auth_state_manager.dart';
import '../../services/chat_state_manager.dart';
import 'active_call_screen.dart';

/// Screen shown when initiating a call - shows "Calling..." and waits for answer
class OutgoingCallScreen extends StatefulWidget {
  final String channelName;
  final String remoteUserName;
  final String remoteUserId;
  final bool isVideoCall;
  final String callId;

  const OutgoingCallScreen({
    super.key,
    required this.channelName,
    required this.remoteUserName,
    required this.remoteUserId,
    required this.isVideoCall,
    required this.callId,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  late CallSignalingService _signalingService;
  late AgoraCallService _agoraService;
  late ChatStateManager _chatStateManager;
  bool _isCallAccepted = false;
  bool _isCallRejected = false;

  @override
  void initState() {
    super.initState();
    _signalingService = CallSignalingService();
    _agoraService = AgoraCallService();
    _chatStateManager = ChatStateManager.instance;
    _listenForCallResponse();
  }

  /// Listen for call acceptance or rejection
  void _listenForCallResponse() {
    _chatStateManager.callStateChanges.listen((stateChange) {
      if (stateChange.callId != widget.callId) return;

      debugPrint('📞 OutgoingCallScreen: Received call state change: ${stateChange.type}');

      if (stateChange.type == CallStateType.callAccepted) {
        setState(() {
          _isCallAccepted = true;
        });
        _navigateToActiveCall();
      } else if (stateChange.type == CallStateType.callRejected) {
        setState(() {
          _isCallRejected = true;
        });
        _handleCallRejected();
      } else if (stateChange.type == CallStateType.callCancelled) {
        // Call was cancelled by the other user
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  /// Navigate to active call screen when call is accepted
  Future<void> _navigateToActiveCall() async {
    if (!mounted) return;

    try {
      debugPrint('📞 OutgoingCallScreen: Call accepted, initiating Agora call...');
      
      // Get auth token from AuthStateManager
      final authManager = context.read<AuthStateManager>();
      final authToken = authManager.currentUser?.token;
      
      if (authToken == null) {
        debugPrint('❌ OutgoingCallScreen: No auth token available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication error. Please log in again.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      // Calculate UID from user ID
      final uid = authManager.currentUser!.id.hashCode.abs() % 100000;

      // Initiate Agora call with auth token
      final success = await _agoraService.initiateCall(
        channelName: widget.channelName,
        uid: uid,
        videoCall: widget.isVideoCall,
        authToken: authToken,
      );

      if (!success) {
        debugPrint('❌ OutgoingCallScreen: Failed to initiate Agora call');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to call'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      debugPrint('✅ OutgoingCallScreen: Agora call initiated, navigating to ActiveCallScreen');

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ActiveCallScreen(
            channelName: widget.channelName,
            remoteUserName: widget.remoteUserName,
            isVideoCall: widget.isVideoCall,
            callId: widget.callId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ OutgoingCallScreen: Error navigating to active call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting to call: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  /// Handle call rejection
  void _handleCallRejected() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.remoteUserName} declined the call'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );

    // Close screen after a brief delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  /// Cancel the call
  Future<void> _cancelCall() async {
    try {
      await _signalingService.sendCallCancellation(
        toUserId: widget.remoteUserId,
        callId: widget.callId,
      );
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ OutgoingCallScreen: Error cancelling call: $e');
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // User avatar
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[800],
                    ),
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.grey[400],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // User name
                  Text(
                    widget.remoteUserName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Call status
                  if (_isCallRejected)
                    const Text(
                      'Call Declined',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.red,
                      ),
                    )
                  else if (_isCallAccepted)
                    const Text(
                      'Connecting...',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.green,
                      ),
                    )
                  else
                    Column(
                      children: [
                        Text(
                          widget.isVideoCall ? 'Video calling...' : 'Calling...',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Pulsing indicator
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.grey[400]!,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 64),

                  // Call type icon
                  Icon(
                    widget.isVideoCall ? Icons.videocam : Icons.call,
                    size: 32,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),

            // Cancel button (bottom center)
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.red,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _isCallAccepted || _isCallRejected ? null : _cancelCall,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
