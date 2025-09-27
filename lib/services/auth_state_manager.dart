import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'api_exceptions.dart';
import 'google_signin_service.dart';

/// Manages authentication state throughout the app
/// Handles login, logout, remember me, and auto-login functionality
class AuthStateManager extends ChangeNotifier {
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyCurrentUser = 'current_user';
  static const String _keyRememberMe = 'remember_me';
  static const String _keyRememberedEmail = 'remembered_email';
  static const String _keyRememberedPassword = 'remembered_password';

  User? _currentUser;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _rememberMe = false;
  String _rememberedEmail = '';
  String _rememberedPassword = '';

  final ApiService _apiService = ApiService();
  final GoogleSignInService _googleSignInService = GoogleSignInService();

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get rememberMe => _rememberMe;
  String get rememberedEmail => _rememberedEmail;
  String get rememberedPassword => _rememberedPassword;

  /// Initialize auth state from stored preferences
  Future<void> initialize() async {
    _setLoading(true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if user was logged in
      _isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
      
      // Load remember me settings
      _rememberMe = prefs.getBool(_keyRememberMe) ?? false;
      _rememberedEmail = prefs.getString(_keyRememberedEmail) ?? '';
      _rememberedPassword = prefs.getString(_keyRememberedPassword) ?? '';
      
      // Load current user if logged in
      if (_isLoggedIn) {
        final userJson = prefs.getString(_keyCurrentUser);
        if (userJson != null) {
          _currentUser = User.fromStoredJson(userJson);
          debugPrint('AuthStateManager: Restored user session for ${_currentUser?.email}');
        } else {
          // User data not found, reset login state
          _isLoggedIn = false;
          await _clearStoredAuth();
        }
      }
      
      // Remember me only affects form pre-filling, not auto-login
      // Users must manually click "Sign in" even if remember me is enabled
      
    } catch (e) {
      debugPrint('AuthStateManager: Error initializing auth state: $e');
      await _clearStoredAuth();
    } finally {
      _setLoading(false);
    }
  }

  /// Login with email and password
  Future<LoginResult> login(String email, String password, {bool rememberMe = false}) async {
    _setLoading(true);
    
    try {
      debugPrint('AuthStateManager: Attempting login for $email');
      
      final loginRequest = LoginRequest(email: email, password: password);
      final loginResponse = await _apiService.login(loginRequest);
      
      // Update state
      _currentUser = loginResponse.user;
      _isLoggedIn = true;
      _rememberMe = rememberMe;
      
      // Save to preferences
      await _saveAuthState();
      
      if (rememberMe) {
        await _saveRememberMeCredentials(email, password);
      } else {
        await _clearRememberMeCredentials();
      }
      
      debugPrint('AuthStateManager: Login successful for ${_currentUser?.email}');
      notifyListeners();
      
      return LoginResult.success();
      
    } on ValidationException catch (e) {
      debugPrint('AuthStateManager: Login validation error: ${e.message}');
      return LoginResult.failure(e.message, LoginErrorType.validation);
    } on AuthenticationException catch (e) {
      debugPrint('AuthStateManager: Login authentication error: ${e.message}');
      return LoginResult.failure(e.message, LoginErrorType.authentication);
    } on NetworkException catch (e) {
      debugPrint('AuthStateManager: Login network error: ${e.message}');
      return LoginResult.failure(e.message, LoginErrorType.network);
    } on ServerException catch (e) {
      debugPrint('AuthStateManager: Login server error: ${e.message}');
      return LoginResult.failure(e.message, LoginErrorType.server);
    } catch (e) {
      debugPrint('AuthStateManager: Login unexpected error: $e');
      return LoginResult.failure('An unexpected error occurred. Please try again.', LoginErrorType.unknown);
    } finally {
      _setLoading(false);
    }
  }

