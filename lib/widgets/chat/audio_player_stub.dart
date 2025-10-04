// Stub file for platforms that don't support audio playback
// This file is used when audio playback is not available

import 'dart:async';

/// Player state (stub implementation)
enum PlayerState {
  stopped,
  playing,
  paused,
  completed,
}

/// Audio player (stub implementation)
class AudioPlayer {
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;
  Stream<Duration> get onDurationChanged => _durationController.stream;
  Stream<Duration> get onPositionChanged => _positionController.stream;
  Stream<void> get onPlayerComplete => _completeController.stream;

  final StreamController<PlayerState> _stateController = StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<void> _completeController = StreamController<void>.broadcast();

  Future<void> play(Source source) async {
    throw UnsupportedError('Audio playback is not supported on this platform');
  }

  Future<void> pause() async {
    // No-op for stub
  }

  Future<void> dispose() async {
    await _stateController.close();
    await _durationController.close();
    await _positionController.close();
    await _completeController.close();
  }
}

/// Audio source (stub implementation)
abstract class Source {}

/// Device file source (stub implementation)
class DeviceFileSource extends Source {
  DeviceFileSource(this.path);
  final String path;
}