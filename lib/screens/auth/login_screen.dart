import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../services/auth_state_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _loadRememberedCredentials() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authManager = context.read<AuthStateManager>();
      if (authManager.rememberMe && authManager.rememberedEmail.isNotEmpty) {
        _emailController.text = authManager.rememberedEmail;
        if (authManager.rememberedPassword.isNotEmpty) {
          _passwordController.text = authManager.rememberedPassword;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        systemOverlayStyle: theme.brightness == Brightness.dark 
          ? SystemUiOverlayStyle.light 
          : SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 24),
                
                // App Logo
                _buildAppLogo(),
                
                const SizedBox(height: 48),
                
                // Title
                _buildTitle(),
                
                const SizedBox(height: 32),
                
                // Email Field
                _buildEmailField(),
                
                const SizedBox(height: 12),
                
                // Password Field
                _buildPasswordField(),
                
                const SizedBox(height: 20),
                
                // Remember Me
                _buildRememberMe(),
                
                const SizedBox(height: 81),
                
                // Sign In Button
                _buildSignInButton(),
                
                const SizedBox(height: 32),
                
                // Sign Up Link
                _buildSignUpLink(),
                
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppLogo() {
    final theme = Theme.of(context);
    
    return SizedBox(
      width: 133,
      height: 115,
      child: Image.asset(
        'assets/images/app_logo.png', // Using existing welcome image as fallback
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.chat_bubble_outline,
            size: 60,
            color: theme.colorScheme.primary,
          );
        },
      ),
    );
  }

  Widget _buildTitle() {
    final theme = Theme.of(context);
    
    return Text(
      'Login to Your Account',
      style: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildEmailField() {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _emailController,
        focusNode: _emailFocusNode,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: 'Enter email',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 16,
          ),
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your email';
          }
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Enter a valid email';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField() {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        obscureText: !_isPasswordVisible,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _handleSignIn(),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontSize: 16,
          ),
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          suffixIcon: IconButton(
            icon: Icon(
              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            onPressed: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
          ),
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
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your password';
          }
          if (value.length < 6) {
            return 'Password must be at least 6 characters';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildRememberMe() {
    final theme = Theme.of(context);
    
    return Consumer<AuthStateManager>(
      builder: (context, authManager, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  authManager.updateRememberMe(!authManager.rememberMe);
                },
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: authManager.rememberMe ? theme.colorScheme.primary : Colors.transparent,
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: authManager.rememberMe
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: theme.colorScheme.onPrimary,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  authManager.updateRememberMe(!authManager.rememberMe);
                },
                child: Text(
                  'Remember Me',
                  style: GoogleFonts.poppins(
                    fontSize: 12.82,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignInButton() {
    final theme = Theme.of(context);
    
    return Consumer<AuthStateManager>(
      builder: (context, authManager, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          child: SizedBox(
            width: 262,
            height: 52,
            child: ElevatedButton(
            onPressed: authManager.isLoading ? null : _handleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
              disabledBackgroundColor: theme.colorScheme.primary.withOpacity(0.6),
            ),
            child: authManager.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimary),
                    ),
                  )
                : Text(
                    'Sign in',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignUpLink() {
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

  void _handleSignIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authManager = context.read<AuthStateManager>();
    
    final result = await authManager.login(
      _emailController.text.trim(),
      _passwordController.text,
      rememberMe: authManager.rememberMe,
    );

    if (mounted) {
      if (result.isSuccess) {
        // Navigate directly to chat list screen since login was successful
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppConstants.chatListRoute,
          (route) => false,
        );
      } else {
        // Show error message
        _showErrorSnackBar(result.errorMessage ?? 'Login failed');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}