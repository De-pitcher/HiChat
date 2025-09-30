import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_exceptions.dart';

/// Service class for handling Firebase Phone Authentication
class FirebasePhoneAuthService {
  static final FirebasePhoneAuthService _instance = FirebasePhoneAuthService._internal();
  factory FirebasePhoneAuthService() => _instance;
  FirebasePhoneAuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  
  // Store the verification data
  String? _verificationId;
  int? _resendToken;
  
  /// Send OTP to the provided phone number
  /// Returns true if OTP was sent successfully
  Future<bool> sendOTP({
    required String phoneNumber,
    required Function(String message) onError,
    required Function(String message) onSuccess,
    Function(String verificationId)? onCodeSent,
    Function(PhoneAuthCredential credential)? onAutoVerificationCompleted,
  }) async {
    try {
      debugPrint('FirebasePhoneAuth: Sending OTP to $phoneNumber');
      debugPrint('FirebasePhoneAuth: Project ID: ${_firebaseAuth.app.options.projectId}');
      debugPrint('FirebasePhoneAuth: Project Number: ${_firebaseAuth.app.options.messagingSenderId}');
      debugPrint('FirebasePhoneAuth: App ID: ${_firebaseAuth.app.options.appId}');
      debugPrint('FirebasePhoneAuth: Current user: ${_firebaseAuth.currentUser?.uid ?? "None"}');
      
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('FirebasePhoneAuth: Auto verification completed');
          if (onAutoVerificationCompleted != null) {
            onAutoVerificationCompleted(credential);
          } else {
            // Auto-sign in if no custom handler provided
            await _signInWithCredential(credential);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('FirebasePhoneAuth: Verification failed: ${e.message}');
          String errorMessage = _getErrorMessage(e);
          onError(errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('FirebasePhoneAuth: Code sent successfully');
          _verificationId = verificationId;
          _resendToken = resendToken;
          
          onSuccess('OTP sent successfully to $phoneNumber');
          
          if (onCodeSent != null) {
            onCodeSent(verificationId);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('FirebasePhoneAuth: Auto retrieval timeout');
          // This is called when the auto-retrieval timeout expires
          // Usually happens after 30 seconds on Android
        },
        // Don't use forceResendingToken on initial send (it should be null)
        forceResendingToken: null,
      );
      
      return true;
    } catch (e) {
      debugPrint('FirebasePhoneAuth: Error sending OTP: $e');
      onError('Failed to send OTP: ${e.toString()}');
      return false;
    }
  }
  
  /// Verify the OTP code entered by user
  /// Returns PhoneAuthCredential if successful
  Future<PhoneAuthCredential?> verifyOTP(String otpCode) async {
    try {
      if (_verificationId == null) {
        throw const ApiException('Verification ID not found. Please resend OTP.');
      }
      
      debugPrint('FirebasePhoneAuth: Verifying OTP code');
      
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otpCode,
      );
      
      debugPrint('FirebasePhoneAuth: OTP verification successful');
      return credential;
      
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebasePhoneAuth: OTP verification failed: ${e.message}');
      throw ApiException(_getErrorMessage(e));
    } catch (e) {
      debugPrint('FirebasePhoneAuth: Error verifying OTP: $e');
      throw ApiException('Failed to verify OTP: ${e.toString()}');
    }
  }
  
  /// Sign in with phone credential
  /// Returns UserCredential if successful
  Future<UserCredential> signInWithCredential(PhoneAuthCredential credential) async {
    try {
      debugPrint('FirebasePhoneAuth: Signing in with phone credential');
      
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      
      debugPrint('FirebasePhoneAuth: Phone sign-in successful');
      return userCredential;
      
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebasePhoneAuth: Sign-in failed: ${e.message}');
      throw ApiException(_getErrorMessage(e));
    } catch (e) {
      debugPrint('FirebasePhoneAuth: Error signing in: $e');
      throw ApiException('Failed to sign in: ${e.toString()}');
    }
  }
  
  /// Internal method to sign in with credential
  Future<UserCredential> _signInWithCredential(PhoneAuthCredential credential) async {
    return await signInWithCredential(credential);
  }
  
