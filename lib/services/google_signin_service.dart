import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
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

      debugPrint('=== GOOGLE SIGN-IN SUCCESS ===');
      debugPrint('Email: ${googleUser.email}');
      debugPrint('Display Name: ${googleUser.displayName}');
      debugPrint('Photo URL: ${googleUser.photoUrl}');
      debugPrint('ID: ${googleUser.id}');
      debugPrint('Access Token: ${googleAuth.accessToken?.substring(0, 20)}...');
      debugPrint('ID Token: ${googleAuth.idToken?.substring(0, 20)}...');
      debugPrint('=============================');

      // Create a credential for Firebase Auth (if using Firebase)
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google user credential
      // Using a try-catch to handle potential Firebase Auth issues
      UserCredential? userCredential;
      String? firebaseIdToken;
      
      try {
        userCredential = await _firebaseAuth.signInWithCredential(credential);
        
        // Get the Firebase ID token for backend authentication
        if (userCredential.user != null) {
          firebaseIdToken = await userCredential.user!.getIdToken();
        }
        
        debugPrint('Firebase Auth successful');
      } catch (firebaseError) {
        debugPrint('Firebase Auth error: $firebaseError');
        debugPrint('Proceeding with Google ID token as fallback');
        
        // Use the Google ID token as fallback if Firebase auth fails
        firebaseIdToken = googleAuth.idToken;
      }

      // Create the request using available token data
      final googleSignInRequest = app_user.GoogleSignInRequest(
        firebaseIdToken: firebaseIdToken ?? googleAuth.idToken ?? '',
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
      await Future.wait([
        _googleSignIn.signOut().catchError((e) {
          debugPrint('Error during Google signOut: $e');
          return null;
        }),
        _firebaseAuth.signOut().catchError((e) {
          debugPrint('Error during Firebase signOut: $e');
          return null;
        }),
      ]);
      debugPrint('Logout completed after error');
    } catch (e) {
      debugPrint('Error during logout: $e');
      // Don't rethrow here as we're already handling an error
    }
  }

  /// Sign out from Google and Firebase
  Future<void> signOut() async {
    try {
      await Future.wait([
        _googleSignIn.signOut(),
        _firebaseAuth.signOut(),
      ]);
      debugPrint('Google Sign-Out successful');
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
      await _firebaseAuth.signOut();
      debugPrint('Google account disconnected');
    } catch (e) {
      debugPrint('Google disconnect error: $e');
      rethrow;
    }
  }

  /// Complete logout including Google Sign-Out and Firebase Sign-Out
  /// This is a comprehensive logout method that can be called independently
  Future<void> performCompleteLogout() async {
    try {
      debugPrint('GoogleSignInService: Performing complete logout...');
      
      // Sign out from Google and Firebase
      await signOut();
      
      debugPrint('GoogleSignInService: Complete logout successful');
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