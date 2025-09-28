import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:camera_service_plugin/camera_service_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// Service for managing camera operations using the camera_service_plugin
/// 
/// This service provides a wrapper around the camera_service_plugin with
/// additional features specific to the HiChat app including:
/// - Error handling with user-friendly messages
/// - File management for captured media
/// - Integration with app's architecture
/// - Caching and storage management
class CameraService {
  static const String _tag = 'CameraService';
  
  // Storage keys for preferences
  static const String _prefKeyLastCaptureTime = 'last_capture_time';
  static const String _prefKeyCaptureCount = 'capture_count';
  
  /// Captures an image using the device camera
  /// 
  /// Returns a [CameraResult] containing the Base64 encoded image data
  /// and metadata about the capture operation.
  /// 
  /// Throws [CameraException] if the operation fails.
  static Future<CameraResult> captureImage() async {
    try {
      final startTime = DateTime.now();
      
      // Call the camera service plugin
      final String? result = await CameraServicePlugin.captureImage();
      
      if (result == null || result.isEmpty) {
        throw CameraException(
          'Image capture failed: No data returned',
          CameraErrorType.captureError,
        );
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      // Update capture statistics
      await _updateCaptureStats('image');
      
      return CameraResult(
        data: result,
        type: MediaType.image,
        size: result.length,
        captureTime: endTime,
        duration: duration,
      );
      
    } on PlatformException catch (e) {
      throw _handlePlatformException(e, 'Image capture');
    } catch (e) {
      throw CameraException(
        'Unexpected error during image capture: $e',
        CameraErrorType.unknown,
      );
    }
  }
  
  /// Records a video using the device camera
  /// 
  /// Returns a [CameraResult] containing the Base64 encoded video data
  /// and metadata about the recording operation.
  /// 
  /// Throws [CameraException] if the operation fails.
  static Future<CameraResult> recordVideo() async {
    try {
      final startTime = DateTime.now();
      
      // Call the camera service plugin
      final String? result = await CameraServicePlugin.recordVideo();
      
      if (result == null || result.isEmpty) {
        throw CameraException(
          'Video recording failed: No data returned',
          CameraErrorType.recordingError,
        );
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      // Update capture statistics
      await _updateCaptureStats('video');
      
      return CameraResult(
        data: result,
        type: MediaType.video,
        size: result.length,
        captureTime: endTime,
        duration: duration,
      );
      
    } on PlatformException catch (e) {
      throw _handlePlatformException(e, 'Video recording');
    } catch (e) {
      throw CameraException(
        'Unexpected error during video recording: $e',
        CameraErrorType.unknown,
      );
    }
  }
  
  /// Records audio using the device microphone
  /// 
  /// Returns a [CameraResult] containing the Base64 encoded audio data
  /// and metadata about the recording operation.
  /// 
  /// Throws [CameraException] if the operation fails.
  static Future<CameraResult> recordAudio() async {
    try {
      final startTime = DateTime.now();
      
      // Call the camera service plugin
      final String? result = await CameraServicePlugin.recordAudio();
      
      if (result == null || result.isEmpty) {
        throw CameraException(
          'Audio recording failed: No data returned',
          CameraErrorType.recordingError,
        );
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      // Update capture statistics
      await _updateCaptureStats('audio');
      
      return CameraResult(
        data: result,
        type: MediaType.audio,
        size: result.length,
        captureTime: endTime,
        duration: duration,
      );
      
    } on PlatformException catch (e) {
      throw _handlePlatformException(e, 'Audio recording');
    } catch (e) {
      throw CameraException(
        'Unexpected error during audio recording: $e',
        CameraErrorType.unknown,
      );
    }
  }
  
  /// Saves Base64 encoded media data to a file
  /// 
  /// [data] - Base64 encoded media data
  /// [filename] - Desired filename (without extension)
  /// [type] - Type of media (image, video, audio)
  /// 
  /// Returns the path to the saved file
  static Future<String> saveMediaToFile(
    String data,
    String filename,
    MediaType type,
  ) async {
    try {
      // Decode Base64 data
      final Uint8List bytes = base64Decode(data);
      
      // Get app documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String mediaDir = '${appDir.path}/media/${type.name}';
      
      // Create media directory if it doesn't exist
      final Directory dir = Directory(mediaDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // Determine file extension based on media type
      String extension;
      switch (type) {
        case MediaType.image:
          extension = 'jpg';
          break;
        case MediaType.video:
          extension = 'mp4';
          break;
        case MediaType.audio:
          extension = 'm4a';
          break;
      }
      
      // Create file path
      final String filePath = '$mediaDir/${filename}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final File file = File(filePath);
      
      // Write bytes to file
      await file.writeAsBytes(bytes);
      
      return filePath;
      
    } catch (e) {
      throw CameraException(
        'Failed to save media file: $e',
        CameraErrorType.fileError,
      );
    }
  }
  
  /// Gets capture statistics from shared preferences
  static Future<CaptureStats> getCaptureStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final lastCaptureTime = prefs.getInt(_prefKeyLastCaptureTime) ?? 0;
      final captureCount = prefs.getInt(_prefKeyCaptureCount) ?? 0;
      
      return CaptureStats(
        totalCaptures: captureCount,
        lastCaptureTime: lastCaptureTime > 0 
          ? DateTime.fromMillisecondsSinceEpoch(lastCaptureTime)
          : null,
      );
    } catch (e) {
      // Return default stats if there's an error
      return CaptureStats(totalCaptures: 0, lastCaptureTime: null);
    }
  }
  
  /// Clears all capture statistics
  static Future<void> clearCaptureStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyLastCaptureTime);
      await prefs.remove(_prefKeyCaptureCount);
    } catch (e) {
      // Silently ignore errors when clearing stats
    }
  }
  
  /// Formats data size for display
  static String formatDataSize(int bytes) {
    if (bytes < 1024) return '$bytes bytes';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  /// Updates capture statistics in shared preferences
  static Future<void> _updateCaptureStats(String mediaType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final currentCount = prefs.getInt(_prefKeyCaptureCount) ?? 0;
      await prefs.setInt(_prefKeyCaptureCount, currentCount + 1);
      await prefs.setInt(_prefKeyLastCaptureTime, DateTime.now().millisecondsSinceEpoch);
      
    } catch (e) {
      // Silently ignore errors when updating stats
    }
  }
  
  /// Handles platform exceptions and converts them to user-friendly messages
  static CameraException _handlePlatformException(PlatformException e, String operation) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return CameraException(
          'Permission denied. Please grant camera and microphone permissions in settings.',
          CameraErrorType.permissionDenied,
        );
      case 'CAMERA_ERROR':
        return CameraException(
          'Camera error occurred. Please try again or restart the app.',
          CameraErrorType.cameraError,
        );
      case 'RECORDING_ERROR':
        return CameraException(
          'Recording failed. Please check if the camera is available and try again.',
          CameraErrorType.recordingError,
        );
      case 'CAPTURE_ERROR':
        return CameraException(
          'Image capture failed. Please try again.',
          CameraErrorType.captureError,
        );
      default:
        return CameraException(
          '$operation failed: ${e.message ?? 'Unknown error'}',
          CameraErrorType.unknown,
        );
    }
  }
}

