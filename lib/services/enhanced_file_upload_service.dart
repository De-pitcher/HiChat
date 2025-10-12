import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import '../constants/app_constants.dart';
import 'native_camera_service.dart';
import 'local_media_cache_service.dart';

/// Enhanced service for uploading media files with local caching support
/// 
/// Handles file upload with progress tracking, local caching using timestamps,
/// and proper error handling for multimedia messages in chat conversations.
class EnhancedFileUploadService {
  static const String _tag = 'EnhancedFileUploadService';
  static const String _uploadEndpoint = '/api/media/';
  static const Duration _uploadTimeout = Duration(minutes: 2); // Increased to 2 minutes for large videos
  static const int _maxRetries = 3;
  
  // Base URL from app constants, fallback to production server
  static const String _baseUrl = 'https://chatcornerbackend-production.up.railway.app';
  
  // Local cache service instance
  static final LocalMediaCacheService _cacheService = LocalMediaCacheService();

  /// Upload media file from camera service result with local caching
  /// 
  /// [result] - CameraResult containing Base64 encoded media data
  /// [chatId] - ID of the chat where the media will be sent
  /// [onProgress] - Optional callback for upload progress (0.0 to 1.0)
  /// 
  /// Returns [EnhancedUploadResult] with file URL, timestamp, and metadata
  static Future<EnhancedUploadResult> uploadMediaWithCaching(
    NativeCameraResult result,
    String chatId, {
    Function(double)? onProgress,
  }) async {
    debugPrint('$_tag: Starting media upload with caching for chat: $chatId');
    
    try {
      // Validate file size
      if (result.size > AppConstants.maxFileSize) {
        throw FileUploadException(
          'File size (${result.formattedSize}) exceeds maximum allowed size (${_formatBytes(AppConstants.maxFileSize)})',
          FileUploadErrorType.fileTooLarge,
        );
      }
      
      // Use the file bytes directly from NativeCameraResult
      final Uint8List fileBytes = result.data;
      
      // Save media locally first and get timestamp
      debugPrint('🚀 Saving media locally: type=${_convertToLocalMediaType(result.type)}, size=${fileBytes.length}');
      final timestamp = await _cacheService.saveMediaLocally(
        data: fileBytes,
        type: _convertToLocalMediaType(result.type),
        originalFilename: 'media_${DateTime.now().millisecondsSinceEpoch}.${_getFileExtension(result.type)}',
      );
      debugPrint('🚀 Media saved with timestamp: $timestamp');

      if (timestamp == null) {
        throw FileUploadException(
          'Failed to save media locally',
          FileUploadErrorType.localCacheError,
        );
      }

      if (onProgress != null) {
        onProgress(0.2); // Local save complete
      }
      
      // Set progress callback if provided
      if (onProgress != null) {
        onProgress(0.3); // Starting upload
      }
      
      // Send request with retry mechanism (creates fresh request for each attempt)
      final response = await _sendWithRetry(
        fileBytes,
        _convertToLocalMediaType(result.type),
        timestamp,
        onProgress,
      );
      
      // Parse response
      final uploadResult = await _parseUploadResponse(response, result, timestamp);
      
      debugPrint('$_tag: Upload successful - URL: ${uploadResult.fileUrl}, Timestamp: ${uploadResult.timestamp}');
      return uploadResult;
      
    } catch (e) {
      debugPrint('$_tag: Upload failed: $e');
      if (onProgress != null) {
        onProgress(0.0); // Reset progress on error
      }
      rethrow;
    }
  }
  
  /// Create multipart request for file upload
  static Future<http.MultipartRequest> _createMultipartRequest(
    Uint8List fileBytes,
    MediaType mediaType,
    String timestamp,
  ) async {
    final uri = Uri.parse('$_baseUrl$_uploadEndpoint');
    final request = http.MultipartRequest('POST', uri);
    
    // Add headers
    request.headers.addAll({
      'Accept': 'application/json',
      'User-Agent': 'HiChat/1.0',
    });
    
    // Create filename with timestamp
    final filename = '$timestamp.${_getFileExtension(_convertToCameraMediaType(mediaType))}';
    
    // Add file data
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
      contentType: http_parser.MediaType.parse(_getMimeType(_convertToCameraMediaType(mediaType))),
    );
    
    request.files.add(multipartFile);
    
    // Add additional fields if needed
    request.fields['type'] = mediaType.name;
    request.fields['timestamp'] = timestamp;
    
