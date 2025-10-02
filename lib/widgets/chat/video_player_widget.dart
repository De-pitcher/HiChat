import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Custom video player widget for displaying video messages
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  String _videoDuration = '0:00';
  String _currentPosition = '0:00';

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      debugPrint('🎥 Initializing video player for: ${widget.videoUrl}');

      // Create and initialize the video player controller
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (compatible; HiChat/1.0)',
        },
      );

      await _controller!.initialize();

      if (mounted) {
        final duration = _controller!.value.duration;
        debugPrint('🎥 Video duration: $duration');
        debugPrint('🎥 Video aspect ratio: ${_controller!.value.aspectRatio}');
        debugPrint('🎥 Video size: ${_controller!.value.size}');
        
        setState(() {
          _isInitialized = true;
          _videoDuration = _formatDuration(duration);
        });

        // Listen to video player state changes
        _controller!.addListener(_videoPlayerListener);
        
        // Auto-play the video when initialized
        _controller!.play();
      }

      debugPrint('🎥 Video player initialized successfully');
    } catch (error) {
      debugPrint('🎥 Failed to initialize video player: $error');
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  void _videoPlayerListener() {
    if (!mounted) return;

    final value = _controller!.value;
    final newIsPlaying = value.isPlaying;
    final newIsBuffering = value.isBuffering;
    final newPosition = _formatDuration(value.position);

    if (newIsPlaying != _isPlaying ||
        newIsBuffering != _isBuffering ||
        newPosition != _currentPosition) {
      setState(() {
        _isPlaying = newIsPlaying;
        _isBuffering = newIsBuffering;
        _currentPosition = newPosition;
      });
    }
  }

  void _togglePlayPause() {
    if (_controller != null && _isInitialized) {
      if (_isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });

    // Auto-hide controls after 3 seconds
    if (_showControls) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _seekTo(double value) {
    if (_controller != null && _isInitialized) {
      final duration = _controller!.value.duration;
      final position = Duration(
        milliseconds: (duration.inMilliseconds * value).round(),
      );
      _controller!.seekTo(position);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // Video player or loading/error state
          Center(
            child: GestureDetector(
              onTap: _toggleControls,
              child: _buildVideoContent(),
            ),
          ),

          // Video controls overlay
          if (_showControls && _isInitialized) ...[
            _buildControlsOverlay(),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoContent() {
    if (!_isInitialized) {
      if (_controller == null) {
        return _buildErrorState();
      }
      return _buildLoadingState();
    }

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          SizedBox(height: 16),
          Text(
            'Loading video...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.red[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Failed to load video',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.videoUrl,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final progress = _controller!.value.duration.inMilliseconds > 0
        ? _controller!.value.position.inMilliseconds /
            _controller!.value.duration.inMilliseconds
        : 0.0;

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Top controls (close button)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const Spacer(),
                  // You can add more top controls here (e.g., download, share)
                ],
              ),
            ),

            const Spacer(),

            // Center play/pause button
            Center(
              child: _isBuffering
                  ? const CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                  : !_isPlaying
                      ? Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _togglePlayPause,
                            icon: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 64,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(), // Hide when playing
            ),

            const Spacer(),

            // Bottom controls (progress bar, time, etc.)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Progress bar
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: _seekTo,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),

                  // Time display and additional controls
                  Row(
                    children: [
                      // Play/pause button
                      IconButton(
                        onPressed: _togglePlayPause,
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentPosition,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _videoDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}