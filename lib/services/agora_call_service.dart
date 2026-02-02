import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;

/// Agora Call Service for handling audio/video calls
/// Manages real-time communication using Agora SDK
class AgoraCallService {
  static const String _tag = 'AgoraCallService';
  
  // Agora App ID - MUST be set before using service
  static const String AGORA_APP_ID = '9d6f9392e0ff44a7838c091757a70615';
  
  static final AgoraCallService _instance = AgoraCallService._internal();
  
  factory AgoraCallService() => _instance;
  
  AgoraCallService._internal();
  
  // Agora SDK instance
  late RtcEngine _agoraEngine;
  
  // Call state
  bool _isInitialized = false;
  bool _isCallActive = false;
  int? _remoteUserId;
  
  // Event streams
  final StreamController<CallEvent> _callEventController = StreamController<CallEvent>.broadcast();
  Stream<CallEvent> get callEvents => _callEventController.stream;
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isCallActive => _isCallActive;
  int? get remoteUserId => _remoteUserId;
  
  /// Ensure Agora SDK is initialized - lazy initialization
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    await initialize();
  }
  
  /// Initialize Agora SDK
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('🎤 AgoraCallService: Already initialized');
      return;
    }
    
    try {
      debugPrint('🎤 AgoraCallService: Initializing Agora SDK...');
      
      // Create Agora RTC Engine
      _agoraEngine = createAgoraRtcEngine();
      
      // Initialize with App ID
      await _agoraEngine.initialize(RtcEngineContext(appId: AGORA_APP_ID));
      debugPrint('🎤 AgoraCallService: RTC Engine initialized with App ID');
      
      // Setup event listeners
      _setupEventListeners();
      
      // Enable video
      await _agoraEngine.enableVideo();
      debugPrint('🎤 AgoraCallService: Video enabled');
      
      // Setup audio
      await _agoraEngine.enableAudio();
      debugPrint('🎤 AgoraCallService: Audio enabled');
      
      _isInitialized = true;
      _callEventController.add(CallEvent(
        type: CallEventType.initialized,
        message: 'Agora SDK initialized successfully',
      ));
      
      debugPrint('✅ AgoraCallService: Initialization completed successfully');
    } catch (e) {
      debugPrint('❌ AgoraCallService: Initialization failed: $e');
      developer.log('Agora initialization error: $e', name: _tag, level: 1000);
      rethrow;
    }
  }
  
  /// Setup Agora event listeners
  void _setupEventListeners() {
    _agoraEngine.registerEventHandler(
      RtcEngineEventHandler(
        onError: (err, msg) {
          final errorMessage = msg.isNotEmpty ? msg : 'Error code: ${err.name} (${err.index})';
          debugPrint('❌ Agora Error: $errorMessage');
          _callEventController.add(CallEvent(
            type: CallEventType.error,
            message: 'Agora error: $errorMessage',
          ));
        },
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('✅ AgoraCallService: Joined channel successfully');
          _callEventController.add(CallEvent(
            type: CallEventType.channelJoined,
            message: 'Successfully joined channel',
          ));
        },
        onLeaveChannel: (connection, stats) {
          debugPrint('🎤 AgoraCallService: Left channel');
          _isCallActive = false;
          _remoteUserId = null;
          _callEventController.add(CallEvent(
            type: CallEventType.channelLeft,
            message: 'Left channel',
          ));
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('👤 AgoraCallService: Remote user joined: $remoteUid');
          _remoteUserId = remoteUid;
          _callEventController.add(CallEvent(
            type: CallEventType.remoteUserJoined,
            message: 'Remote user joined',
            userId: remoteUid,
          ));
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('👤 AgoraCallService: Remote user left: $remoteUid (reason: $reason)');
          _remoteUserId = null;
          _callEventController.add(CallEvent(
            type: CallEventType.remoteUserLeft,
            message: 'Remote user left',
            userId: remoteUid,
          ));
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          debugPrint('⚠️ AgoraCallService: Token will expire soon');
          _callEventController.add(CallEvent(
            type: CallEventType.tokenExpiring,
            message: 'Token will expire',
          ));
        },
      ),
    );
    debugPrint('🎤 AgoraCallService: Event listeners registered');
  }
  
  /// Request call permissions (microphone and camera)
  Future<bool> requestCallPermissions({bool videoCall = false}) async {
    try {
      debugPrint('🔐 AgoraCallService: Requesting call permissions (video: $videoCall)...');
      
      final permissions = [
        Permission.microphone,
        if (videoCall) Permission.camera,
      ];
      
      final results = await permissions.request();
      
      final allGranted = results.values.every((status) => status.isGranted);
      
      if (allGranted) {
        debugPrint('✅ AgoraCallService: All permissions granted');
      } else {
        debugPrint('❌ AgoraCallService: Some permissions denied');
        results.forEach((permission, status) {
          debugPrint('  - $permission: $status');
        });
      }
      
      return allGranted;
    } catch (e) {
      debugPrint('❌ AgoraCallService: Permission request error: $e');
      return false;
    }
  }
  
  /// Initiate a call
  Future<bool> initiateCall({
    required String channelName,
    required int uid,
    required bool videoCall,
  }) async {
    try {
      await _ensureInitialized();
      
      debugPrint('📞 AgoraCallService: Initiating call (channel: $channelName, video: $videoCall)...');
      
      // Request permissions
      final hasPermissions = await requestCallPermissions(videoCall: videoCall);
      if (!hasPermissions) {
        debugPrint('❌ AgoraCallService: Permissions not granted');
        return false;
      }
      
      // Set client role (host/audience)
      // For version 6.3.0, use default options
      debugPrint('🎤 AgoraCallService: Client role configured');
      
      // Setup video if it's a video call
      if (videoCall) {
        await _agoraEngine.enableVideo();
        await _agoraEngine.startPreview();
        debugPrint('🎥 AgoraCallService: Video preview started');
      } else {
        await _agoraEngine.disableVideo();
        debugPrint('🎤 AgoraCallService: Video disabled for audio-only call');
      }
      
      // Join channel
      await _agoraEngine.joinChannel(
        token: '', // Token not required for testing, generate from backend in production
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(),
      );
      
      _isCallActive = true;
      debugPrint('✅ AgoraCallService: Call initiated successfully');
      
      _callEventController.add(CallEvent(
        type: CallEventType.callInitiated,
        message: 'Call initiated successfully',
      ));
      
      return true;
    } catch (e) {
      debugPrint('❌ AgoraCallService: Failed to initiate call: $e');
      developer.log('Call initiation error: $e', name: _tag, level: 1000);
      _callEventController.add(CallEvent(
        type: CallEventType.error,
        message: 'Failed to initiate call: $e',
      ));
      return false;
    }
  }
  
  /// End the current call
  Future<void> endCall() async {
    try {
      await _ensureInitialized();
      if (!_isCallActive) {
        debugPrint('⚠️ AgoraCallService: No active call to end');
        return;
      }
      
      debugPrint('🎤 AgoraCallService: Ending call...');
      
      await _agoraEngine.leaveChannel();
      _isCallActive = false;
      _remoteUserId = null;
      
      debugPrint('✅ AgoraCallService: Call ended successfully');
      
      _callEventController.add(CallEvent(
        type: CallEventType.callEnded,
        message: 'Call ended',
      ));
    } catch (e) {
      debugPrint('❌ AgoraCallService: Error ending call: $e');
      developer.log('Call end error: $e', name: _tag, level: 1000);
    }
  }
  
  /// Mute microphone
  Future<void> muteMicrophone(bool mute) async {
    try {
      await _ensureInitialized();
      await _agoraEngine.muteLocalAudioStream(mute);
      debugPrint('🎤 AgoraCallService: Microphone ${mute ? 'muted' : 'unmuted'}');
    } catch (e) {
      debugPrint('❌ AgoraCallService: Error toggling microphone: $e');
    }
  }
  
  /// Disable camera
  Future<void> disableCamera(bool disable) async {
    try {
      await _ensureInitialized();
      await _agoraEngine.muteLocalVideoStream(disable);
      debugPrint('🎥 AgoraCallService: Camera ${disable ? 'disabled' : 'enabled'}');
    } catch (e) {
      debugPrint('❌ AgoraCallService: Error toggling camera: $e');
    }
  }
  
  /// Switch between front and back camera
  Future<void> switchCamera() async {
    try {
      await _ensureInitialized();
      await _agoraEngine.switchCamera();
      debugPrint('🎥 AgoraCallService: Camera switched');
    } catch (e) {
      debugPrint('❌ AgoraCallService: Error switching camera: $e');
    }
  }
  
  /// Enable speaker
  Future<void> enableSpeaker(bool enable) async {
    try {
      await _ensureInitialized();
      await _agoraEngine.setEnableSpeakerphone(enable);
      debugPrint('🔊 AgoraCallService: Speaker ${enable ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('❌ AgoraCallService: Error toggling speaker: $e');
    }
  }
  
  /// Dispose and cleanup
  Future<void> dispose() async {
    try {
      if (!_isInitialized) {
        debugPrint('⚠️ AgoraCallService: Not initialized, skipping disposal');
        return;
      }
      
      if (_isCallActive) {
        await endCall();
      }
      
      await _agoraEngine.release();
      await _callEventController.close();
      
      _isInitialized = false;
      debugPrint('✅ AgoraCallService: Disposed successfully');
    } catch (e) {
      debugPrint('❌ AgoraCallService: Error disposing: $e');
    }
  }
}

/// Call event types
enum CallEventType {
  initialized,           // SDK initialized
  callInitiated,         // Call started
  callEnded,            // Call ended
  channelJoined,        // Joined channel successfully
  channelLeft,          // Left channel
  remoteUserJoined,     // Remote user joined call
  remoteUserLeft,       // Remote user left call
  error,                // Error occurred
  tokenExpiring,        // Token about to expire
  permissionDenied,     // Permission not granted
}

/// Call event model
class CallEvent {
  final CallEventType type;
  final String message;
  final int? userId;
  final dynamic data;
  final DateTime timestamp;
  
  CallEvent({
    required this.type,
    required this.message,
    this.userId,
    this.data,
  }) : timestamp = DateTime.now();
  
  @override
  String toString() => 'CallEvent(type: $type, message: $message, userId: $userId)';
}

/// Call information model
class CallInfo {
  final String channelName;
  final int localUserId;
  final String? remoteUserName;
  final int? remoteUserId;
  final bool isVideoCall;
  final DateTime startTime;
  
  CallInfo({
    required this.channelName,
    required this.localUserId,
    this.remoteUserName,
    this.remoteUserId,
    required this.isVideoCall,
    required this.startTime,
  });
  
  Duration get duration => DateTime.now().difference(startTime);
}