  /// Logout user and clear session data
  Future<void> logout() async {
    debugPrint('AuthStateManager: Logging out user ${_currentUser?.email}');
    
    try {
      // If user has a token, try to logout from backend
      if (_currentUser?.token != null) {
        try {
          debugPrint('AuthStateManager: Calling backend logout API');
          await _apiService.logout(_currentUser!.token!);
          debugPrint('AuthStateManager: Backend logout successful');
        } catch (e) {
          debugPrint('AuthStateManager: Backend logout failed (continuing with local logout): $e');
          // Continue with local logout even if backend fails
        }
      }
      
      // Always sign out from Google and Firebase (regardless of how user logged in)
      try {
        debugPrint('AuthStateManager: Performing Google & Firebase sign out');
        await _googleSignInService.signOut();
        debugPrint('AuthStateManager: Google & Firebase sign out successful');
      } catch (e) {
        debugPrint('AuthStateManager: Google/Firebase sign out failed (continuing): $e');
        // Continue with local logout even if Google sign out fails
      }
      
    } catch (e) {
      debugPrint('AuthStateManager: Error during logout process: $e');
      // Continue with local cleanup even if remote logout fails
    }
    
    // Always clear local session data
    _currentUser = null;
    _isLoggedIn = false;
    
    // Clear only the user session data (login state and user data)
    await _clearStoredAuth();
    
    // Keep remember me credentials intact - they should persist
    // This allows users to have their email/password pre-filled next time
    // but prevents auto-login until they manually log in again
    
    debugPrint('AuthStateManager: Logout complete - session cleared, remember me preserved');
    notifyListeners();
  }

  /// Update remember me preference
  Future<void> updateRememberMe(bool remember) async {
    _rememberMe = remember;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberMe, remember);
    
    if (!remember) {
      await _clearRememberMeCredentials();
    }
    
    notifyListeners();
  }

  /// Check if user session is still valid (optional future enhancement)
  Future<bool> validateSession() async {
    if (!_isLoggedIn || _currentUser?.token == null) {
      return false;
    }
    
    try {
      // You can implement token validation with the API here
      // For now, assume valid if we have a token
      return true;
    } catch (e) {
      debugPrint('AuthStateManager: Session validation failed: $e');
      await logout();
      return false;
    }
  }

  /// Handle Google Sign-In result and update auth state
  Future<void> handleGoogleSignInResult(User user) async {
    debugPrint('AuthStateManager: Handling Google Sign-In result for ${user.email}');
    await _updateAuthState(user, false); // Google sign-in doesn't use remember me
  }

  /// Handle any successful login and update auth state
  Future<void> handleSuccessfulLogin(User user, {bool rememberMe = false}) async {
    debugPrint('AuthStateManager: Handling successful login for ${user.email}');
    await _updateAuthState(user, rememberMe);
  }

  /// Internal method to update authentication state
  Future<void> _updateAuthState(User user, bool rememberMe) async {
    _currentUser = user;
    _isLoggedIn = true;
    _rememberMe = rememberMe;
    
    // Save to preferences
    await _saveAuthState();
    
    debugPrint('AuthStateManager: Auth state saved successfully for ${user.email}');
    notifyListeners();
  }

  // Private methods

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }



  Future<void> _saveAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, _isLoggedIn);
    await prefs.setBool(_keyRememberMe, _rememberMe);
    
    if (_currentUser != null) {
      await prefs.setString(_keyCurrentUser, _currentUser!.toStoredJson());
    }
  }

  Future<void> _saveRememberMeCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    _rememberedEmail = email;
    _rememberedPassword = password;
    
    await prefs.setString(_keyRememberedEmail, email);
    await prefs.setString(_keyRememberedPassword, password);
    
    debugPrint('AuthStateManager: Remember me credentials saved for $email');
  }

  Future<void> _clearRememberMeCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberedEmail = '';
    _rememberedPassword = '';
    _rememberMe = false;
    
    await prefs.remove(_keyRememberedEmail);
    await prefs.remove(_keyRememberedPassword);
    await prefs.remove(_keyRememberMe);
  }

  Future<void> _clearStoredAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyCurrentUser);
  }
}

/// Result of a login attempt
class LoginResult {
  final bool isSuccess;
  final String? errorMessage;
  final LoginErrorType? errorType;

  const LoginResult._({
    required this.isSuccess,
    this.errorMessage,
    this.errorType,
  });

  factory LoginResult.success() => const LoginResult._(isSuccess: true);
  
  factory LoginResult.failure(String message, LoginErrorType type) => 
    LoginResult._(isSuccess: false, errorMessage: message, errorType: type);
}

/// Types of login errors for different handling
enum LoginErrorType {
  validation,
  authentication, 
  network,
  server,
  unknown,
}