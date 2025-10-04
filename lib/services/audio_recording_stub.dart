// Stub file for platforms that don't support audio recording
// This file is used when audio recording is not available

import 'dart:async';

/// Configuration for recording (stub implementation)
class RecordConfig {
  const RecordConfig({
    this.encoder,
    this.sampleRate,
    this.bitRate,
    this.numChannels,
  });

  final Object? encoder;
  final int? sampleRate;
  final int? bitRate;
  final int? numChannels;
}

/// Audio encoder types (stub implementation)
class AudioEncoder {
  static const Object aacLc = 'aac_lc';
}

/// Audio recorder (stub implementation)
class AudioRecorder {
  Future<void> start(RecordConfig config, {String? path}) async {
    throw UnsupportedError('Audio recording is not supported on this platform');
  }

  Future<String?> stop() async {
    throw UnsupportedError('Audio recording is not supported on this platform');
  }

  Future<void> dispose() async {
    // No-op for stub
  }

  Future<RecordAmplitude> getAmplitude() async {
    return RecordAmplitude(current: 0.0, max: 0.0);
  }
}

/// Record amplitude (stub implementation)  
class RecordAmplitude {
  const RecordAmplitude({required this.current, required this.max});
  
  final double current;
  final double max;
}