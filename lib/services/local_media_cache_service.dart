import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:convert';

/// Service for managing local media cache including images, videos, and audio files
class LocalMediaCacheService {
  static final LocalMediaCacheService _instance = LocalMediaCacheService._internal();
  factory LocalMediaCacheService() => _instance;
  LocalMediaCacheService._internal();

  // Cache directories
  static const String _imagesDir = 'cached_images';
  static const String _videosDir = 'cached_videos';
  static const String _audiosDir = 'cached_audios';
  static const String _thumbnailsDir = 'video_thumbnails';
  
  // Metadata file for storing media info
  static const String _metadataFile = 'media_metadata.json';
  
  Map<String, MediaMetadata> _metadataCache = {};
  bool _isInitialized = false;

  /// Initialize the cache service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _createCacheDirectories();
      await _loadMetadata();
      _isInitialized = true;
      debugPrint('📱 LocalMediaCacheService initialized successfully');
    } catch (error) {
      debugPrint('📱 Failed to initialize LocalMediaCacheService: $error');
    }
  }

  /// Create cache directories if they don't exist
  Future<void> _createCacheDirectories() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/media_cache');
    
    final directories = [
      Directory('${cacheDir.path}/$_imagesDir'),
      Directory('${cacheDir.path}/$_videosDir'),
      Directory('${cacheDir.path}/$_audiosDir'),
      Directory('${cacheDir.path}/$_thumbnailsDir'),
    ];

    for (final dir in directories) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        debugPrint('📱 Created cache directory: ${dir.path}');
      }
    }
  }

  /// Load metadata from file
  Future<void> _loadMetadata() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final metadataFile = File('${appDir.path}/media_cache/$_metadataFile');
      
      if (await metadataFile.exists()) {
        final jsonString = await metadataFile.readAsString();
        final Map<String, dynamic> jsonData = json.decode(jsonString);
        
        _metadataCache = jsonData.map((key, value) => 
          MapEntry(key, MediaMetadata.fromJson(value as Map<String, dynamic>))
        );
        
        debugPrint('📱 Loaded ${_metadataCache.length} media metadata entries');
      }
    } catch (error) {
      debugPrint('📱 Failed to load metadata: $error');
      _metadataCache = {};
    }
  }

  /// Save metadata to file
  Future<void> _saveMetadata() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final metadataFile = File('${appDir.path}/media_cache/$_metadataFile');
      
      final jsonData = _metadataCache.map((key, value) => 
        MapEntry(key, value.toJson())
      );
      
      await metadataFile.writeAsString(json.encode(jsonData));
      debugPrint('📱 Saved ${_metadataCache.length} media metadata entries');
    } catch (error) {
      debugPrint('📱 Failed to save metadata: $error');
    }
  }

  /// Save media file locally with timestamp-based naming
  Future<String?> saveMediaLocally({
    required Uint8List data,
    required MediaType type,
    required String originalFilename,
  }) async {
    await initialize();
    
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final extension = _getFileExtension(originalFilename);
      final filename = '$timestamp$extension';
      
      final appDir = await getApplicationDocumentsDirectory();
      final typeDir = _getTypeDirName(type);
      final filePath = '${appDir.path}/media_cache/$typeDir/$filename';
      final file = File(filePath);
      
      await file.writeAsBytes(data);
      
      // Create metadata entry
      final metadata = MediaMetadata(
        timestamp: timestamp,
        originalFilename: originalFilename,
        localPath: filePath,
        type: type,
        fileSize: data.length,
        createdAt: DateTime.now(),
      );

      // Generate video thumbnail and extract duration if it's a video
      if (type == MediaType.video) {
        await _generateVideoThumbnailAndDuration(filePath, metadata);
      }

      _metadataCache[timestamp] = metadata;
      await _saveMetadata();
      
      debugPrint('📱 Saved ${type.name} locally: $filename (${data.length} bytes)');
      return timestamp;
    } catch (error) {
      debugPrint('📱 Failed to save media locally: $error');
      return null;
    }
  }

  /// Generate video thumbnail and extract duration
  Future<void> _generateVideoThumbnailAndDuration(String videoPath, MediaMetadata metadata) async {
    try {
      debugPrint('🎬 Generating thumbnail for video: $videoPath');
      
      // Initialize video player to get duration
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();

      // Extract duration
      final duration = controller.value.duration;
      metadata.duration = duration;
      debugPrint('🎬 Video duration extracted: ${duration.inSeconds}s');

      await controller.dispose();

      // Generate thumbnail using video_thumbnail package
      final appDir = await getApplicationDocumentsDirectory();
      final thumbnailPath = '${appDir.path}/media_cache/$_thumbnailsDir/${metadata.timestamp}_thumb.jpg';
      
      debugPrint('🎬 Generating thumbnail at: $thumbnailPath');
      debugPrint('🎬 Thumbnail time: ${duration.inMilliseconds ~/ 4}ms');
      
      final thumbnailData = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300, // Good quality for chat thumbnails
        quality: 75,
        timeMs: duration.inMilliseconds ~/ 4, // Get thumbnail at 25% of video
      );

      if (thumbnailData != null) {
        debugPrint('🎬 Thumbnail data generated: ${thumbnailData.length} bytes');
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(thumbnailData);
        
        debugPrint('🎬 Thumbnail saved to: $thumbnailPath');
        debugPrint('🎬 Thumbnail file exists: ${await thumbnailFile.exists()}');
        
        metadata.thumbnailPath = thumbnailPath;
        metadata.hasThumbnail = true;
        
        debugPrint('📱 Video thumbnail generated: $thumbnailPath');
      } else {
        debugPrint('📱 Failed to generate thumbnail data');
        metadata.hasThumbnail = false;
        // Try alternative approach
        await _tryAlternativeThumbnailGeneration(videoPath, metadata);
      }
      
      debugPrint('📱 Video duration extracted: ${duration.inSeconds}s');
    } catch (error) {
      debugPrint('📱 Failed to generate video thumbnail: $error');
      metadata.hasThumbnail = false;
      // Try alternative approach
      await _tryAlternativeThumbnailGeneration(videoPath, metadata);
    }
  }
  
  /// Alternative thumbnail generation method using file path
  Future<void> _tryAlternativeThumbnailGeneration(String videoPath, MediaMetadata metadata) async {
    try {
      debugPrint('🎬 Trying alternative thumbnail generation...');
      
      final appDir = await getApplicationDocumentsDirectory();
      final thumbnailPath = '${appDir.path}/media_cache/$_thumbnailsDir/${metadata.timestamp}_thumb.jpg';
      
      // Try generating thumbnail to file directly
      final thumbnailFilePath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: thumbnailPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
        timeMs: 500, // Try at 0.5 seconds
      );
      
      if (thumbnailFilePath != null && await File(thumbnailFilePath).exists()) {
        debugPrint('🎬 ✅ Alternative thumbnail generation successful: $thumbnailFilePath');
        metadata.thumbnailPath = thumbnailFilePath;
        metadata.hasThumbnail = true;
      } else {
        debugPrint('🎬 ❌ Alternative thumbnail generation also failed');
        // Set a flag that thumbnail generation failed
        metadata.hasThumbnail = false;
      }
    } catch (error) {
      debugPrint('🎬 ❌ Alternative thumbnail generation error: $error');
      metadata.hasThumbnail = false;
    }
  }

  /// Get media file from local cache
  Future<File?> getLocalMedia(String timestamp) async {
    await initialize();
    
    final metadata = _metadataCache[timestamp];
    if (metadata == null) {
      debugPrint('📱 No metadata found for timestamp: $timestamp');
      return null;
    }

    final file = File(metadata.localPath);
    if (await file.exists()) {
      debugPrint('📱 Found local media: ${metadata.originalFilename}');
      return file;
    } else {
      debugPrint('📱 Local media file not found: ${metadata.localPath}');
      // Remove from metadata if file doesn't exist
      _metadataCache.remove(timestamp);
      await _saveMetadata();
      return null;
    }
  }

  /// Download and cache media from URL
  Future<File?> downloadAndCacheMedia({
    required String url,
    required String timestamp,
    required MediaType type,
  }) async {
    await initialize();
    
    try {
      debugPrint('📱 Downloading media from: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; HiChat/1.0)',
        },
      );

      if (response.statusCode == 200) {
        final savedTimestamp = await saveMediaLocally(
          data: response.bodyBytes,
          type: type,
          originalFilename: _extractFilenameFromUrl(url),
        );

        if (savedTimestamp != null) {
          // Update the metadata to use the provided timestamp
          final metadata = _metadataCache[savedTimestamp];
          if (metadata != null) {
            _metadataCache.remove(savedTimestamp);
            metadata.timestamp = timestamp;
            _metadataCache[timestamp] = metadata;
            
            // Rename the file to use the provided timestamp
            final file = File(metadata.localPath);
            final newPath = metadata.localPath.replaceAll(savedTimestamp, timestamp);
            final newFile = await file.rename(newPath);
            metadata.localPath = newPath;
            
            await _saveMetadata();
            
            debugPrint('📱 Downloaded and cached media: $timestamp');
            return newFile;
          }
        }
      } else {
        debugPrint('📱 Failed to download media: HTTP ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('📱 Error downloading media: $error');
    }
    
    return null;
  }

  /// Get media metadata
  MediaMetadata? getMediaMetadata(String timestamp) {
    return _metadataCache[timestamp];
  }

  /// Get video thumbnail path
  String? getVideoThumbnailPath(String timestamp) {
    final metadata = _metadataCache[timestamp];
    if (metadata?.type == MediaType.video && metadata?.hasThumbnail == true) {
      return metadata?.thumbnailPath;
    }
    return null;
  }

  /// Clear cache (optional - for maintenance)
  Future<void> clearCache() async {
    await initialize();
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/media_cache');
      
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await _createCacheDirectories();
        _metadataCache.clear();
        debugPrint('📱 Cache cleared successfully');
      }
    } catch (error) {
      debugPrint('📱 Failed to clear cache: $error');
    }
  }

  /// Helper methods
  String _getFileExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    return lastDot != -1 ? filename.substring(lastDot) : '';
  }

  String _getTypeDirName(MediaType type) {
    switch (type) {
      case MediaType.image:
        return _imagesDir;
      case MediaType.video:
        return _videosDir;
      case MediaType.audio:
        return _audiosDir;
    }
  }

  String _extractFilenameFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    return segments.isNotEmpty ? segments.last : 'unknown_file';
  }
}

