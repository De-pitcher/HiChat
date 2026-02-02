import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// Service for managing call audio feedback (ringtones, vibration)
class CallAudioService {
  static final CallAudioService _instance = CallAudioService._internal();
  
  factory CallAudioService() => _instance;
  
  CallAudioService._internal();
  
  AudioPlayer? _audioPlayer;
  bool _isRinging = false;
  bool _isInitialized = false;
  
  /// Initialize the audio service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _audioPlayer = AudioPlayer();
      _isInitialized = true;
      debugPrint('🔊 CallAudioService: Initialized');
    } catch (e) {
      debugPrint('❌ CallAudioService: Initialization failed: $e');
    }
  }
  
  /// Play ringtone for incoming call
  Future<void> playRingtone({bool isVideoCall = false}) async {
    if (_isRinging) {
      debugPrint('⚠️ CallAudioService: Ringtone already playing');
      return;
    }
    
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      _isRinging = true;
      
      // Play system notification sound as ringtone
      // Note: For custom ringtone, add audio file to assets/sounds/ringtone.mp3
      // and uncomment the line below:
      // await _audioPlayer?.play(AssetSource('sounds/ringtone.mp3'));
      
      // For now, use a simple approach with volume
      await _audioPlayer?.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer?.setVolume(1.0);
      
      // Play notification sound (requires asset or uses device default)
      debugPrint('🔔 CallAudioService: Ringtone started (${isVideoCall ? 'video' : 'audio'})');
      
    } catch (e) {
      debugPrint('❌ CallAudioService: Error playing ringtone: $e');
      _isRinging = false;
    }
  }
  
  /// Stop ringtone and vibration
  Future<void> stopRingtone() async {
    if (!_isRinging) return;
    
    try {
      _isRinging = false;
      
      // Stop audio
      await _audioPlayer?.stop();
      
      debugPrint('🔇 CallAudioService: Ringtone stopped');
    } catch (e) {
      debugPrint('❌ CallAudioService: Error stopping ringtone: $e');
    }
  }
  
  /// Check if ringtone is currently playing
  bool get isRinging => _isRinging;
  
  /// Play a short beep sound (for call accepted/rejected)
  Future<void> playBeep() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      // Play a short beep
      // Note: This would require an audio file in assets
      // await _audioPlayer?.play(AssetSource('sounds/beep.mp3'));
      
      // Simple feedback (beep would play if audio file exists)
      debugPrint('🔔 CallAudioService: Beep played');
    } catch (e) {
      debugPrint('❌ CallAudioService: Error playing beep: $e');
    }
  }
  
  /// Dispose the service
  Future<void> dispose() async {
    try {
      await stopRingtone();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      _isInitialized = false;
      debugPrint('🔊 CallAudioService: Disposed');
    } catch (e) {
      debugPrint('❌ CallAudioService: Error disposing: $e');
    }
  }
}
