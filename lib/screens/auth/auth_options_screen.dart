import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_theme.dart';
import '../../constants/app_constants.dart';

class AuthOptionsScreen extends StatelessWidget {
  const AuthOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            children: [
              // Top Welcome Image
              _buildWelcomeImage(),
              
              const SizedBox(height: 32),
              
              // Main Text "Let's you in"
              _buildMainText(),
              
              const SizedBox(height: 24),
              
              // Authentication Options
              _buildAuthButtons(context),
              
              const SizedBox(height: 24),
              
              // Or Divider
              _buildOrDivider(),
              
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

  Widget _buildWelcomeImage() {
    return Container(
      width: 356,
      height: 275,
      child: Image.asset(
        'assets/images/wl_2_image.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback image/icon if the main image is not found
          return Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.people_alt_outlined,
              size: 120,
              color: AppColors.primary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainText() {
    return Text(
      "Let's you in",
      style: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
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
        _buildAuthButton(
          context: context,
          text: "Continue With Google",
          imagePath: "assets/icons/g_icon.png",
          onTap: () => _showComingSoon(context, "Google Sign In"),
        ),
        
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
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
                    color: Colors.black87,
                  );
                },
              ),
              const SizedBox(width: 16),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: Colors.black87,
              ),
              const SizedBox(width: 16),
            ],
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: Colors.black,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Or",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: const Color(0xFF191919),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSignInButton(BuildContext context) {
    return SizedBox(
      width: 262,
      height: 36,
      child: ElevatedButton(
        onPressed: () => _showComingSoon(context, "Phone Sign In"),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?",
          style: GoogleFonts.poppins(
            fontSize: 9.68,
            color: Colors.black,
            fontWeight: FontWeight.w400,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppConstants.registerRoute),
          child: Text(
            " Sign Up",
            style: GoogleFonts.poppins(
              fontSize: 9.68,
              color: AppColors.primary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming Soon!'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}