import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';

/// Audio recording service with mobile platform support
class AudioRecordingService {
  static final AudioRecordingService _instance = AudioRecordingService._internal();
  factory AudioRecordingService() => _instance;
  AudioRecordingService._internal();

  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;

  /// Duration stream for recording updates
  Stream<Duration> get durationStream => _durationController.stream;

  /// Check if recording permission is granted
  Future<bool> hasPermission() async {
    // Check if we're on a supported platform
    if (!_isMobilePlatform()) {
      if (kDebugMode) {
        print('Audio recording only supported on iOS and Android');
      }
      return false;
    }

    try {
      final status = await Permission.microphone.status;
      return status == PermissionStatus.granted;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking microphone permission: $e');
      }
      return false;
    }
  }

  /// Request recording permission
  Future<bool> requestPermission() async {
    if (!_isMobilePlatform()) {
      return false;
    }

    try {
      final status = await Permission.microphone.request();
      return status == PermissionStatus.granted;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting microphone permission: $e');
      }
      return false;
    }
  }

  /// Start recording audio  
  Future<bool> startRecording() async {
    if (!_isMobilePlatform()) {
      if (kDebugMode) {
        print('Audio recording not supported on this platform');
      }
      return false;
    }

    try {
      // Check permissions first
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) {
          if (kDebugMode) {
            print('Microphone permission denied');
          }
          return false;
        }
      }

      // Initialize recorder if needed
      _recorder ??= FlutterSoundRecorder();
      
      // Open the recorder session
      await _recorder!.openRecorder();

      // Get recording path
      final audioDir = await _getAudioCacheDir();
      final fileName = _generateAudioFileName();
      _currentRecordingPath = '${audioDir.path}/$fileName';

      // Start recording with AAC codec
      await _recorder!.startRecorder(
        toFile: _currentRecordingPath!,
        codec: Codec.aacADTS,
        bitRate: 64000, // 64kbps - good for voice
        sampleRate: 22050, // 22kHz - sufficient for voice
        numChannels: 1, // Mono for voice messages
      );
      
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _startDurationTimer();

      if (kDebugMode) {
        print('✅ Started recording to: $_currentRecordingPath');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start recording: $e');
      }
      _isRecording = false;
      _currentRecordingPath = null;
      return false;
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    if (!_isMobilePlatform() || _recorder == null || !_isRecording) {
      _isRecording = false;
      _currentRecordingPath = null;
      return null;
    }

    try {
      _stopDurationTimer();
      
      final path = await _recorder!.stopRecorder();
      _isRecording = false;
      
      if (kDebugMode) {
        print('✅ Stopped recording, saved to: $path');
      }

      // Verify file exists and has content
      if (path != null && File(path).existsSync()) {
        final fileSize = File(path).lengthSync();
        if (fileSize > 0) {
          if (kDebugMode) {
            print('📁 Audio file size: ${fileSize} bytes');
          }
          final recordingPath = _currentRecordingPath;
          _currentRecordingPath = null;
          return recordingPath ?? path;
        } else {
          if (kDebugMode) {
            print('⚠️ Audio file is empty, deleting');
          }
          try {
            File(path).deleteSync();
          } catch (e) {
            if (kDebugMode) {
              print('Error deleting empty audio file: $e');
            }
          }
        }
      }

      _currentRecordingPath = null;
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error stopping recording: $e');
      }
      _isRecording = false;
      _currentRecordingPath = null;
      return null;
    }
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    if (!_isMobilePlatform() || _recorder == null || !_isRecording) {
      _isRecording = false;
      _currentRecordingPath = null;
      return;
    }

    try {
      _stopDurationTimer();
      await _recorder!.stopRecorder();
      _isRecording = false;

      // Delete the cancelled recording file
      if (_currentRecordingPath != null && File(_currentRecordingPath!).existsSync()) {
        try {
          await File(_currentRecordingPath!).delete();
          if (kDebugMode) {
            print('🗑️ Deleted cancelled recording');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error deleting cancelled recording: $e');
          }
        }
      }

      _currentRecordingPath = null;
    } catch (e) {
      if (kDebugMode) {
        print('Error cancelling recording: $e');
      }
      _isRecording = false;
      _currentRecordingPath = null;
    }
  }

  /// Get recording duration
  Duration getRecordingDuration() {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Clean up resources
  Future<void> dispose() async {
    await cancelRecording();
    _stopDurationTimer();
    await _durationController.close();
    await _recorder?.closeRecorder();
    _recorder = null;
  }

  /// Check if we're on a mobile platform that supports audio recording
  bool _isMobilePlatform() {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Start the duration timer for UI updates
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isRecording && _recordingStartTime != null) {
        final duration = DateTime.now().difference(_recordingStartTime!);
        if (!_durationController.isClosed) {
          _durationController.add(duration);
        }
      }
    });
  }

  /// Stop the duration timer
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  /// Get the cache directory for audio files
  Future<Directory> _getAudioCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDir.path}/audio_cache');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  /// Generate a unique filename for audio recording
  String _generateAudioFileName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'audio_${timestamp}.aac';
  }
}