/// Media types supported by the cache
enum MediaType {
  image,
  video,
  audio,
}

/// Metadata for cached media files
class MediaMetadata {
  String timestamp;
  String originalFilename;
  String localPath;
  MediaType type;
  int fileSize;
  DateTime createdAt;
  Duration? duration; // For videos and audio
  String? thumbnailPath; // For videos
  bool hasThumbnail;

  MediaMetadata({
    required this.timestamp,
    required this.originalFilename,
    required this.localPath,
    required this.type,
    required this.fileSize,
    required this.createdAt,
    this.duration,
    this.thumbnailPath,
    this.hasThumbnail = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'originalFilename': originalFilename,
      'localPath': localPath,
      'type': type.name,
      'fileSize': fileSize,
      'createdAt': createdAt.toIso8601String(),
      'duration': duration?.inMilliseconds,
      'thumbnailPath': thumbnailPath,
      'hasThumbnail': hasThumbnail,
    };
  }

  factory MediaMetadata.fromJson(Map<String, dynamic> json) {
    return MediaMetadata(
      timestamp: json['timestamp'] as String,
      originalFilename: json['originalFilename'] as String,
      localPath: json['localPath'] as String,
      type: MediaType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MediaType.image,
      ),
      fileSize: json['fileSize'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      duration: json['duration'] != null 
        ? Duration(milliseconds: json['duration'] as int)
        : null,
      thumbnailPath: json['thumbnailPath'] as String?,
      hasThumbnail: json['hasThumbnail'] as bool? ?? false,
    );
  }

  String getFormattedDuration() {
    if (duration == null) return '0:00';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}