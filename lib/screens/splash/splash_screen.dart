import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _navigateToHome();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  _navigateToHome() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? theme.scaffoldBackgroundColor : AppColors.splashBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Main content area with welcome image
            Expanded(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32.0),
                  child: Image.asset(
                    'assets/images/welcome_img.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback if image is not found
                      return Icon(
                        Icons.chat_bubble_outline,
                        size: 120,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      );
                    },
                  ),
                ),
              ),
            ),
            
            // Loading spinner at the bottom
            Container(
              padding: const EdgeInsets.only(bottom: 80.0),
              child: _buildCustomDottedSpinner(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomDottedSpinner() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final theme = Theme.of(context);
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final delay = index * 0.2;
            final animationValue = (_animationController.value + delay) % 1.0;
            final opacity = (0.3 + (0.7 * (1 - (animationValue * 2 - 1).abs()))).clamp(0.3, 1.0);
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.0),
              width: 5.77,
              height: 5.66,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}