  /// Resend OTP with the stored resend token
  Future<bool> resendOTP({
    required String phoneNumber,
    required Function(String message) onError,
    required Function(String message) onSuccess,
    Function(String verificationId)? onCodeSent,
  }) async {
    try {
      debugPrint('FirebasePhoneAuth: Resending OTP to $phoneNumber');
      debugPrint('FirebasePhoneAuth: Using resend token: ${_resendToken != null ? "Available" : "Not Available"}');
      
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('FirebasePhoneAuth: Auto verification completed on resend');
          // Auto-sign in
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('FirebasePhoneAuth: Resend verification failed: ${e.message}');
          String errorMessage = _getErrorMessage(e);
          onError(errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('FirebasePhoneAuth: Code resent successfully');
          _verificationId = verificationId;
          _resendToken = resendToken;
          
          onSuccess('OTP resent successfully to $phoneNumber');
          
          if (onCodeSent != null) {
            onCodeSent(verificationId);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('FirebasePhoneAuth: Auto retrieval timeout on resend');
        },
        forceResendingToken: _resendToken, // Use stored resend token
      );
      
      return true;
    } catch (e) {
      debugPrint('FirebasePhoneAuth: Error resending OTP: $e');
      
      // If resend with token fails, try a fresh send as fallback
      if (_resendToken != null) {
        debugPrint('FirebasePhoneAuth: Resend with token failed, trying fresh send...');
        return await sendOTP(
          phoneNumber: phoneNumber,
          onError: onError,
          onSuccess: onSuccess,
          onCodeSent: onCodeSent,
        );
      }
      
      onError('Failed to resend OTP: ${e.toString()}');
      return false;
    }
  }
  
  /// Get user-friendly error messages
  String _getErrorMessage(FirebaseAuthException e) {
    // Log the full error details for debugging
    debugPrint('FirebaseAuth Error Code: ${e.code}');
    debugPrint('FirebaseAuth Error Message: ${e.message}');
    
    switch (e.code) {
      case 'invalid-phone-number':
        return 'The phone number format is invalid.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'invalid-verification-code':
        return 'The verification code is invalid.';
      case 'invalid-verification-id':
        return 'The verification session has expired. Please request a new code.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'credential-already-in-use':
        return 'This phone number is already associated with another account.';
      case 'operation-not-allowed':
        return 'Phone authentication is not enabled in Firebase Console.';
      case 'missing-verification-code':
        return 'Please enter the verification code.';
      case 'missing-verification-id':
        return 'Verification ID is missing. Please request a new code.';
      case 'session-expired':
        return 'The verification session has expired. Please request a new code.';
      // Handle billing-related errors specifically
      case 'billing-not-enabled':
      case 'BILLING_NOT_ENABLED':
        return 'Phone Authentication billing is not enabled. Please enable Blaze plan in Firebase Console.';
      case 'internal-error':
        // Check if the message contains billing information
        if (e.message?.contains('BILLING_NOT_ENABLED') == true) {
          return 'Phone Authentication requires billing to be enabled. Please upgrade to Blaze plan in Firebase Console.';
        }
        return 'An internal error occurred. Please try again.';
      default:
        // For unknown errors, show the Firebase message but make it user-friendly
        if (e.message?.contains('BILLING_NOT_ENABLED') == true) {
          return 'Phone Authentication billing is not enabled. Please enable Blaze plan in Firebase Console.';
        }
        return e.message ?? 'An unknown error occurred.';
    }
  }
  
  /// Get current verification ID (for debugging)
  String? get verificationId => _verificationId;
  
  /// Clear stored verification data
  void clearVerificationData() {
    _verificationId = null;
    _resendToken = null;
    debugPrint('FirebasePhoneAuth: Verification data cleared');
  }
  
  /// Sign out from Firebase
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
      clearVerificationData();
      debugPrint('FirebasePhoneAuth: Sign out successful');
    } catch (e) {
      debugPrint('FirebasePhoneAuth: Error signing out: $e');
      throw ApiException('Failed to sign out: ${e.toString()}');
    }
  }
  
  /// Get current Firebase user
  User? get currentUser => _firebaseAuth.currentUser;
  
  /// Check if user is signed in
  bool get isSignedIn => _firebaseAuth.currentUser != null;
}