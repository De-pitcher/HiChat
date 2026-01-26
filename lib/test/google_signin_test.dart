import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Simple test for Firebase-independent Google Sign-In
class GoogleSignInTest {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Test Google Sign-In without Firebase
  static Future<Map<String, dynamic>?> testGoogleSignIn() async {
    try {
      print('🧪 Testing Firebase-independent Google Sign-In...');
      
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('❌ User cancelled the sign-in');
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Check if we have the required tokens
      if (googleAuth.idToken == null) {
        print('❌ Google ID token is null - authentication failed');
        return null;
      }

      print('✅ Google Sign-In Success!');
      print('📧 Email: ${googleUser.email}');
      print('👤 Display Name: ${googleUser.displayName}');
      print('🖼️ Photo URL: ${googleUser.photoUrl}');
      print('🆔 Google ID: ${googleUser.id}');
      print('🔑 ID Token Available: ${googleAuth.idToken != null}');
      print('🔐 Access Token Available: ${googleAuth.accessToken != null}');

      return {
        'success': true,
        'email': googleUser.email,
        'displayName': googleUser.displayName,
        'photoUrl': googleUser.photoUrl,
        'googleId': googleUser.id,
        'idToken': googleAuth.idToken,
        'accessToken': googleAuth.accessToken,
      };

    } catch (e) {
      print('❌ Google Sign-In Test Failed: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Test sign out
  static Future<bool> testSignOut() async {
    try {
      print('🧪 Testing sign out...');
      await _googleSignIn.signOut();
      print('✅ Sign out successful');
      return true;
    } catch (e) {
      print('❌ Sign out failed: $e');
      return false;
    }
  }

  /// Check current sign-in status
  static bool isSignedIn() {
    final isSignedIn = _googleSignIn.currentUser != null;
    print('🔍 Current sign-in status: ${isSignedIn ? "Signed In" : "Signed Out"}');
    return isSignedIn;
  }
}