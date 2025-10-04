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
  final Function(Message)? onRetry;

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

  @override
  void initState() {
    super.initState();
    _loadMediaFromCache();
  }

  /// Load media from local cache or download if not available
  Future<void> _loadMediaFromCache() async {
    final timestamp = widget.message.content; // Content now contains timestamp
    
    try {
      // First, try to get from local cache
      final localFile = await _cacheService.getLocalMedia(timestamp);
      
      if (localFile != null) {
        debugPrint('📱 Found local media for timestamp: $timestamp');
        
        // Get metadata for duration and thumbnail
        final metadata = _cacheService.getMediaMetadata(timestamp);
        
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
            
            // Video play button overlay
            if (isVideo && !_isLoading) ...[
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
            
            // Video duration indicator (bottom left)
            if (isVideo && _actualDuration != null && !_isLoading) ...[
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
                      widget.message.status == MessageStatus.failed
                          ? GestureDetector(
                              onTap: () => _handleRetryMessage(),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  _getStatusIcon(),
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Icon(
                              _getStatusIcon(),
                              size: 14,
                              color: Colors.white,
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
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_localFile == null) {
      return _buildErrorState('Media not available');
    }

    if (isVideo) {
      // For videos, show thumbnail if available, otherwise show placeholder
      if (_thumbnailPath != null && File(_thumbnailPath!).existsSync()) {
        return Image.file(
          File(_thumbnailPath!),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
        );
      } else {
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
    return Container(
      color: Colors.grey[200],
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 16),
          Text(
            'Loading media...',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Build error state widget
  Widget _buildErrorState(String message) {
    return Container(
      color: Colors.red[100],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red[400],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: Colors.red[700],
              fontSize: 12,
              fontWeight: FontWeight.bold,
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

  /// Format timestamp
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final messageTime = timestamp.toLocal();
    
    if (now.day == messageTime.day && 
        now.month == messageTime.month && 
        now.year == messageTime.year) {
      final hour = messageTime.hour.toString().padLeft(2, '0');
      final minute = messageTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else {
      final day = messageTime.day.toString().padLeft(2, '0');
      final month = messageTime.month.toString().padLeft(2, '0');
      final hour = messageTime.hour.toString().padLeft(2, '0');
      final minute = messageTime.minute.toString().padLeft(2, '0');
      return '$day/$month $hour:$minute';
    }
  }

  /// Handle retry message for failed multimedia messages
  void _handleRetryMessage() {
    debugPrint('🔄 ImageMessageCard: Retry button tapped for message: ${widget.message.id}');
    widget.onRetry?.call(widget.message);
  }

  /// Get status icon for current user messages
  IconData _getStatusIcon() {
    switch (widget.message.status) {
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
      case MessageStatus.pending:
        return Icons.pending;
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