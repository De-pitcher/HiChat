import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart' as app_user;
import 'api_service.dart';

/// Service class for handling Google Sign-In authentication
class GoogleSignInService {
  static final GoogleSignInService _instance = GoogleSignInService._internal();
  factory GoogleSignInService() => _instance;
  GoogleSignInService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
  );

  final ApiService _apiService = ApiService();

  /// Sign in with Google
  /// Returns the authenticated user or null if sign-in was cancelled
  Future<GoogleSignInResult?> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      // Trigger the authentication flow
      googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        debugPrint('Google Sign-In was cancelled by user');
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      debugPrint('=== GOOGLE SIGN-IN SUCCESS (Firebase-Independent) ===');
      debugPrint('Email: ${googleUser.email}');
      debugPrint('Display Name: ${googleUser.displayName}');
      debugPrint('Photo URL: ${googleUser.photoUrl}');
      debugPrint('ID: ${googleUser.id}');
      debugPrint('Access Token Available: ${googleAuth.accessToken != null}');
      debugPrint('ID Token Available: ${googleAuth.idToken != null}');
      debugPrint('====================================================');

      // Validate that we have the required tokens
      if (googleAuth.idToken == null) {
        throw Exception('Google ID token is null - authentication failed');
      }

      // Use Google ID token directly (bypassing Firebase Auth)
      final googleIdToken = googleAuth.idToken!;

      debugPrint('Using Google ID token directly for backend authentication');

      // Create the request using Google ID token instead of Firebase token
      final googleSignInRequest = app_user.GoogleSignInRequest(
        firebaseIdToken: googleIdToken, // Using Google ID token directly
        email: googleUser.email,
        displayName: googleUser.displayName ?? '',
        photoUrl: googleUser.photoUrl,
        googleId: googleUser.id,
      );

      // Call your backend API to authenticate/register the user
      final googleSignInResponse = await _apiService.googleSignIn(googleSignInRequest);

      return GoogleSignInResult(
        user: googleSignInResponse.user,
        isNewUser: googleSignInResponse.isNew,
      );

    } catch (e, stackTrace) {
      debugPrint('Google Sign-In error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Logout to clear cached credentials on any error
      await _logoutOnError();
      
      rethrow;
    }
  }

  /// Internal method to logout when errors occur
  /// This prevents cached user sessions from causing issues
  Future<void> _logoutOnError() async {
    try {
      debugPrint('Performing logout due to sign-in error...');
      await _googleSignIn.signOut().catchError((e) {
        debugPrint('Error during Google signOut: $e');
        return null;
      });
      debugPrint('Logout completed after error');
    } catch (e) {
      debugPrint('Error during logout: $e');
      // Don't rethrow here as we're already handling an error
    }
  }

  /// Sign out from Google (Firebase-independent)
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      debugPrint('Google Sign-Out successful (Firebase-independent)');
    } catch (e) {
      debugPrint('Google Sign-Out error: $e');
      rethrow;
    }
  }

  /// Check if user is currently signed in with Google
  bool get isSignedIn => _googleSignIn.currentUser != null;

  /// Get current Google user
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Disconnect Google account (revoke access)
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      debugPrint('Google account disconnected (Firebase-independent)');
    } catch (e) {
      debugPrint('Google disconnect error: $e');
      rethrow;
    }
  }

  /// Complete logout including Google Sign-Out (Firebase-independent)
  /// This is a comprehensive logout method that can be called independently
  Future<void> performCompleteLogout() async {
    try {
      debugPrint('GoogleSignInService: Performing complete logout (Firebase-independent)...');
      
      // Sign out from Google only
      await signOut();
      
      debugPrint('GoogleSignInService: Complete logout successful (Firebase-independent)');
    } catch (e) {
      debugPrint('GoogleSignInService: Error during complete logout: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _apiService.dispose();
  }
}

/// Result model for Google Sign-In operation
class GoogleSignInResult {
  final app_user.User user;
  final bool isNewUser;

  const GoogleSignInResult({
    required this.user,
    required this.isNewUser,
  });

  @override
  String toString() {
    return 'GoogleSignInResult(user: ${user.username}, isNewUser: $isNewUser)';
  }
}