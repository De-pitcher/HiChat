import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Native camera service using image_picker for direct camera access
/// 
/// This service replaces the custom camera_service_plugin with Flutter's
/// built-in image_picker package for capturing images and videos directly
/// from the device's native camera interface.
class NativeCameraService {
  static final ImagePicker _picker = ImagePicker();
  
  /// Capture an image using the device's native camera
  /// 
  /// Returns a [NativeCameraResult] with the captured image file and metadata
  static Future<NativeCameraResult?> captureImage({
    int imageQuality = 85,
    double? maxWidth,
    double? maxHeight,
  }) async {
    try {
      debugPrint('📸 NativeCameraService: Starting image capture...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        preferredCameraDevice: CameraDevice.rear,
      );
      
      if (image == null) {
        debugPrint('📸 NativeCameraService: Image capture cancelled by user');
        return null;
      }
      
      debugPrint('📸 NativeCameraService: Image captured successfully - ${image.path}');
      
      final File imageFile = File(image.path);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final int fileSize = imageBytes.length;
      
      return NativeCameraResult(
        file: imageFile,
        data: imageBytes,
        type: NativeMediaType.image,
        size: fileSize,
        path: image.path,
        name: image.name,
        captureTime: DateTime.now(),
        mimeType: image.mimeType,
      );
    } catch (e) {
      debugPrint('Native camera image capture error: $e');
      throw NativeCameraException(
        'Failed to capture image: $e',
        NativeCameraErrorType.captureError,
      );
    }
  }
  
