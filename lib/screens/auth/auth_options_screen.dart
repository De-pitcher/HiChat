import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../services/google_signin_service.dart';
import '../../services/auth_state_manager.dart';

class AuthOptionsScreen extends StatefulWidget {
  const AuthOptionsScreen({super.key});

  @override
  State<AuthOptionsScreen> createState() => _AuthOptionsScreenState();
}

class _AuthOptionsScreenState extends State<AuthOptionsScreen> {
  final GoogleSignInService _googleSignInService = GoogleSignInService();
  bool _isGoogleSignInLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            children: [
              // Top Welcome Image
              _buildWelcomeImage(context),
              
              const SizedBox(height: 32),
              
              // Main Text "Let's you in"
              _buildMainText(context),
              
              const SizedBox(height: 24),
              
              // Authentication Options
              _buildAuthButtons(context),
              
              const SizedBox(height: 24),
              
              // Or Divider
              _buildOrDivider(context),
              
              const SizedBox(height: 24),
              
              // Sign in with Phone Button
              _buildPhoneSignInButton(context),
              
              const SizedBox(height: 32),
              
              // Bottom Sign Up Text
              _buildSignUpText(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeImage(BuildContext context) {
    final theme = Theme.of(context);
    
    return SizedBox(
      width: 356,
      height: 275,
      child: Image.asset(
        'assets/images/wl_2_image.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback image/icon if the main image is not found
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.people_alt_outlined,
              size: 120,
              color: theme.colorScheme.primary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainText(BuildContext context) {
    final theme = Theme.of(context);
    
    return Text(
      "Let's you in",
      style: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildAuthButtons(BuildContext context) {
    return Column(
      children: [
        // Email and Password Button
        _buildAuthButton(
          context: context,
          text: "Sign in with Email and Password",
          onTap: () => Navigator.pushNamed(context, AppConstants.loginRoute),
        ),
        
        const SizedBox(height: 24),
        
        // Google Button
        _buildGoogleSignInButton(context),
        
        const SizedBox(height: 24),
        
        // Apple Button
        _buildAuthButton(
          context: context,
          text: "Continue With Apple",
          icon: Icons.apple,
          onTap: () => _showComingSoon(context, "Apple Sign In"),
        ),
      ],
    );
  }

  Widget _buildAuthButton({
    required BuildContext context,
    required String text,
    IconData? icon,
    String? imagePath,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (imagePath != null) ...[
              Image.asset(
                imagePath,
                width: 20,
                height: 20,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.image_not_supported,
                    size: 20,
                    color: theme.colorScheme.onSurface,
                  );
                },
              ),
              const SizedBox(width: 16),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 16),
            ],
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrDivider(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: theme.dividerColor,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Or",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: theme.dividerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSignInButton(BuildContext context) {
    final theme = Theme.of(context);
    
    return SizedBox(
      width: 262,
      height: 52,
      child: ElevatedButton(
        onPressed: () => Navigator.pushNamed(context, AppConstants.phoneSigninRoute),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          elevation: 0,
        ),
        child: Text(
          "Sign in With Phone Number",
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSignUpText(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?",
          style: GoogleFonts.poppins(
            fontSize: 9.68,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w400,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppConstants.registerRoute),
          child: Text(
            " Sign Up",
            style: GoogleFonts.poppins(
              fontSize: 9.68,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleSignInButton(BuildContext context) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: _isGoogleSignInLoading ? null : () => _handleGoogleSignIn(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isGoogleSignInLoading) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 16),
            ] else ...[
              Image.asset(
                "assets/icons/g_icon.png",
                width: 20,
                height: 20,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.g_mobiledata,
                    size: 20,
                    color: theme.colorScheme.onSurface,
                  );
                },
              ),
              const SizedBox(width: 16),
            ],
            Text(
              _isGoogleSignInLoading ? "Signing in..." : "Continue With Google",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    // Capture context reference for safe async usage
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authManager = Provider.of<AuthStateManager>(context, listen: false);
    
    setState(() {
      _isGoogleSignInLoading = true;
    });

    try {
      final result = await _googleSignInService.signInWithGoogle();
      
      if (!mounted) return;
      
      if (result == null) {
        // User cancelled the sign-in
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Sign-in was cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Update auth state with Google Sign-In result
      await authManager.handleGoogleSignInResult(result.user);

      if (!mounted) return;

      // Show success message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            result.isNewUser 
              ? 'Welcome ${result.user.username}! Account created successfully.'
              : 'Welcome back ${result.user.username}!',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to chat screen - AuthWrapper will handle routing automatically
      navigator.pushNamedAndRemoveUntil(
        '/', // Go to root, AuthWrapper will redirect to chat list
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        // Show user-friendly error message
        String errorMessage = 'Google Sign-In failed. Please try again.';
        
        if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection and try again.';
        } else if (e.toString().contains('cancelled')) {
          errorMessage = 'Sign-in was cancelled.';
        } else if (e.toString().contains('type') && e.toString().contains('subtype')) {
          errorMessage = 'Authentication error. Please try again or contact support.';
        }
        
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
        
        // Additional logging for debugging
        debugPrint('Detailed Google Sign-In error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSignInLoading = false;
        });
      }
    }
  }



  void _showComingSoon(BuildContext context, String feature) {
    final theme = Theme.of(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming Soon!'),
        duration: const Duration(seconds: 2),
        backgroundColor: theme.colorScheme.primary,
      ),
    );
  }
}