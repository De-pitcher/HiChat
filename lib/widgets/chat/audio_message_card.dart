import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter_sound/flutter_sound.dart';

import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/local_media_cache_service.dart';

/// Modern audio message card with platform-aware playback functionality
class AudioMessageCard extends StatefulWidget {
  final Message message;
  final bool isCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  const AudioMessageCard({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.onTap,
    this.onRetry,
  });

  @override
  State<AudioMessageCard> createState() => _AudioMessageCardState();
}

class _AudioMessageCardState extends State<AudioMessageCard> with TickerProviderStateMixin {
  FlutterSoundPlayer? _audioPlayer;
  final LocalMediaCacheService _cacheService = LocalMediaCacheService();
  
  // Playback state
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackProgress = 0.0;
  
  // File state
  int _fileSize = 0;
  String? _audioUrl;
  
  // Animation controllers for waveform
  late AnimationController _waveformController;
  late Animation<double> _waveformAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAudio();
    _initializeAnimations();
    _loadAudioFile();
  }

  @override
  void dispose() {
    _audioPlayer?.closePlayer();
    _waveformController.dispose();
    super.dispose();
  }

  void _initializeAudio() {
    // Only initialize audio player on mobile platforms, and only if not already initialized
    if ((Platform.isAndroid || Platform.isIOS) && _audioPlayer == null) {
      _audioPlayer = FlutterSoundPlayer();
      _setupAudioListeners();
    }
  }

  void _initializeAnimations() {
    _waveformController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _waveformAnimation = CurvedAnimation(
      parent: _waveformController,
      curve: Curves.easeInOut,
    );
  }

  void _setupAudioListeners() {
    if (_audioPlayer == null) return;
    
    // Initialize player session only once
    if (!_audioPlayer!.isOpen()) {
      _audioPlayer!.openPlayer().then((_) {
        if (kDebugMode) {
          print('✅ Audio player initialized successfully');
        }
        _setupPlayerCallbacks();
      }).catchError((error) {
        if (kDebugMode) {
          print('❌ Failed to initialize audio player: $error');
        }
      });
    } else {
      _setupPlayerCallbacks();
    }
  }

  void _setupPlayerCallbacks() {
    if (_audioPlayer == null) return;

    // Set up callbacks for player state changes
    _audioPlayer!.onProgress!.listen((PlaybackDisposition e) {
      if (mounted) {
        setState(() {
          _position = e.position;
          _duration = e.duration;
          _playbackProgress = e.duration.inMilliseconds > 0
              ? e.position.inMilliseconds / e.duration.inMilliseconds
              : 0.0;
          
          // Check if playback has finished (position reached duration)
          if (e.duration.inMilliseconds > 0 && 
              e.position.inMilliseconds >= e.duration.inMilliseconds - 100) {
            _isPlaying = false;
            _position = Duration.zero;
            _playbackProgress = 0.0;
          }
        });
      }
    });

    // Set subscription duration for regular progress updates
    _audioPlayer!.setSubscriptionDuration(const Duration(milliseconds: 100));
  }

  Future<void> _extractDuration() async {
    if (_audioPlayer == null || _audioUrl == null) return;

    try {
      // Calculate file size if not already available
      await _calculateFileSize();
      
      // FIXED: Set volume to 0 before starting player to prevent audible playback
      // This prevents the unwanted audio playback when messages load
      await _audioPlayer!.setVolume(0.0);
      
      // Get the duration of the audio file silently
      final duration = await _audioPlayer!.startPlayer(
        fromURI: _audioUrl!,
        whenFinished: () {
          // Immediately stop after getting duration
          _audioPlayer!.stopPlayer();
        },
      );
      
      // Stop the player immediately after starting to extract duration
      await _audioPlayer!.stopPlayer();
      
      // Restore normal volume for when user actually plays the audio
      await _audioPlayer!.setVolume(1.0);
      
      // Use the duration returned from startPlayer
      if (duration != null && duration.inMilliseconds > 0) {
        setState(() {
          _duration = duration;
        });
        if (kDebugMode) {
          print('🎵 Got audio duration silently: ${duration.inSeconds}s');
        }
      }
    } catch (e) {
      // Ensure volume is restored even on error
      try {
        await _audioPlayer!.setVolume(1.0);
      } catch (_) {}
      
      print('🎵 Error extracting duration: $e');
      // Fallback: try to extract from metadata
      final metadata = widget.message.metadata ?? {};
      final durationMs = metadata['duration'] as int?;
      if (durationMs != null) {
        setState(() {
          _duration = Duration(milliseconds: durationMs);
        });
      }
    }
  }

  Future<void> _calculateFileSize() async {
    if (_audioUrl == null) return;
    
    try {
      final file = File(_audioUrl!);
      if (await file.exists()) {
        final fileSize = await file.length();
        
        if (mounted) {
          setState(() {
            _fileSize = fileSize;
          });
        }
        
        if (kDebugMode) {
          print('🎵 Calculated file size: $fileSize bytes for $_audioUrl');
        }
      }
    } catch (e) {
      print('🎵 Error calculating file size: $e');
    }
  }

  Future<void> _loadAudioFile() async {
    final metadata = widget.message.metadata ?? {};
    
    if (kDebugMode) {
      print('🎵 Loading audio file for message: ${widget.message.id}');
      print('🎵 Message content: ${widget.message.content}');
      print('🎵 Message metadata: $metadata');
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Try to get cached file first
      final cachedFile = await _cacheService.getLocalMedia(widget.message.id);
      if (cachedFile != null) {
        if (kDebugMode) {
          print('🎵 Found cached file: ${cachedFile.path}');
        }
        setState(() {
          _audioUrl = cachedFile.path;
          _isLoading = false;
        });
        // Extract duration after setting the URL
        await _extractDuration();
        return;
      }

      // Handle different content types
      if (widget.message.content.startsWith('http')) {
        // Download from HTTP URL
        final downloadedFile = await _cacheService.downloadAndCacheMedia(
          url: widget.message.content,
          timestamp: widget.message.id,
          type: MediaType.audio,
        );

        if (downloadedFile != null) {
          setState(() {
            _audioUrl = downloadedFile.path;
            _isLoading = false;
          });
          // Extract duration after setting the URL
          await _extractDuration();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else if (widget.message.content.startsWith('/')) {
        // Local file path
        final localFile = File(widget.message.content);
        if (await localFile.exists()) {
          setState(() {
            _audioUrl = localFile.path;
            _isLoading = false;
          });
          // Extract duration after setting the URL
          await _extractDuration();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        // Check metadata for local path
        final localPath = widget.message.metadata?['local_path'] as String?;
        if (localPath != null) {
          final localFile = File(localPath);
          if (await localFile.exists()) {
            setState(() {
              _audioUrl = localFile.path;
              _isLoading = false;
            });
            // Extract duration after setting the URL
            await _extractDuration();
          } else {
            setState(() {
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioPlayer == null) {
      // Show message for unsupported platforms
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio playback not supported on this platform'),
          ),
        );
      }
      return;
    }

    if (_audioUrl == null) {
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      if (_isPlaying) {
        await _audioPlayer!.pausePlayer();
        setState(() {
          _isPlaying = false;
          _isLoading = false;
        });
      } else {
        // For FlutterSound, we need to use resumePlayer if it was paused
        if (_audioPlayer!.isPaused) {
          await _audioPlayer!.resumePlayer();
        } else {
          // Start fresh or seek to position
          if (_position.inMilliseconds > 0) {
            // Start and immediately seek
            await _audioPlayer!.startPlayer(fromURI: _audioUrl!);
            await Future.delayed(const Duration(milliseconds: 100));
            await _audioPlayer!.seekToPlayer(_position);
          } else {
            // Start from beginning
            await _audioPlayer!.startPlayer(fromURI: _audioUrl!);
          }
        }
        
        setState(() {
          _isPlaying = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: ${e.toString()}'),
          ),
        );
        setState(() {
          _isPlaying = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _seekToPosition(double progress) async {
    if (_audioPlayer == null || _duration.inMilliseconds == 0) return;

    try {
      final seekPosition = Duration(
        milliseconds: (_duration.inMilliseconds * progress).round(),
      );

      await _audioPlayer!.seekToPlayer(seekPosition);
      
      setState(() {
        _position = seekPosition;
        _playbackProgress = progress;
      });

      if (kDebugMode) {
        print('🎵 Seeking to position: ${seekPosition.inSeconds}s (${(progress * 100).toStringAsFixed(1)}%)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎵 Error seeking to position: $e');
      }
    }
  }

  @override  
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 350,
        minWidth: 200,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isCurrentUser
            ? AppTheme.primaryBlue
            : AppTheme.chatBubbleBackground,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isCurrentUser ? 18 : 6),
          bottomRight: Radius.circular(widget.isCurrentUser ? 6 : 18),
        ),
        border: widget.isCurrentUser
            ? null
            : Border.all(color: AppTheme.borderColor, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main audio row
          Row(
            children: [
              // Play button
              GestureDetector(
                onTap: _isLoading ? null : _togglePlayback,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.isCurrentUser
                        ? Colors.white.withValues(alpha: 0.15)
                        : AppTheme.primaryBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.isCurrentUser ? Colors.white : AppTheme.primaryBlue,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: widget.isCurrentUser ? Colors.white : AppTheme.primaryBlue,
                            size: 24,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Audio info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWaveform(),
                    const SizedBox(height: 8),
                    _buildDurationInfo(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Bottom row with file size, timestamp and status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildFileSize(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(widget.message.timestamp),
                    style: TextStyle(
                      color: widget.isCurrentUser
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (widget.isCurrentUser) ...[
                    const SizedBox(width: 6),
                    _buildMessageStatus(),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildFileSize() {
    return Text(
      _formatFileSize(_fileSize > 0 ? _fileSize : (widget.message.metadata?['file_size'] as int? ?? 0)),
      style: TextStyle(
        fontSize: 11,
        color: widget.isCurrentUser
            ? Colors.white.withValues(alpha: 0.7)
            : AppTheme.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildMessageStatus() {
    return GestureDetector(
      onTap: widget.message.status == MessageStatus.failed && widget.onRetry != null
          ? widget.onRetry
          : null,
      child: Icon(
        widget.message.status == MessageStatus.sent
            ? Icons.check
            : widget.message.status == MessageStatus.delivered
                ? Icons.done_all
                : widget.message.status == MessageStatus.read
                    ? Icons.done_all
                    : widget.message.status == MessageStatus.failed
                        ? Icons.error_outline
                        : Icons.access_time,
        size: 16,
        color: widget.message.status == MessageStatus.read
            ? AppTheme.primaryBlue
            : widget.message.status == MessageStatus.failed
                ? Colors.red
                : Colors.white.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildWaveform() {
    return GestureDetector(
      onTapDown: (details) {
        // Only allow seeking if audio is loaded and not loading
        if (_duration.inMilliseconds > 0 && !_isLoading) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          final progress = localPosition.dx / box.size.width;
          
          // Clamp progress between 0 and 1
          final clampedProgress = progress.clamp(0.0, 1.0);
          _seekToPosition(clampedProgress);
        }
      },
      child: Container(
        height: 32,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _waveformAnimation,
          builder: (context, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(24, (index) {
                final heights = [6, 18, 10, 24, 8, 16, 22, 12, 26, 8, 18, 14, 20, 16, 12, 18, 10, 24, 14, 16, 8, 20, 12, 18];
                final baseHeight = heights[index % heights.length].toDouble();
                
                final isActive = _playbackProgress > index / 24;
                
                return GestureDetector(
                  onTap: () {
                    if (_duration.inMilliseconds > 0 && !_isLoading) {
                      final progress = (index + 0.5) / 24; // Center of the bar
                      _seekToPosition(progress);
                    }
                  },
                  child: Container(
                    width: 2.5,
                    height: baseHeight,
                    decoration: BoxDecoration(
                      color: isActive
                          ? (widget.isCurrentUser ? Colors.white : AppTheme.primaryBlue)
                          : (widget.isCurrentUser
                              ? Colors.white.withValues(alpha: 0.35)
                              : AppTheme.primaryBlue.withValues(alpha: 0.25)),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDurationInfo() {
    final metadata = widget.message.metadata ?? {};
    
    String durationText;
    if (_isLoading) {
      durationText = 'Loading...';
    } else if (_audioUrl != null && _duration.inSeconds > 0) {
      durationText = '${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')} / ${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}';
    } else if (metadata['duration'] != null) {
      final totalDurationMs = metadata['duration'] as int;
      final totalDuration = Duration(milliseconds: totalDurationMs);
      durationText = '${totalDuration.inMinutes}:${(totalDuration.inSeconds % 60).toString().padLeft(2, '0')}';
    } else {
      durationText = '0:00';
    }

    return Text(
      durationText,
      style: TextStyle(
        fontSize: 12,
        color: widget.isCurrentUser
            ? Colors.white.withValues(alpha: 0.8)
            : AppTheme.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }



  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }


}