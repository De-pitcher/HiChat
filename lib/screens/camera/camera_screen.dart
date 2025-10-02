import 'package:flutter/material.dart';
import 'dart:convert';
import '../../services/camera_service.dart';
import '../../constants/app_theme.dart';

/// Camera screen for capturing images, videos, and audio
/// 
/// This screen provides a professional interface for all camera operations
/// with proper error handling, loading states, and result display.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  
  // State management
  CameraResult? _lastResult;
  String? _currentOperation;
  bool _isProcessing = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _showWelcomeMessage();
    _loadCaptureStats();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  /// Initialize animations for UI effects
  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }
  
  /// Show welcome message when screen loads
  void _showWelcomeMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCustomSnackBar(
        'Welcome to HiChat Camera! Tap any button to start capturing.',
        Colors.blue,
        icon: Icons.camera_enhance,
      );
    });
  }
  
  /// Load capture statistics
  void _loadCaptureStats() async {
    try {
      final stats = await CameraService.getCaptureStats();
      if (stats.totalCaptures > 0) {
        _showCustomSnackBar(
          'You have captured ${stats.totalCaptures} media files so far!',
          Colors.green,
          icon: Icons.analytics,
        );
      }
    } catch (e) {
      // Silently ignore stats loading errors
    }
  }
  
  /// Generic method to handle camera operations
  Future<void> _performCameraOperation(
    Future<CameraResult> Function() operation,
    String operationName,
    IconData icon,
    Color color,
  ) async {
    // Prevent multiple simultaneous operations
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _currentOperation = operationName;
    });
    
    // Start button animation
    _animationController.forward();
    
    try {
      // Show operation started feedback
      _showOperationStarted(operationName, icon);
      
      // Perform the camera operation
      final CameraResult result = await operation();
      
      setState(() {
        _lastResult = result;
      });
      
      // Show success feedback
      _showOperationSuccess(operationName, result, icon);
      
    } on CameraException catch (e) {
      _showCameraError(operationName, e);
    } catch (e) {
      _showGenericError(operationName, e.toString());
    } finally {
      setState(() {
        _isProcessing = false;
        _currentOperation = null;
      });
      
      // Reset button animation
      _animationController.reverse();
    }
  }
  
  /// Show operation started feedback
  void _showOperationStarted(String operationName, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('$operationName in progress...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
  
  /// Show operation success feedback
  void _showOperationSuccess(String operationName, CameraResult result, IconData icon) {
    _showCustomSnackBar(
      '$operationName completed! Captured ${result.formattedSize} of ${result.type.name} data.',
      Colors.green,
      icon: icon,
    );
  }
  
  /// Show camera-specific error
  void _showCameraError(String operationName, CameraException error) {
    _showCustomSnackBar(
      error.userMessage,
      Colors.red,
      icon: Icons.error_outline,
    );
  }
  
  /// Show generic error
  void _showGenericError(String operationName, String error) {
    _showCustomSnackBar(
      '$operationName failed: $error',
      Colors.red,
      icon: Icons.error_outline,
    );
  }
  
  /// Show custom colored snack bar
  void _showCustomSnackBar(String message, Color backgroundColor, {IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
  
  /// Capture image
  Future<void> _captureImage() async {
    await _performCameraOperation(
      CameraService.captureImage,
      'Image capture',
      Icons.camera_alt,
      Colors.blue,
    );
  }
  
  /// Record video
  Future<void> _recordVideo() async {
    await _performCameraOperation(
      CameraService.recordVideo,
      'Video recording',
      Icons.videocam,
      Colors.red,
    );
  }
  
  /// Record audio
  Future<void> _recordAudio() async {
    await _performCameraOperation(
      CameraService.recordAudio,
      'Audio recording',
      Icons.mic,
      Colors.green,
    );
  }
  
  /// Save current result to file
  Future<void> _saveToFile() async {
    if (_lastResult == null) return;
    
    try {
      setState(() => _isProcessing = true);
      
      final filename = 'hichat_${_lastResult!.type.name}';
      final filePath = await CameraService.saveMediaToFile(
        _lastResult!.data,
        filename,
        _lastResult!.type,
      );
      
      _showCustomSnackBar(
        'Media saved to: $filePath',
        Colors.green,
        icon: Icons.save,
      );
      
    } catch (e) {
      _showCustomSnackBar(
        'Failed to save file: $e',
        Colors.red,
        icon: Icons.error,
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }
  
  /// Clear current result
  void _clearResult() {
    setState(() {
      _lastResult = null;
    });
    _showCustomSnackBar('Result cleared', Colors.blue, icon: Icons.clear);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HiChat Camera',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_lastResult != null)
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: _isProcessing ? null : _saveToFile,
              tooltip: 'Save to file',
            ),
          if (_lastResult != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: _isProcessing ? null : _clearResult,
              tooltip: 'Clear result',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header section
            _buildHeaderSection(),
            
            const SizedBox(height: 24),
            
            // Camera operation buttons
            _buildOperationButtons(),
            
            const SizedBox(height: 24),
            
            // Results section
            if (_lastResult != null) _buildResultsSection(),
          ],
        ),
      ),
    );
  }
  
  /// Build header section with app info
  Widget _buildHeaderSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const Icon(
                Icons.camera_enhance,
                size: 48,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                'Camera Service',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Capture images, record videos, and audio with professional quality',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build operation buttons section
  Widget _buildOperationButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Camera Operations',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        // Image capture button
        _buildOperationButton(
          label: 'Capture Image',
          icon: Icons.camera_alt,
          onPressed: _captureImage,
          description: 'Take a high-quality photo',
          isActive: _currentOperation == 'Image capture',
          color: Colors.blue,
        ),
        
        const SizedBox(height: 12),
        
        // Video recording button
        _buildOperationButton(
          label: 'Record Video',
          icon: Icons.videocam,
          onPressed: _recordVideo,
          description: 'Record video with audio',
          isActive: _currentOperation == 'Video recording',
          color: Colors.red,
        ),
        
        const SizedBox(height: 12),
        
        // Audio recording button
        _buildOperationButton(
          label: 'Record Audio',
          icon: Icons.mic,
          onPressed: _recordAudio,
          description: 'Record audio only',
          isActive: _currentOperation == 'Audio recording',
          color: Colors.green,
        ),
      ],
    );
  }
  
  /// Build individual operation button
  Widget _buildOperationButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required String description,
    required bool isActive,
    required Color color,
  }) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isActive ? _scaleAnimation.value : 1.0,
          child: Card(
            elevation: isActive ? 8 : 2,
            color: isActive ? color.withValues(alpha: 0.1) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isProcessing ? null : onPressed,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isProcessing ? Colors.grey[300] : color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: isActive
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(
                              icon,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isActive ? color : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isProcessing)
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.grey[400],
                        size: 16,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  /// Build results section
  Widget _buildResultsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Last Result',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: _isProcessing ? null : _clearResult,
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Result card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Success header
                Row(
                  children: [
                    Icon(
                      _getMediaTypeIcon(_lastResult!.type),
                      color: _getMediaTypeColor(_lastResult!.type),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Capture Successful',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _getMediaTypeColor(_lastResult!.type),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Media information
                _buildInfoContainer(),
                
                const SizedBox(height: 16),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _saveToFile,
                        icon: const Icon(Icons.save),
                        label: const Text('Save File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : () {
                          // Show preview/share options
                          _showMediaPreview();
                        },
                        icon: const Icon(Icons.preview),
                        label: const Text('Preview'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  /// Build media information container
  Widget _buildInfoContainer() {
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Media Information:',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),          _buildInfoRow(Icons.category, 'Type', _lastResult!.type.name.toUpperCase()),
          const SizedBox(height: 4),
          _buildInfoRow(Icons.data_usage, 'Size', _lastResult!.formattedSize),
          const SizedBox(height: 4),
          _buildInfoRow(Icons.access_time, 'Duration', '${_lastResult!.duration.inMilliseconds}ms'),
          const SizedBox(height: 4),
          _buildInfoRow(Icons.schedule, 'Captured', _formatTime(_lastResult!.captureTime)),
          
          const SizedBox(height: 12),
          
          Text(
            'Data Preview:',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: Text(
              _lastResult!.dataPreview,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.black87,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
    );
  }
  
  /// Build information row
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(color: Colors.black87)),
      ],
    );
  }
  
  /// Get media type icon
  IconData _getMediaTypeIcon(MediaType type) {
    switch (type) {
      case MediaType.image:
        return Icons.image;
      case MediaType.video:
        return Icons.video_file;
      case MediaType.audio:
        return Icons.audio_file;
    }
  }
  
  /// Get media type color
  Color _getMediaTypeColor(MediaType type) {
    switch (type) {
      case MediaType.image:
        return Colors.blue;
      case MediaType.video:
        return Colors.red;
      case MediaType.audio:
        return Colors.green;
    }
  }
  
  /// Format time for display
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
  
  /// Show media preview dialog
  void _showMediaPreview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_lastResult!.type.name.toUpperCase()} Preview'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getMediaTypeIcon(_lastResult!.type),
              size: 64,
              color: _getMediaTypeColor(_lastResult!.type),
            ),
            const SizedBox(height: 16),
            Text('Size: ${_lastResult!.formattedSize}'),
            Text('Captured: ${_formatTime(_lastResult!.captureTime)}'),
            const SizedBox(height: 16),
            if (_lastResult!.type == MediaType.image)
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(_lastResult!.data),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text('Failed to load image preview'),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _saveToFile();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}