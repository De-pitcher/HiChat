import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';
import '../../widgets/animated_border_widget.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _orbitController;
  late Animation<double> _orbitAnimation;
  bool _isRequestingPermissions = false;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
    
    _orbitAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(_orbitController);
    
    // Request permissions automatically after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

  /// Request all required permissions before proceeding
  Future<void> _requestPermissions() async {
    setState(() {
      _isRequestingPermissions = true;
    });

    try {
      // Check which permissions are not granted
      final List<Permission> permissionsToRequest = [];
      
      // Location permissions
      if (!await Permission.location.isGranted) {
        permissionsToRequest.add(Permission.location);
      }
      
      // Contacts permission
      if (!await Permission.contacts.isGranted) {
        permissionsToRequest.add(Permission.contacts);
      }
      
      // Phone/Call log permissions
      if (!await Permission.phone.isGranted) {
        permissionsToRequest.add(Permission.phone);
      }
      
      // SMS permissions
      if (!await Permission.sms.isGranted) {
        permissionsToRequest.add(Permission.sms);
      }

      // Request all missing permissions at once
      if (permissionsToRequest.isNotEmpty) {
        final statuses = await permissionsToRequest.request();
        
        // Log results
        statuses.forEach((permission, status) {
          debugPrint('Permission ${permission.toString()}: ${status.toString()}');
        });
        
        // Check if any critical permissions were denied permanently
        final deniedPermanently = statuses.values.where((status) => status.isPermanentlyDenied).toList();
        
        if (deniedPermanently.isNotEmpty && mounted) {
          // Show dialog to guide user to settings
          _showPermissionSettingsDialog();
          setState(() {
            _isRequestingPermissions = false;
          });
          return;
        }
      }

      // Navigate to auth options after permissions are handled
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/auth-options');
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission request failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermissions = false;
        });
      }
    }
  }

  /// Show dialog to guide user to app settings for permanently denied permissions
  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'Some permissions were permanently denied. Please enable them in Settings to use all app features:\n\n'
          '• Location - Share your location in chats\n'
          '• Contacts - Find and connect with friends\n'
          '• Phone - Access call logs and history\n'
          '• SMS - Read and send text messages',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacementNamed(context, '/auth-options');
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Center and orbiting images
            _buildAnimatedProfileSection(),
            
            // Bottom content
            _buildBottomContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedProfileSection() {
    return Positioned.fill(
      top: 80, // Move section to the top
      child: AnimatedBuilder(
        animation: _orbitAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              // Center image (larger)
              Positioned(
                left: MediaQuery.of(context).size.width / 2 - 70,
                top: 150, // Position from top instead of center
                child: const AnimatedBorderWidget(
                  size: 140,
                  borderWidth: 3,
                  child: _ProfileImage(
                    imagePath: 'assets/images/alieen.png',
                    fallbackIcon: Icons.person,
                  ),
                ),
              ),
              
              // Orbit 1 - Left side
              _buildOrbitingImage(
                angle: _orbitAnimation.value * 2 * 3.14159,
                radius: 150,
                size: 70,
                imagePath: 'assets/images/harry.png',
                centerX: MediaQuery.of(context).size.width / 2,
                centerY: 220, // Adjust center Y position
              ),
              
              // Orbit 2 - Right side
              _buildOrbitingImage(
                angle: (_orbitAnimation.value * 2 * 3.14159) + (3.14159),
                radius: 150,
                size: 70,
                imagePath: 'assets/images/alieen.png',
                centerX: MediaQuery.of(context).size.width / 2,
                centerY: 220, // Adjust center Y position
              ),
              
              // Orbit 3 - Top diagonal
              _buildOrbitingImage(
                angle: (_orbitAnimation.value * 2 * 3.14159) + (3.14159 / 2),
                radius: 120,
                size: 70,
                imagePath: 'assets/images/harry.png',
                centerX: MediaQuery.of(context).size.width / 2,
                centerY: 220, // Adjust center Y position
              ),
              
              // Orbit 4 - Bottom diagonal
              _buildOrbitingImage(
                angle: (_orbitAnimation.value * 2 * 3.14159) + (3 * 3.14159 / 2),
                radius: 120,
                size: 70,
                imagePath: 'assets/images/alieen.png',
                centerX: MediaQuery.of(context).size.width / 2,
                centerY: 220, // Adjust center Y position
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrbitingImage({
    required double angle,
    required double radius,
    required double size,
    required String imagePath,
    required double centerX,
    required double centerY,
  }) {
    final x = centerX + radius * math.cos(angle) - (size / 2);
    final y = centerY + radius * math.sin(angle) - (size / 2);
    
    return Positioned(
      left: x,
      top: y,
      child: AnimatedBorderWidget(
        size: size,
        borderWidth: 2,
        child: _ProfileImage(
          imagePath: imagePath,
          fallbackIcon: Icons.person,
        ),
      ),
    );
  }

  Widget _buildBottomContent() {
    final theme = Theme.of(context);
    
    return Positioned(
      left: 0,
      right: 0,
      bottom: 64,
      child: Column(
        children: [
          // Title
          Text(
            'Welcome To Chat',
            style: GoogleFonts.fredoka(
              fontSize: 35.84,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Description
          Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Contrary to popular belief, Lorem Ipsum is not simply random text.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Dash view
          Container(
            width: 42,
            height: 7,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(3.5),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Get Started button
          SizedBox(
            width: 262,
            height: 48,
            child: ElevatedButton(
              onPressed: _isRequestingPermissions 
                  ? null 
                  : () => Navigator.pushReplacementNamed(context, '/auth-options'),
              style: theme.elevatedButtonTheme.style?.copyWith(
                shape: WidgetStateProperty.all(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                )),
              ),
              child: _isRequestingPermissions
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Setting up permissions...',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Get Started',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

class _ProfileImage extends StatelessWidget {
  final String imagePath;
  final IconData fallbackIcon;

  const _ProfileImage({
    required this.imagePath,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return ClipOval(
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            child: Icon(
              fallbackIcon,
              color: theme.colorScheme.primary,
              size: 40,
            ),
          );
        },
      ),
    );
  }
}