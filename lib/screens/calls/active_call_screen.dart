import 'package:flutter/material.dart';
import '../../services/agora_call_service.dart';
import '../../services/call_signaling_service.dart';

/// Active call screen showing video/audio call with controls
class ActiveCallScreen extends StatefulWidget {
  final String channelName;
  final String remoteUserName;
  final bool isVideoCall;
  final String callId;

  const ActiveCallScreen({
    Key? key,
    required this.channelName,
    required this.remoteUserName,
    required this.isVideoCall,
    required this.callId,
  }) : super(key: key);

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  late AgoraCallService _agoraService;
  late CallSignalingService _signalingService;

  bool _isMuted = false;
  bool _isCameraDisabled = false;
  bool _isSpeakerEnabled = true;
  bool _isNavigatingBack = false; // Flag to prevent double-pop

  int? _remoteUserId;
  Duration _callDuration = Duration.zero;
  late DateTime _callStartTime;

  @override
  void initState() {
    super.initState();
    _agoraService = AgoraCallService();
    _signalingService = CallSignalingService();
    _callStartTime = DateTime.now();

    // Listen to Agora events
    _listenToAgoraEvents();

    // Update call duration every second
    _startCallDurationTimer();

    debugPrint(
        '🎥 ActiveCallScreen: Call started with ${widget.remoteUserName} (${widget.isVideoCall ? 'video' : 'audio'})');
  }

  @override
  void dispose() {
    _agoraService.dispose();
    super.dispose();
  }

  /// Listen to Agora events
  void _listenToAgoraEvents() {
    _agoraService.callEvents.listen((event) {
      debugPrint('🎥 ActiveCallScreen: Agora event - ${event.type}: ${event.message}');

      switch (event.type) {
        case CallEventType.remoteUserJoined:
          setState(() {
            _remoteUserId = event.userId;
          });
          debugPrint('👤 ActiveCallScreen: Remote user joined: $_remoteUserId');
          break;

        case CallEventType.remoteUserLeft:
          setState(() {
            _remoteUserId = null;
          });
          debugPrint('👤 ActiveCallScreen: Remote user left');
          break;

        case CallEventType.channelLeft:
        case CallEventType.callEnded:
        case CallEventType.error:
          if (mounted && !_isNavigatingBack) {
            _isNavigatingBack = true;
            Navigator.of(context).pop();
          }
          break;

        default:
          break;
      }
    });
  }

  /// Start timer to update call duration
  void _startCallDurationTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime);
        });
      }
      return mounted;
    });
  }

  /// Format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Handle mute toggle
  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    await _agoraService.muteMicrophone(_isMuted);
    debugPrint('🎤 ActiveCallScreen: Microphone ${_isMuted ? 'muted' : 'unmuted'}');
  }

  /// Handle camera toggle
  Future<void> _toggleCamera() async {
    setState(() => _isCameraDisabled = !_isCameraDisabled);
    await _agoraService.disableCamera(_isCameraDisabled);
    debugPrint('🎥 ActiveCallScreen: Camera ${_isCameraDisabled ? 'disabled' : 'enabled'}');
  }

  /// Handle speaker toggle
  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerEnabled = !_isSpeakerEnabled);
    await _agoraService.enableSpeaker(_isSpeakerEnabled);
    debugPrint('🔊 ActiveCallScreen: Speaker ${_isSpeakerEnabled ? 'enabled' : 'disabled'}');
  }

  /// Handle camera switch (front/back)
  Future<void> _switchCamera() async {
    if (!widget.isVideoCall) return;

    await _agoraService.switchCamera();
    debugPrint('🎥 ActiveCallScreen: Camera switched');
  }

  /// Handle end call
  Future<void> _endCall() async {
    if (_isNavigatingBack) return; // Prevent multiple end calls
    
    debugPrint('🎤 ActiveCallScreen: Ending call...');

    try {
      // End Agora call
      await _agoraService.endCall();

      // Send end call signal
      final durationSeconds = _callDuration.inSeconds;
      await _signalingService.endCall(
        widget.callId,
        durationSeconds: durationSeconds,
      );

      if (mounted && !_isNavigatingBack) {
        _isNavigatingBack = true;
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ ActiveCallScreen: Error ending call: $e');
      if (mounted && !_isNavigatingBack) {
        _isNavigatingBack = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent back button from closing without ending call
        await _endCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Remote video/placeholder
            if (widget.isVideoCall)
              _buildRemoteVideo()
            else
              _buildAudioCallPlaceholder(),

            // Top bar with caller info and call duration
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.remoteUserName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _formatDuration(_callDuration),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Control buttons at bottom
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // First row: Mute, Camera, Speaker
                      if (widget.isVideoCall) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildControlButton(
                              icon: _isMuted ? Icons.mic_off : Icons.mic,
                              label: _isMuted ? 'Unmute' : 'Mute',
                              color: _isMuted ? Colors.red : Colors.grey[700]!,
                              onPressed: _toggleMute,
                            ),
                            _buildControlButton(
                              icon: _isCameraDisabled ? Icons.videocam_off : Icons.videocam,
                              label: _isCameraDisabled ? 'Camera Off' : 'Camera On',
                              color: _isCameraDisabled ? Colors.red : Colors.grey[700]!,
                              onPressed: _toggleCamera,
                            ),
                            _buildControlButton(
                              icon: _isSpeakerEnabled ? Icons.volume_up : Icons.volume_off,
                              label: _isSpeakerEnabled ? 'Speaker' : 'Phone',
                              color: Colors.grey[700]!,
                              onPressed: _toggleSpeaker,
                            ),
                            _buildControlButton(
                              icon: Icons.flip_camera_android,
                              label: 'Flip',
                              color: Colors.grey[700]!,
                              onPressed: _switchCamera,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        // Audio call controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildControlButton(
                              icon: _isMuted ? Icons.mic_off : Icons.mic,
                              label: _isMuted ? 'Unmute' : 'Mute',
                              color: _isMuted ? Colors.red : Colors.grey[700]!,
                              onPressed: _toggleMute,
                            ),
                            _buildControlButton(
                              icon: _isSpeakerEnabled ? Icons.volume_up : Icons.volume_off,
                              label: _isSpeakerEnabled ? 'Speaker' : 'Phone',
                              color: Colors.grey[700]!,
                              onPressed: _toggleSpeaker,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // End call button (full width)
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: _endCall,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.call_end, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'End Call',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build remote video area
  Widget _buildRemoteVideo() {
    return Container(
      color: Colors.black,
      child: _remoteUserId != null
          ? Center(
              child: Text(
                'Video Stream (UID: $_remoteUserId)',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[700],
                    ),
                    child: Center(
                      child: Text(
                        widget.remoteUserName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.remoteUserName,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Waiting for video...',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Build audio call placeholder
  Widget _buildAudioCallPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[700],
              ),
              child: Center(
                child: Text(
                  widget.remoteUserName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.remoteUserName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Voice Call · ${_formatDuration(_callDuration)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build control button
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                icon,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
