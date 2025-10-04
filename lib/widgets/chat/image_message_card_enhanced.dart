import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../screens/chat/video_player_screen.dart';
import '../../services/local_media_cache_service.dart';

/// Enhanced media message card that supports both images and videos with local caching
class ImageMessageCard extends StatefulWidget {
  final Message message;
  final bool isCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  const ImageMessageCard({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.onTap,
    this.onRetry,
  });

  @override
  State<ImageMessageCard> createState() => _ImageMessageCardState();
}

class _ImageMessageCardState extends State<ImageMessageCard> {
  final LocalMediaCacheService _cacheService = LocalMediaCacheService();
  File? _localFile;
  String? _thumbnailPath;
  bool _isLoading = true;
  String? _actualDuration;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkUploadState();
    _loadMediaFromCache();
  }

  @override
  void didUpdateWidget(ImageMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if upload state changed
    final oldMetadata = oldWidget.message.metadata ?? {};
    final newMetadata = widget.message.metadata ?? {};
    
    final oldUploading = oldMetadata['is_uploading'] == true;
    final newUploading = newMetadata['is_uploading'] == true;
    final oldProgress = (oldMetadata['upload_progress'] as num?)?.toDouble() ?? 0.0;
    final newProgress = (newMetadata['upload_progress'] as num?)?.toDouble() ?? 0.0;
    
    if (oldUploading != newUploading || oldProgress != newProgress) {
      setState(() {
        _checkUploadState();
      });
    }
    
    // If upload completed, reload media from cache
    if (oldUploading && !newUploading) {
      debugPrint('🔄 Upload completed, reloading media from cache');
      setState(() {
        _isLoading = true;
      });
      _loadMediaFromCache();
    }
  }
  
  /// Check if message is currently being uploaded
  void _checkUploadState() {
    final metadata = widget.message.metadata ?? {};
    _isUploading = metadata['is_uploading'] == true;
    _uploadProgress = (metadata['upload_progress'] as num?)?.toDouble() ?? 0.0;
    
    debugPrint('🔄 Upload state - isUploading: $_isUploading, progress: $_uploadProgress');
  }

  /// Load media from local cache or download if not available
  Future<void> _loadMediaFromCache() async {
    final timestamp = widget.message.content; // Content now contains timestamp
    
    debugPrint('🔍 Loading media for timestamp: $timestamp');
    debugPrint('🔍 Message type: ${widget.message.type}');
    debugPrint('🔍 Is video: ${_isVideoMessage()}');
    
    try {
      // First, try to get from local cache
      final localFile = await _cacheService.getLocalMedia(timestamp);
      
      if (localFile != null) {
        debugPrint('📱 Found local media for timestamp: $timestamp');
        debugPrint('📱 Local file path: ${localFile.path}');
        debugPrint('📱 Local file exists: ${await localFile.exists()}');
        
        // Get metadata for duration and thumbnail
        final metadata = _cacheService.getMediaMetadata(timestamp);
        debugPrint('📱 Metadata found: ${metadata != null}');
        debugPrint('📱 Duration: ${metadata?.getFormattedDuration()}');
        debugPrint('📱 Thumbnail path: ${metadata?.thumbnailPath}');
        debugPrint('📱 Has thumbnail: ${metadata?.hasThumbnail}');
        
        if (metadata?.thumbnailPath != null) {
          final thumbnailFile = File(metadata!.thumbnailPath!);
          debugPrint('📱 Thumbnail file exists: ${await thumbnailFile.exists()}');
        }
        
        setState(() {
          _localFile = localFile;
          _actualDuration = metadata?.getFormattedDuration();
          _thumbnailPath = metadata?.thumbnailPath;
          _isLoading = false;
        });
      } else {
        // Download from remote URL if not in cache
        debugPrint('📱 Media not in cache, downloading: $timestamp');
        await _downloadAndCacheMedia(timestamp);
      }
    } catch (error) {
      debugPrint('📱 Error loading media: $error');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Download media from remote URL and cache locally
  Future<void> _downloadAndCacheMedia(String timestamp) async {
    final mediaUrl = _getMediaUrl();
    final isVideo = _isVideoMessage();
    
    final mediaType = isVideo 
      ? MediaType.video 
      : MediaType.image;
    
    final downloadedFile = await _cacheService.downloadAndCacheMedia(
      url: mediaUrl,
      timestamp: timestamp,
      type: mediaType,
    );
    
    if (downloadedFile != null) {
      final metadata = _cacheService.getMediaMetadata(timestamp);
      
      setState(() {
        _localFile = downloadedFile;
        _actualDuration = metadata?.getFormattedDuration();
        _thumbnailPath = metadata?.thumbnailPath;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _isVideoMessage();
    
    debugPrint('📸 Building ${isVideo ? 'Video' : 'Image'}MessageCard with local file: ${_localFile?.path}');
    
    return GestureDetector(
      onTap: widget.onTap ?? () => _handleMediaTap(context, isVideo),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 250,
          maxHeight: 350,
          minWidth: 200,
          minHeight: 150,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(widget.isCurrentUser ? 12 : 4),
            bottomRight: Radius.circular(widget.isCurrentUser ? 4 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Media content (image or video thumbnail)
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(widget.isCurrentUser ? 12 : 4),
                bottomRight: Radius.circular(widget.isCurrentUser ? 4 : 12),
              ),
              child: _buildMediaContent(isVideo),
            ),
            
            // Video play button overlay (only show when video is fully loaded)
            if (isVideo && !_isLoading && !_isUploading && _localFile != null) ...[
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(widget.isCurrentUser ? 12 : 4),
                      bottomRight: Radius.circular(widget.isCurrentUser ? 4 : 12),
                    ),
                  ),
                  child: const Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.play_arrow,
                        size: 40,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            
            // Video duration indicator (bottom left) - only show when video is fully loaded
            if (isVideo && _actualDuration != null && !_isLoading && !_isUploading && _localFile != null) ...[
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _actualDuration!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            // Timestamp overlay (bottom right)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(widget.message.timestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (widget.isCurrentUser) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.message.status == MessageStatus.failed && widget.onRetry != null
                            ? _handleRetryMessage
                            : null,
                        child: Icon(
                          _getStatusIcon(),
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build media content widget from local file or show loading/error states
  Widget _buildMediaContent(bool isVideo) {
    // Show upload progress if currently uploading
    if (_isUploading) {
      return _buildUploadProgressState();
    }
    
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_localFile == null) {
      return _buildErrorState('Media not available');
    }

    if (isVideo) {
      // For videos, show thumbnail if available, otherwise show placeholder
      debugPrint('🎬 Building video content:');
      debugPrint('🎬 Thumbnail path: $_thumbnailPath');
      debugPrint('🎬 Thumbnail exists check: ${_thumbnailPath != null ? File(_thumbnailPath!).existsSync() : 'null path'}');
      
      if (_thumbnailPath != null && File(_thumbnailPath!).existsSync()) {
        debugPrint('🎬 Displaying thumbnail from: $_thumbnailPath');
        return Image.file(
          File(_thumbnailPath!),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('🎬 Error loading thumbnail: $error');
            return _buildVideoPlaceholder();
          },
        );
      } else {
        debugPrint('🎬 No thumbnail available, showing placeholder');
        return _buildVideoPlaceholder();
      }
    } else {
      // For images, display directly from local file
      return Image.file(
        _localFile!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    }
  }

  /// Build loading state widget
  Widget _buildLoadingState() {
    final isVideo = _isVideoMessage();
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Media type icon
          Icon(
            isVideo ? Icons.videocam : Icons.image,
            size: 32,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading ${isVideo ? 'video' : 'image'}...',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build error state widget
  Widget _buildErrorState(String message) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.red[100],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red[400],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Build upload progress state widget
  Widget _buildUploadProgressState() {
    final isVideo = _isVideoMessage();
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          
          // Progress indicator
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[300]!),
                  ),
                ),
                // Progress circle
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: _uploadProgress,
                    strokeWidth: 8,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                // Progress text
                Text(
                  '${(_uploadProgress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Upload status text
          Text(
            'Uploading ${isVideo ? 'video' : 'image'}...',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build video placeholder with pattern
  Widget _buildVideoPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6B73FF).withValues(alpha: 0.1),
            const Color(0xFF000051).withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background pattern for video thumbnail effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.1),
              ),
              child: CustomPaint(
                painter: VideoThumbnailPatternPainter(),
              ),
            ),
          ),
          
          // Center play button
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 32,
                color: Color(0xFF2D3748),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle media tap (image or video)
  void _handleMediaTap(BuildContext context, bool isVideo) {
    if (_localFile == null) return;

    if (isVideo) {
      // Navigate to video player with local file path
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: _localFile!.path,
          ),
        ),
      );
    } else {
      // Show full screen image viewer with local file
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Image Viewer'),
            ),
            body: Center(
              child: InteractiveViewer(
                child: Image.file(
                  _localFile!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Check if this is a video message
  bool _isVideoMessage() {
    return widget.message.type == MessageType.video || 
           widget.message.fileUrl?.contains('.mp4') == true ||
           widget.message.fileUrl?.contains('.mov') == true ||
           widget.message.fileUrl?.contains('.avi') == true ||
           widget.message.fileUrl?.contains('.mkv') == true ||
           widget.message.fileUrl?.contains('.webm') == true;
  }

  /// Get the media URL from message (fallback for downloading)
  String _getMediaUrl() {
    String? url;
    
    // Check if message has a file field (from API response)
    if (widget.message.fileUrl != null && widget.message.fileUrl!.isNotEmpty) {
      url = widget.message.fileUrl!;
      debugPrint('📸 Using fileUrl: $url');
    }
    // Fallback: construct URL from timestamp (for older messages)
    else {
      final isVideo = _isVideoMessage();
      final mediaType = isVideo ? 'video' : 'image';
      final timestamp = widget.message.content;
      url = 'https://res.cloudinary.com/dsazvjswi/$mediaType/upload/chat_corner/messages/$mediaType/$timestamp.${isVideo ? 'mp4' : 'jpg'}';
      debugPrint('📸 Constructed $mediaType URL from timestamp: $url');
    }
    
    debugPrint('📸 Final media URL: $url');
    debugPrint('📸 Message content: ${widget.message.content}');
    debugPrint('📸 Message fileUrl: ${widget.message.fileUrl}');  
    debugPrint('📸 Message type: ${widget.message.type}');
    debugPrint('📸 Message metadata: ${widget.message.metadata}');
    
    return url;
  }

  /// Format timestamp - only show time
  String _formatTime(DateTime timestamp) {
    final messageTime = timestamp.toLocal();
    final hour = messageTime.hour.toString().padLeft(2, '0');
    final minute = messageTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _handleRetryMessage() {
    if (widget.onRetry != null) {
      widget.onRetry!();
    }
  }

  /// Get status icon for current user messages
  IconData _getStatusIcon() {
    switch (widget.message.status) {
      case MessageStatus.pending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
      case MessageStatus.sending:
        return Icons.schedule;
      case MessageStatus.failed:
        return Icons.error_outline;
    }
  }
}

/// Custom painter for video thumbnail background pattern
class VideoThumbnailPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Draw a subtle grid pattern
    const spacing = 40.0;
    
    // Vertical lines
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Horizontal lines
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}