    debugPrint('$_tag: Created multipart request for $filename (${fileBytes.length} bytes)');
    return request;
  }
  
  /// Send request with retry mechanism and progress tracking
  static Future<http.StreamedResponse> _sendWithRetry(
    Uint8List fileBytes,
    MediaType mediaType,
    String timestamp,
    Function(double)? onProgress,
  ) async {
    int attempts = 0;
    
    while (attempts < _maxRetries) {
      attempts++;
      
      try {
        debugPrint('$_tag: Upload attempt $attempts/$_maxRetries');
        
        if (onProgress != null) {
          final baseProgress = 0.3 + (0.6 * (attempts - 1) / _maxRetries);
          onProgress(baseProgress);
        }
        
        // Create a fresh request for each attempt
        final request = await _createMultipartRequest(fileBytes, mediaType, timestamp);
        final response = await request.send().timeout(_uploadTimeout);
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (onProgress != null) {
            onProgress(0.9); // Upload complete, parsing response
          }
          return response;
        } else {
          debugPrint('$_tag: HTTP ${response.statusCode} on attempt $attempts');
          if (attempts == _maxRetries) {
            throw FileUploadException(
              'Upload failed with HTTP ${response.statusCode}',
              FileUploadErrorType.serverError,
            );
          }
        }
      } catch (e) {
        debugPrint('$_tag: Attempt $attempts failed: $e');
        if (attempts == _maxRetries) {
          if (e is FileUploadException) {
            rethrow;
          }
          throw FileUploadException(
            'Upload failed after $_maxRetries attempts: $e',
            FileUploadErrorType.networkError,
          );
        }
        
        // Wait before retry
        await Future.delayed(Duration(seconds: attempts));
      }
    }
    
    throw FileUploadException(
      'Upload failed after $_maxRetries attempts',
      FileUploadErrorType.networkError,
    );
  }
  
  /// Parse upload response and create result
  static Future<EnhancedUploadResult> _parseUploadResponse(
    http.StreamedResponse response,
    NativeCameraResult originalResult,
    String timestamp,
  ) async {
    try {
      final responseBody = await response.stream.bytesToString();
      final Map<String, dynamic> responseData = json.decode(responseBody);
      
      if (responseData['success'] == true || responseData['file_url'] != null) {
        final fileUrl = responseData['file_url'] as String? ?? responseData['url'] as String?;
        
        if (fileUrl == null) {
          throw FileUploadException(
            'No file URL in response',
            FileUploadErrorType.serverError,
          );
        }
        
        // Get metadata from cache
        final metadata = _cacheService.getMediaMetadata(timestamp);
        
        return EnhancedUploadResult(
          fileUrl: fileUrl,
          timestamp: timestamp,
          fileSize: originalResult.size,
          fileType: _convertToLocalMediaType(originalResult.type),
          fileName: '$timestamp.${_getFileExtension(originalResult.type)}',
          duration: metadata?.getFormattedDuration(),
          thumbnailPath: metadata?.thumbnailPath,
          success: true,
        );
      } else {
        final error = responseData['error'] as String? ?? 'Unknown server error';
        throw FileUploadException(
          'Server error: $error',
          FileUploadErrorType.serverError,
        );
      }
    } catch (e) {
      if (e is FileUploadException) {
        rethrow;
      }
      throw FileUploadException(
        'Failed to parse response: $e',
        FileUploadErrorType.parseError,
      );
    }
  }

  /// Convert camera MediaType to local cache MediaType
  static MediaType _convertToLocalMediaType(NativeMediaType cameraType) {
    switch (cameraType) {
      case NativeMediaType.image:
        return MediaType.image;
      case NativeMediaType.video:
        return MediaType.video;
      case NativeMediaType.audio:
        return MediaType.audio;
    }
  }

  /// Convert local cache MediaType to native camera MediaType for helper functions
  static NativeMediaType _convertToCameraMediaType(MediaType localType) {
    switch (localType) {
      case MediaType.image:
        return NativeMediaType.image;
      case MediaType.video:
        return NativeMediaType.video;
      case MediaType.audio:
        // Native camera service doesn't support audio, default to video
        return NativeMediaType.video;
    }
  }
  
  /// Helper methods for file handling
  static String _getFileExtension(NativeMediaType mediaType) {
    switch (mediaType) {
      case NativeMediaType.image:
        return 'jpg';
      case NativeMediaType.video:
        return 'mp4';
      case NativeMediaType.audio:
        return 'aac';
    }
  }
  
  static String _getMimeType(NativeMediaType mediaType) {
    switch (mediaType) {
      case NativeMediaType.image:
        return 'image/jpeg';
      case NativeMediaType.video:
        return 'video/mp4';
      case NativeMediaType.audio:
        return 'audio/aac';
    }
  }
  
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Enhanced upload result with local caching information
class EnhancedUploadResult {
  final String fileUrl;
  final String timestamp;
  final int fileSize;
  final MediaType fileType;
  final String fileName;
  final String? duration;
  final String? thumbnailPath;
  final bool success;
  final String? error;

  const EnhancedUploadResult({
    required this.fileUrl,
    required this.timestamp,
    required this.fileSize,
    required this.fileType,
    required this.fileName,
    this.duration,
    this.thumbnailPath,
    this.success = true,
    this.error,
  });

  /// Create error result
  static EnhancedUploadResult createError(String error, String timestamp) {
    return EnhancedUploadResult(
      fileUrl: '',
      timestamp: timestamp,
      fileSize: 0,
      fileType: MediaType.image,
      fileName: '',
      success: false,
      error: error,
    );
  }

  @override
  String toString() {
    return 'EnhancedUploadResult(fileUrl: $fileUrl, timestamp: $timestamp, success: $success)';
  }
}

/// File upload exception with error type
class FileUploadException implements Exception {
  final String message;
  final FileUploadErrorType type;

  const FileUploadException(this.message, this.type);

  @override
  String toString() => 'FileUploadException: $message (${type.name})';
}

/// Types of file upload errors
enum FileUploadErrorType {
  fileTooLarge,
  invalidFileType,
  networkError,
  serverError,
  parseError,
  localCacheError,
}