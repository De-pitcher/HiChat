import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import '../../models/chat.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';
import '../../services/chat_state_manager.dart';
import '../../services/audio_recording_service.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onGalleryPressed;
  final Chat chat;
  final bool isEditMode;
  final VoidCallback? onCancelEdit;
  final Message? editingMessage;
  final bool isReplyMode;
  final VoidCallback? onCancelReply;
  final Message? replyingToMessage;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
    required this.chat,
    this.onCameraPressed,
    this.onGalleryPressed,
    this.isEditMode = false,
    this.onCancelEdit,
    this.editingMessage,
    this.isReplyMode = false,
    this.onCancelReply,
    this.replyingToMessage,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with SingleTickerProviderStateMixin {
  bool _hasText = false;
  bool _isRecording = false;
  bool _showEmojiPicker = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late final AudioRecordingService _audioRecordingService;

  // Recording timer state
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  static const int maxRecordingSeconds = 300; // 5 minutes max

  @override
  void initState() {
    super.initState();
    _audioRecordingService = AudioRecordingService();
    widget.controller.addListener(_onTextChanged);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _animationController.dispose();
    _stopRecordingTimer();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
      if (hasText) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = Duration.zero;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration = Duration(
          seconds: _recordingDuration.inSeconds + 1,
        );
      });

      // Auto-stop recording at max duration
      if (_recordingDuration.inSeconds >= maxRecordingSeconds) {
        _stopRecording();
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Reply mode indicator
        if (widget.isReplyMode) _buildReplyModeIndicator(),

        // Edit mode indicator
        if (widget.isEditMode) _buildEditModeIndicator(),

        // Main input area
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                // Attachment button
                if (!_isRecording)
                  IconButton(
                    onPressed: _showAttachmentOptions,
                    icon: const Icon(Icons.add),
                    color: AppColors.primary,
                    iconSize: 28,
                  ),

                // Text input or recording widget
                Expanded(
                  child: _isRecording
                      ? _buildRecordingWidget()
                      : _buildTextInputField(context),
                ),

                const SizedBox(width: 8),

                // Send/Mic button - Hide when recording widget is active
                if (!_isRecording)
                  GestureDetector(
                    onTap: () {
                      debugPrint('🎤 Button tapped - hasText: $_hasText, isEditMode: ${widget.isEditMode}, isRecording: $_isRecording');
                      
                      if (_hasText || widget.isEditMode) {
                        // Send message when there's text or in edit mode
                        debugPrint('🎤 Sending message');
                        widget.onSend();
                      } else {
                        // Start recording when no text and not recording
                        debugPrint('🎤 Starting recording via tap');
                        _startRecording();
                      }
                    },
                  onLongPressStart: (_) {
                    if (!_hasText && !widget.isEditMode && !_isRecording) {
                      _startRecording();
                    }
                  },
                    onLongPressEnd: (_) {
                      if (_isRecording) {
                        _stopRecording();
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _hasText || widget.isEditMode
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_hasText || widget.isEditMode)
                                      ? AppColors.primary.withValues(alpha: 0.3)
                                      : Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              _hasText || widget.isEditMode
                                  ? Icons.send
                                  : Icons.mic,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Emoji picker
        if (_showEmojiPicker) _buildEmojiPicker(),
      ],
    );
  }

  Widget _buildReplyModeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${widget.replyingToMessage?.senderUsername ?? "Unknown"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.replyingToMessage?.content ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelReply,
            icon: const Icon(Icons.close),
            color: Colors.grey[600],
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildEditModeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.edit,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit Message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.editingMessage?.content ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelEdit,
            icon: const Icon(Icons.close),
            color: Colors.grey[600],
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildTextInputField(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      child: TextField(
        controller: widget.controller,
        keyboardType: TextInputType.multiline,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: widget.isEditMode
              ? 'Edit message...'
              : 'Type a message...',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 16,
          ),
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          
          // Prefix icon for emoji/keyboard toggle
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: IconButton(
              onPressed: _toggleEmojiPicker,
              icon: Icon(
                _showEmojiPicker
                    ? Icons.keyboard
                    : Icons.emoji_emotions_outlined,
              ),
              color: AppColors.primary,
              iconSize: 22,
              splashRadius: 20,
            ),
          ),
          
          // Border styling to match auth textfields
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
        ),
        onSubmitted: (_) => _hasText ? widget.onSend() : null,
      ),
    );
  }

  Widget _buildEmojiPicker() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          widget.controller.text += emoji.emoji;
          _onTextChanged();
        },
        config: Config(
          height: 256,
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: theme.scaffoldBackgroundColor,
            emojiSizeMax: 28,
            columns: 7,
            verticalSpacing: 0,
            horizontalSpacing: 0,
            gridPadding: EdgeInsets.zero,
            recentsLimit: 28,
            replaceEmojiOnLimitExceed: false,
            noRecents: Text(
              'No Recents',
              style: TextStyle(
                fontSize: 16,
                color: theme.textTheme.bodyMedium?.color,
              ),
              textAlign: TextAlign.center,
            ),
            loadingIndicator: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: theme.scaffoldBackgroundColor,
            iconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            iconColorSelected: theme.colorScheme.primary,
            backspaceColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            categoryIcons: const CategoryIcons(),
            indicatorColor: theme.colorScheme.primary,
            dividerColor: theme.dividerColor,
            showBackspaceButton: true,
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: theme.scaffoldBackgroundColor,
            buttonColor: theme.scaffoldBackgroundColor,
            buttonIconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            showSearchViewButton: false,
            showBackspaceButton: true,
            enabled: true,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: theme.scaffoldBackgroundColor,
            buttonColor: theme.cardColor,
            buttonIconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            hintText: 'Search emoji',
          ),
          skinToneConfig: SkinToneConfig(
            enabled: true,
            dialogBackgroundColor: theme.cardColor,
            indicatorColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });

    if (_showEmojiPicker) {
      // Hide keyboard when showing emoji picker
      FocusScope.of(context).unfocus();
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Attachment options
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onCameraPressed?.call();
                  },
                ),
                AttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onGalleryPressed?.call();
                  },
                ),
                AttachmentOption(
                  icon: Icons.location_on,
                  label: 'Location',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _shareLocation();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _shareLocation() async {
    try {
      // Request location permission
      final status = await Permission.location.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get current location and send as message
      if (mounted) {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting location...'),
            duration: Duration(seconds: 2),
          ),
        );

        // TODO: Implement shareLocation method in ChatStateManager
        // final chatStateManager = Provider.of<ChatStateManager>(context, listen: false);
        // await chatStateManager.shareLocation(widget.chat.id);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location sharing feature coming soon!'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to get location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startRecording() async {
    debugPrint('🎤 Starting audio recording...');
    try {
      final hasPermission = await _audioRecordingService.hasPermission();
      debugPrint('🎤 Has permission: $hasPermission');
      
      if (!hasPermission) {
        debugPrint('🎤 Requesting microphone permission...');
        final granted = await _audioRecordingService.requestPermission();
        debugPrint('🎤 Permission granted: $granted');
        
        if (!granted) {
          debugPrint('🎤 Permission denied - showing error message');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Microphone permission required for voice messages'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      debugPrint('🎤 Starting recording service...');
      await _audioRecordingService.startRecording();
      
      debugPrint('🎤 Recording started successfully - updating UI');
      setState(() {
        _isRecording = true;
      });
      _startRecordingTimer();

      // Haptic feedback
      HapticFeedback.lightImpact();
      
      debugPrint('🎤 Audio recording initialized successfully');
    } catch (e) {
      debugPrint('🎤 ❌ Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start recording'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopRecording() async {
    debugPrint('🎤 Stopping audio recording...');
    if (!_isRecording) {
      debugPrint('🎤 ⚠️ Not currently recording, ignoring stop request');
      return;
    }

    try {
      debugPrint('🎤 Stopping recording service...');
      final audioFile = await _audioRecordingService.stopRecording();
      debugPrint('🎤 Recording stopped, audio file: $audioFile');
      
      setState(() {
        _isRecording = false;
      });
      _stopRecordingTimer();

      if (audioFile != null && mounted) {
        // Send audio message
        final chatStateManager = Provider.of<ChatStateManager>(
          context,
          listen: false,
        );
        
        await chatStateManager.sendAudioMessage(
          chatId: widget.chat.id,
          audioFilePath: audioFile,
          duration: _recordingDuration,
        );
      }

      // Haptic feedback
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save recording'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelRecording() async {
    if (!_isRecording) return;

    try {
      debugPrint('🎤 Cancelling recording...');
      
      // Stop recording timer first
      _stopRecordingTimer();
      
      // Cancel recording in service (this deletes the file)
      await _audioRecordingService.cancelRecording();
      
      // Reset UI state
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
      
      // Haptic feedback
      HapticFeedback.lightImpact();
      
      debugPrint('✅ Recording cancelled successfully');
    } catch (e) {
      debugPrint('❌ Error cancelling recording: $e');
    }
  }

  Widget _buildRecordingWidget() {
    final primaryColor = AppColors.primary; // Use app's primary blue color
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Recording... ${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // CANCEL BUTTON - first position (discard recording)
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1),
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          // SEND BUTTON - second position (send recording)
          GestureDetector(
            onTap: _stopRecording, // This will send the recording
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const AttachmentOption({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}