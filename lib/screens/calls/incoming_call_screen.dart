import 'package:flutter/material.dart';
import '../../services/call_signaling_service.dart';
import '../../services/agora_call_service.dart';
import '../../services/call_audio_service.dart';

/// Full-screen incoming call notification
/// Displays caller information and allows user to accept/reject the call
class IncomingCallScreen extends StatefulWidget {
  final CallInvitation invitation;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;

  const IncomingCallScreen({
    Key? key,
    required this.invitation,
    required this.onAccepted,
    required this.onRejected,
  }) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final CallSignalingService _signalingService = CallSignalingService();
  final AgoraCallService _agoraService = AgoraCallService();
  final CallAudioService _audioService = CallAudioService();

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    // Setup pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playRingtone();
    debugPrint(
        '📱 IncomingCallScreen: Incoming ${widget.invitation.isVideoCall ? 'video' : 'audio'} call from ${widget.invitation.fromUserName}');
  }

  @override
  void dispose() {
    // Stop ringtone when screen closes
    _audioService.stopRingtone();
    _pulseController.dispose();
    super.dispose();
  }

  /// Play ringtone for incoming call
  void _playRingtone() {
    try {
      _audioService.playRingtone(isVideoCall: widget.invitation.isVideoCall);
      debugPrint('🔔 IncomingCallScreen: Ringtone playing...');
    } catch (e) {
      debugPrint('❌ IncomingCallScreen: Error playing ringtone: $e');
    }
  }

  /// Handle accept button press
  Future<void> _handleAccept() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Stop ringtone and play acceptance beep
      await _audioService.stopRingtone();
      await _audioService.playBeep();
      
      debugPrint('✅ IncomingCallScreen: Accepting call from ${widget.invitation.fromUserName}...');

      // Accept via signaling service - send to correct chat and user
      await _signalingService.acceptCall(
        widget.invitation.callId,
        channelName: widget.invitation.channelName,
        chatId: widget.invitation.chatId,
        toUserId: widget.invitation.fromUserId,
      );

      // Initialize Agora call
      final success = await _agoraService.initiateCall(
        channelName: widget.invitation.channelName,
        uid: widget.invitation.fromUserId.hashCode.abs() % 100000,
        videoCall: widget.invitation.isVideoCall,
      );

      if (success) {
        widget.onAccepted();
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to join call')),
          );
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      debugPrint('❌ IncomingCallScreen: Error accepting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Handle reject button press
  Future<void> _handleReject() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Stop ringtone and play rejection beep
      await _audioService.stopRingtone();
      await _audioService.playBeep();
      
      debugPrint('❌ IncomingCallScreen: Rejecting call from ${widget.invitation.fromUserName}...');

      await _signalingService.rejectCall(
        widget.invitation.callId,
        reason: 'User declined',
        chatId: widget.invitation.chatId,
        toUserId: widget.invitation.fromUserId,
      );

      widget.onRejected();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ IncomingCallScreen: Error rejecting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey[900]!,
                  const Color(0xFF1F1F1F),
                ],
              ),
            ),
          ),

          // Main content
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Caller avatar with pulse effect
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse ring
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 180 + (_pulseAnimation.value * 40),
                            height: 180 + (_pulseAnimation.value * 40),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.green
                                    .withOpacity(0.3 * (1 - _pulseAnimation.value)),
                                width: 3,
                              ),
                            ),
                          );
                        },
                      ),

                      // Avatar
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[700],
                          border: Border.all(
                            color: Colors.green,
                            width: 3,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.invitation.fromUserName
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Caller name
                  Text(
                    widget.invitation.fromUserName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Call type
                  Text(
                    widget.invitation.isVideoCall ? 'Video Call' : 'Voice Call',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Accept and Reject buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Reject button
                      _buildActionButton(
                        onPressed: _isProcessing ? null : _handleReject,
                        icon: Icons.call_end,
                        backgroundColor: Colors.red,
                        size: 64,
                      ),

                      const SizedBox(width: 48),

                      // Accept button
                      _buildActionButton(
                        onPressed: _isProcessing ? null : _handleAccept,
                        icon: Icons.call,
                        backgroundColor: Colors.green,
                        size: 64,
                      ),
                    ],
                  ),

                  // Loading indicator
                  if (_isProcessing) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Close button (top-right)
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close),
                color: Colors.white,
                onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build action button with icon
  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required Color backgroundColor,
    required double size,
  }) {
    return Material(
      color: backgroundColor,
      shape: CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }
}

/// Call overlay manager - Shows incoming call as overlay
class CallOverlayManager {
  static OverlayEntry? _overlayEntry;

  /// Show incoming call overlay
  static void showIncomingCall(
    BuildContext context, {
    required CallInvitation invitation,
    required VoidCallback onAccepted,
    required VoidCallback onRejected,
  }) {
    _overlayEntry?.remove();

    _overlayEntry = OverlayEntry(
      builder: (context) => IncomingCallScreen(
        invitation: invitation,
        onAccepted: onAccepted,
        onRejected: onRejected,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    debugPrint('📱 CallOverlayManager: Incoming call overlay shown');
  }

  /// Hide incoming call overlay
  static void hideIncomingCall() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    debugPrint('📱 CallOverlayManager: Incoming call overlay hidden');
  }
}
