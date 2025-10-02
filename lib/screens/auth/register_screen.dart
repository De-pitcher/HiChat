import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  bool _rememberMe = false;
  bool _isLoading = false;
  
  // Services
  late ApiService _apiService;
  late SharedPreferences _sharedPreferences;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _initializeSharedPreferences();
  }

  Future<void> _initializeSharedPreferences() async {
    _sharedPreferences = await SharedPreferences.getInstance();
    _loadSavedCredentials();
  }

  void _loadSavedCredentials() {
    final savedUsername = _sharedPreferences.getString('username');
    final savedEmail = _sharedPreferences.getString('email');
    final savedPassword = _sharedPreferences.getString('password');
    
    if (savedEmail != null && savedEmail.isNotEmpty && 
        savedPassword != null && savedPassword.isNotEmpty) {
      setState(() {
        if (savedUsername != null && savedUsername.isNotEmpty) {
          _usernameController.text = savedUsername;
        }
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (!_validateInput(username, email, password)) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create basic signup request with minimum required fields
      final signupRequest = SignupRequest(
        username: username,
        email: email,
        password: password,
        name: username, // Use username as initial name
        about: '', // Empty about initially
        dateOfBirth: '1999-01-01', // Default date, will be updated in profile setup
      );

      // Call signup API to create basic account
      final signupResponse = await _apiService.signupUser(signupRequest);

      // Save credentials if remember me is checked
      if (_rememberMe) {
        await _sharedPreferences.setString('username', username);
        await _sharedPreferences.setString('email', email);
        await _sharedPreferences.setString('password', password);
      } else {
        await _sharedPreferences.remove('username');
        await _sharedPreferences.remove('email');
        await _sharedPreferences.remove('password');
      }

      // Navigate to profile setup to complete profile with the user token
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          AppConstants.profileSetupRoute,
          arguments: {
            'user_token': signupResponse.user.token,
            'email': email,
            'password': password,
            'username': username,
            'is_profile_update': true, // Flag to indicate this is profile update flow
          },
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Registration failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _validateInput(String username, String email, String password) {
    if (username.isEmpty) {
      _usernameController.text = '';
      _showFieldError(_usernameController, 'Username is required');
      return false;
    }

    if (username.length < 3) {
      _showFieldError(_usernameController, 'Username must be at least 3 characters');
      return false;
    }

    if (email.isEmpty) {
      _emailController.text = '';
      _showFieldError(_emailController, 'Email is required');
      return false;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showFieldError(_emailController, 'Enter a valid email');
      return false;
    }

    if (password.isEmpty) {
      _passwordController.text = '';
      _showFieldError(_passwordController, 'Password is required');
      return false;
    }

    if (password.length < 6) {
      _showFieldError(_passwordController, 'Password must be at least 6 characters');
      return false;
    }

    if (!_rememberMe) {
      _showError('Please accept Remember Me to continue');
      return false;
    }

    return true;
  }

  void _showFieldError(TextEditingController controller, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
    controller.text = '';
    FocusScope.of(context).requestFocus(FocusNode()); // Request focus
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme),
      body: _buildBody(theme),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      systemOverlayStyle: theme.brightness == Brightness.dark 
        ? SystemUiOverlayStyle.light 
        : SystemUiOverlayStyle.dark,
    );
  }

  Widget _buildBody(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildLogo(theme),
            const SizedBox(height: 48),
            _buildTitle(theme),
            const SizedBox(height: 12),
            _buildUsernameField(theme),
            const SizedBox(height: 12),
            _buildEmailField(theme),
            const SizedBox(height: 12),
            _buildPasswordField(theme),
            const SizedBox(height: 20),
            _buildRememberMeSection(theme),
            const SizedBox(height: 24),
            _buildSignUpButton(theme),
            const SizedBox(height: 32),
            _buildSignInLink(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 24, bottom: 16),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: 133,
        height: 115,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback logo if image not found
          return Container(
            width: 133,
            height: 115,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.person_add,
              size: 60,
              color: theme.colorScheme.primary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Text(
      'Create New Account',
      textAlign: TextAlign.center,
      style: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildUsernameField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _usernameController,
        decoration: InputDecoration(
          hintText: 'Enter username',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withValues(alpha: 0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
      ),
    );
  }

  Widget _buildEmailField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _emailController,
        decoration: InputDecoration(
          hintText: 'Enter email',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withValues(alpha: 0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
      ),
    );
  }

  Widget _buildPasswordField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _passwordController,
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withValues(alpha: 0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        obscureText: true,
        textInputAction: TextInputAction.done,
        onEditingComplete: () => _handleSignUp(),
      ),
    );
  }

  Widget _buildRememberMeSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _rememberMe = !_rememberMe;
              });
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _rememberMe ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _rememberMe
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _rememberMe = !_rememberMe;
              });
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
  }

  Widget _buildSignUpButton(ThemeData theme) {
    return SizedBox(
      width: 262,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          elevation: 0,
          disabledBackgroundColor: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Sign up',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildSignInLink(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account?',
          style: GoogleFonts.poppins(
            fontSize: 9.68,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.normal,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(context, AppConstants.loginRoute);
          },
          child: Text(
            ' Sign In',
            style: GoogleFonts.poppins(
              fontSize: 9.68,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}