/// Result of a camera operation
class CameraResult {
  final String data;
  final MediaType type;
  final int size;
  final DateTime captureTime;
  final Duration duration;
  
  CameraResult({
    required this.data,
    required this.type,
    required this.size,
    required this.captureTime,
    required this.duration,
  });
  
  /// Returns formatted file size
  String get formattedSize => CameraService.formatDataSize(size);
  
  /// Returns preview of the data (first 100 characters)
  String get dataPreview {
    return data.length > 100 ? '${data.substring(0, 100)}...' : data;
  }
}

/// Types of media that can be captured
enum MediaType {
  image,
  video,
  audio,
}

/// Camera operation error types
enum CameraErrorType {
  permissionDenied,
  cameraError,
  recordingError,
  captureError,
  fileError,
  unknown,
}

/// Custom exception for camera operations
class CameraException implements Exception {
  final String message;
  final CameraErrorType type;
  
  CameraException(this.message, this.type);
  
  @override
  String toString() => 'CameraException: $message';
  
  /// Returns user-friendly error message
  String get userMessage {
    switch (type) {
      case CameraErrorType.permissionDenied:
        return 'Camera permission is required. Please enable it in app settings.';
      case CameraErrorType.cameraError:
        return 'Camera is not available. Please try again later.';
      case CameraErrorType.recordingError:
        return 'Recording failed. Please check camera availability and try again.';
      case CameraErrorType.captureError:
        return 'Failed to capture image. Please try again.';
      case CameraErrorType.fileError:
        return 'Failed to save media file. Please check storage permissions.';
      case CameraErrorType.unknown:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}

/// Capture statistics data
class CaptureStats {
  final int totalCaptures;
  final DateTime? lastCaptureTime;
  
  CaptureStats({
    required this.totalCaptures,
    this.lastCaptureTime,
  });
}