  /// Capture a video using the device's native camera
  /// 
  /// Returns a [NativeCameraResult] with the captured video file and metadata
  static Future<NativeCameraResult?> captureVideo({
    Duration? maxDuration,
    CameraDevice preferredCamera = CameraDevice.rear,
  }) async {
    try {
      debugPrint('🎥 NativeCameraService: Starting video capture...');
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: maxDuration ?? const Duration(minutes: 5),
        preferredCameraDevice: preferredCamera,
      );
      
      if (video == null) {
        debugPrint('🎥 NativeCameraService: Video capture cancelled by user');
        return null;
      }
      
      debugPrint('🎥 NativeCameraService: Video captured successfully - ${video.path}');
      
      final File videoFile = File(video.path);
      final Uint8List videoBytes = await videoFile.readAsBytes();
      final int fileSize = videoBytes.length;
      
      return NativeCameraResult(
        file: videoFile,
        data: videoBytes,
        type: NativeMediaType.video,
        size: fileSize,
        path: video.path,
        name: video.name,
        captureTime: DateTime.now(),
        mimeType: video.mimeType,
      );
    } catch (e) {
      debugPrint('Native camera video capture error: $e');
      throw NativeCameraException(
        'Failed to capture video: $e',
        NativeCameraErrorType.captureError,
      );
    }
  }
  
  /// Pick an image from the device gallery
  /// 
  /// Returns a [NativeCameraResult] with the selected image file and metadata
  static Future<NativeCameraResult?> pickImageFromGallery({
    int imageQuality = 85,
    double? maxWidth,
    double? maxHeight,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      
      if (image == null) {
        return null;
      }
      
      final File imageFile = File(image.path);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final int fileSize = imageBytes.length;
      
      return NativeCameraResult(
        file: imageFile,
        data: imageBytes,
        type: NativeMediaType.image,
        size: fileSize,
        path: image.path,
        name: image.name,
        captureTime: DateTime.now(),
        mimeType: image.mimeType,
      );
    } catch (e) {
      debugPrint('Gallery image selection error: $e');
      throw NativeCameraException(
        'Failed to select image from gallery: $e',
        NativeCameraErrorType.galleryError,
      );
    }
  }
  
  /// Pick a video from the device gallery
  /// 
  /// Returns a [NativeCameraResult] with the selected video file and metadata
  static Future<NativeCameraResult?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
      );
      
      if (video == null) {
        return null;
      }
      
      final File videoFile = File(video.path);
      final Uint8List videoBytes = await videoFile.readAsBytes();
      final int fileSize = videoBytes.length;
      
      return NativeCameraResult(
        file: videoFile,
        data: videoBytes,
        type: NativeMediaType.video,
        size: fileSize,
        path: video.path,
        name: video.name,
        captureTime: DateTime.now(),
        mimeType: video.mimeType,
      );
    } catch (e) {
      debugPrint('Gallery video selection error: $e');
      throw NativeCameraException(
        'Failed to select video from gallery: $e',
        NativeCameraErrorType.galleryError,
      );
    }
  }
  
  /// Show media selection dialog for image or video from camera or gallery
  /// 
  /// Returns a [NativeCameraResult] based on user selection
  static Future<NativeCameraResult?> showMediaSelectionDialog(
    BuildContext context, {
    bool allowCamera = true,
    bool allowGallery = true,
    bool allowImage = true,
    bool allowVideo = true,
  }) async {
    debugPrint('📱 NativeCameraService: Showing media selection dialog - Camera: $allowCamera, Gallery: $allowGallery, Image: $allowImage, Video: $allowVideo');
    
    if (!allowCamera && !allowGallery) {
      throw ArgumentError('At least one source (camera or gallery) must be allowed');
    }
    if (!allowImage && !allowVideo) {
      throw ArgumentError('At least one media type (image or video) must be allowed');
    }
    
    final result = await showModalBottomSheet<NativeCameraResult>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Select Media',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Camera options
                if (allowCamera) ...[
                  if (allowImage)
                    _MediaOptionTile(
                      icon: Icons.camera_alt,
                      title: 'Camera Photo',
                      subtitle: 'Take a photo with camera',
                      onTap: () async {
                        debugPrint('📸 NativeCameraService: Camera Photo option selected');
                        final result = await captureImage();
                        debugPrint('📸 NativeCameraService: Camera Photo result: $result');
                        Navigator.pop(context, result);
                      },
                    ),
                  if (allowVideo)
                    _MediaOptionTile(
                      icon: Icons.videocam,
                      title: 'Camera Video',
                      subtitle: 'Record a video with camera',
                      onTap: () async {
                        debugPrint('🎥 NativeCameraService: Camera Video option selected');
                        final result = await captureVideo();
                        debugPrint('🎥 NativeCameraService: Camera Video result: $result');
                        Navigator.pop(context, result);
                      },
                    ),
                ],
                
                // Gallery options
                if (allowGallery) ...[
                  if (allowImage)
                    _MediaOptionTile(
                      icon: Icons.photo_library,
                      title: 'Gallery Photo',
                      subtitle: 'Choose photo from gallery',
                      onTap: () async {
                        debugPrint('📷 NativeCameraService: Gallery Photo option selected');
                        final result = await pickImageFromGallery();
                        debugPrint('📷 NativeCameraService: Gallery Photo result: $result');
                        Navigator.pop(context, result);
                      },
                    ),
                  if (allowVideo)
                    _MediaOptionTile(
                      icon: Icons.video_library,
                      title: 'Gallery Video',
                      subtitle: 'Choose video from gallery',
                      onTap: () async {
                        debugPrint('📹 NativeCameraService: Gallery Video option selected');
                        final result = await pickVideoFromGallery();
                        debugPrint('📹 NativeCameraService: Gallery Video result: $result');
                        Navigator.pop(context, result);
                      },
                    ),
                ],
                
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
    
    debugPrint('📱 NativeCameraService: Media selection dialog result: $result');
    return result;
  }
  
  /// Save captured media to app's documents directory
  /// 
  /// Returns the path to the saved file
  static Future<String> saveMediaToAppDirectory(NativeCameraResult result) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String mediaDir = path.join(appDir.path, 'media');
      
      // Create media directory if it doesn't exist
      final Directory mediaDirObj = Directory(mediaDir);
      if (!await mediaDirObj.exists()) {
        await mediaDirObj.create(recursive: true);
      }
      
      // Generate unique filename
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String extension = result.type == NativeMediaType.image ? 'jpg' : 'mp4';
      final String filename = 'media_$timestamp.$extension';
      final String newPath = path.join(mediaDir, filename);
      
      // Copy file to new location
      final File newFile = await result.file.copy(newPath);
      
      return newFile.path;
    } catch (e) {
      debugPrint('Error saving media to app directory: $e');
      throw NativeCameraException(
        'Failed to save media: $e',
        NativeCameraErrorType.fileError,
      );
    }
  }
}

/// Media option tile widget for the selection dialog
class _MediaOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MediaOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

/// Result class for native camera operations
class NativeCameraResult {
  final File file;
  final Uint8List data;
  final NativeMediaType type;
  final int size;
  final String path;
  final String name;
  final DateTime captureTime;
  final String? mimeType;

  const NativeCameraResult({
    required this.file,
    required this.data,
    required this.type,
    required this.size,
    required this.path,
    required this.name,
    required this.captureTime,
    this.mimeType,
  });

  /// Get file size in a human-readable format
  String get formattedSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// Check if this is an image
  bool get isImage => type == NativeMediaType.image;

  /// Check if this is a video
  bool get isVideo => type == NativeMediaType.video;

  @override
  String toString() {
    return 'NativeCameraResult{type: $type, size: $formattedSize, path: $path}';
  }
}

/// Media type enumeration
enum NativeMediaType {
  image,
  video,
  audio,
}

/// Camera error types
enum NativeCameraErrorType {
  captureError,
  galleryError,
  permissionError,
  fileError,
  unknown,
}

/// Custom exception for native camera operations
class NativeCameraException implements Exception {
  final String message;
  final NativeCameraErrorType type;

  const NativeCameraException(this.message, this.type);

  @override
  String toString() => 'NativeCameraException: $message';
}