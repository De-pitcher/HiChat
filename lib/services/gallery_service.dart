import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'camera_service.dart';

/// Service for handling gallery image/video selection
class GalleryService {
  static final GalleryService _instance = GalleryService._internal();
  factory GalleryService() => _instance;
  GalleryService._internal();

  final ImagePicker _picker = ImagePicker();

  /// Pick image from gallery
  Future<CameraResult?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return null;

      return await _processGalleryFile(image, MediaType.image);
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
      rethrow;
    }
  }

  /// Pick video from gallery
  Future<CameraResult?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5), // 5 minute limit
      );

      if (video == null) return null;

      return await _processGalleryFile(video, MediaType.video);
    } catch (e) {
      debugPrint('Error picking video from gallery: $e');
      rethrow;
    }
  }

  /// Pick multiple images from gallery
  Future<List<CameraResult>> pickMultipleImagesFromGallery({
    int maxImages = 10,
  }) async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isEmpty) return [];

      // Limit the number of selected images
      final limitedImages = images.take(maxImages).toList();
      final List<CameraResult> results = [];

      for (final image in limitedImages) {
        final result = await _processGalleryFile(image, MediaType.image);
        if (result != null) {
          results.add(result);
        }
      }

      return results;
    } catch (e) {
      debugPrint('Error picking multiple images from gallery: $e');
      rethrow;
    }
  }

  /// Show selection dialog for image or video
  Future<CameraResult?> showMediaSelectionDialog(BuildContext context) async {
    return await showDialog<CameraResult>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Media'),
          content: const Text('Choose the type of media to select from gallery'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final result = await pickImageFromGallery();
                if (context.mounted && result != null) {
                  Navigator.pop(context, result);
                }
              },
              child: const Text('Image'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final result = await pickVideoFromGallery();
                if (context.mounted && result != null) {
                  Navigator.pop(context, result);
                }
              },
              child: const Text('Video'),
            ),
          ],
        );
      },
    );
  }

  /// Process gallery file into CameraResult format
  Future<CameraResult?> _processGalleryFile(
    XFile file,
    MediaType type,
  ) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final fileSize = bytes.length;
      
      // Get file extension
      final path = file.path;
      final extension = path.split('.').last.toLowerCase();
      
      // Validate file size (max 50MB)
      const maxSizeBytes = 50 * 1024 * 1024; // 50MB
      if (fileSize > maxSizeBytes) {
        throw Exception('File size too large. Maximum size is 50MB.');
      }

      // Validate file type
      if (type == MediaType.image) {
        if (!_isValidImageExtension(extension)) {
          throw Exception('Invalid image format. Supported formats: jpg, jpeg, png, gif, webp');
        }
      } else if (type == MediaType.video) {
        if (!_isValidVideoExtension(extension)) {
          throw Exception('Invalid video format. Supported formats: mp4, mov, avi, mkv, webm');
        }
      }

      // Create CameraResult with correct parameters
      return CameraResult(
        data: base64String,
        type: type,
        size: fileSize,
        captureTime: DateTime.now(),
        duration: Duration.zero, // Gallery selection is instant
      );
    } catch (e) {
      debugPrint('Error processing gallery file: $e');
      rethrow;
    }
  }

  /// Check if image extension is valid
  bool _isValidImageExtension(String extension) {
    const validExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    return validExtensions.contains(extension);
  }

  /// Check if video extension is valid
  bool _isValidVideoExtension(String extension) {
    const validExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
    return validExtensions.contains(extension);
  }

  /// Get MIME type based on extension and type
  String _getMimeType(String extension, MediaType type) {
    if (type == MediaType.image) {
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg';
      }
    } else if (type == MediaType.video) {
      switch (extension) {
        case 'mp4':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        case 'mkv':
          return 'video/x-matroska';
        case 'webm':
          return 'video/webm';
        case '3gp':
          return 'video/3gpp';
        default:
          return 'video/mp4';
      }
    }
    return 'application/octet-stream';
  }

  /// Get file info without loading into memory (useful for large files)
  Future<Map<String, dynamic>> getFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();
      final extension = filePath.split('.').last.toLowerCase();
      
      return {
        'size': stat.size,
        'extension': extension,
        'lastModified': stat.modified,
        'isImage': _isValidImageExtension(extension),
        'isVideo': _isValidVideoExtension(extension),
        'mimeType': _getMimeType(extension, 
          _isValidImageExtension(extension) 
            ? MediaType.image 
            : MediaType.video),
      };
    } catch (e) {
      debugPrint('Error getting file info: $e');
      rethrow;
    }
  }

  /// Clear cached images (optional cleanup method)
  Future<void> clearTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final galleryTempDir = Directory('${tempDir.path}/gallery_temp');
      
      if (await galleryTempDir.exists()) {
        await galleryTempDir.delete(recursive: true);
        debugPrint('Gallery temp files cleared');
      }
    } catch (e) {
      debugPrint('Error clearing temp files: $e');
    }
  }
}