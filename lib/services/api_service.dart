import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'api_exceptions.dart';

/// Service class for handling API calls to the ChatCorner backend
class ApiService {
  // Production backend URL
  static const String _baseUrl = 'https://chatcornerbackend-production.up.railway.app/api';
  static const Duration _timeoutDuration = Duration(seconds: 30);
  
  final http.Client _client;
  
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Headers for API requests
  Map<String, String> get _defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Headers with authorization token
  Map<String, String> _authHeaders(String token) => {
    ..._defaultHeaders,
    'Authorization': 'Bearer $token',
  };

  /// Login user with email and password
  /// 
  /// Throws [ApiException] on error
  /// Returns [LoginResponse] on success
  Future<LoginResponse> login(LoginRequest request) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/login/');
      final requestBody = json.encode(request.toJson());
      
      // Log request details
      debugPrint('=== API REQUEST DETAILS ===');
      debugPrint('URL: $uri');
      debugPrint('Method: POST');
      debugPrint('Headers: $_defaultHeaders');
      debugPrint('Request Body: $requestBody');
      debugPrint('===========================');
      
      final response = await _client
          .post(
            uri,
            headers: _defaultHeaders,
            body: requestBody,
          )
          .timeout(_timeoutDuration);

      return _handleLoginResponse(response);
    } on SocketException catch (e) {
      debugPrint('Socket Exception during login: $e');
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      debugPrint('HTTP Exception during login: $e');
      throw NetworkException('Network error: ${e.message}');
    } on FormatException catch (e) {
      debugPrint('Format Exception during login: $e');
      throw ApiException('Invalid response format: ${e.message}');
    } on ApiException {
      // Re-throw API exceptions without wrapping them
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during login: $e');
      debugPrint('Stack trace: $stackTrace');
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Handle login response and parse or throw appropriate exceptions
  LoginResponse _handleLoginResponse(http.Response response) {
    // Log all response details for debugging
    debugPrint('=== API RESPONSE DETAILS ===');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Headers: ${response.headers}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('Content Length: ${response.contentLength}');
    debugPrint('============================');
    
    switch (response.statusCode) {
      case 200:
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          debugPrint('Successfully parsed login response: $jsonData');
          return LoginResponse.fromJson(jsonData);
        } catch (e) {
          debugPrint('Failed to parse successful response: $e');
          throw ApiException('Failed to parse login response: $e');
        }
      
      case 400:
        final errorData = _parseErrorResponse(response);
        debugPrint('Validation error data: $errorData');
        throw ValidationException(
          errorData['message'] ?? 'Invalid login credentials',
          validationErrors: errorData['errors'],
          statusCode: 400,
        );
      
      case 401:
        debugPrint('Authentication failed - Invalid credentials');
        throw const AuthenticationException('Invalid email or password');
      
      case 404:
        debugPrint('Login endpoint not found');
        throw const ApiException('Login endpoint not found', statusCode: 404);
      
      case 500:
        debugPrint('Internal server error occurred');
        throw const ServerException('Internal server error', statusCode: 500);
      
      default:
        debugPrint('Unexpected status code: ${response.statusCode}');
        throw ApiException(
          'Login failed with status ${response.statusCode}',
          statusCode: response.statusCode,
        );
    }
  }

  /// Parse error response body
  Map<String, dynamic> _parseErrorResponse(http.Response response) {
    try {
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'message': 'Server error occurred',
        'errors': null,
      };
    }
  }

  /// Handle Google Sign-In response
  GoogleSignInResponse _handleGoogleSignInResponse(http.Response response) {
    // Log all response details for debugging
    debugPrint('=== GOOGLE SIGNIN RESPONSE DETAILS ===');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Headers: ${response.headers}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('Content Length: ${response.contentLength}');
    debugPrint('======================================');
    
    switch (response.statusCode) {
      case 200:
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          debugPrint('Successfully parsed Google Sign-In response: $jsonData');
          return GoogleSignInResponse.fromJson(jsonData);
        } catch (e) {
          debugPrint('Failed to parse successful response: $e');
          throw ApiException('Failed to parse Google Sign-In response: $e');
        }
      
      case 400:
        final errorData = _parseErrorResponse(response);
        debugPrint('Google Sign-In validation error: $errorData');
        throw ValidationException(
          errorData['message'] ?? 'Invalid Google Sign-In data',
          validationErrors: errorData['errors'],
          statusCode: 400,
        );
      
      case 401:
        debugPrint('Google Sign-In authentication failed');
        throw const AuthenticationException('Invalid Firebase token');
      
      case 500:
        debugPrint('Google Sign-In server error occurred');
        throw const ServerException('Google sign-in failed: server error', statusCode: 500);
      
      default:
        debugPrint('Unexpected status code: ${response.statusCode}');
        throw ApiException(
          'Google Sign-In failed with status ${response.statusCode}',
          statusCode: response.statusCode,
        );
    }
  }

  /// Get user profile (authenticated endpoint example)
  Future<User> getUserProfile(String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/profile/');
      
      final response = await _client
          .get(
            uri,
            headers: _authHeaders(token),
          )
          .timeout(_timeoutDuration);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return User.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw const AuthenticationException('Token expired or invalid');
      } else {
        throw ApiException(
          'Failed to get user profile',
          statusCode: response.statusCode,
        );
      }
    } on SocketException {
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Logout user (if endpoint exists)
  Future<void> logout(String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/logout/');
      
      final response = await _client
          .post(
            uri,
            headers: _authHeaders(token),
          )
          .timeout(_timeoutDuration);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw ApiException(
          'Logout failed',
          statusCode: response.statusCode,
        );
      }
    } on SocketException {
      throw const NetworkException('No internet connection available');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Logout error: $e');
    }
  }

  /// Login user with phone number and password
  /// 
  /// Throws [ApiException] on error
  /// Returns [LoginResponse] on success
  Future<LoginResponse> phoneLogin(PhoneLoginRequest request) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/phone-login/');
      final requestBody = json.encode(request.toJson());
      
      // Log request details
      debugPrint('=== PHONE LOGIN REQUEST ===');
      debugPrint('URL: $uri');
      debugPrint('Method: POST');
      debugPrint('Headers: $_defaultHeaders');
      debugPrint('Request Body: $requestBody');
      debugPrint('===========================');
      
      final response = await _client
          .post(
            uri,
            headers: _defaultHeaders,
            body: requestBody,
          )
          .timeout(_timeoutDuration);

      return _handleLoginResponse(response);
    } on SocketException catch (e) {
      debugPrint('Socket Exception during phone login: $e');
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      debugPrint('HTTP Exception during phone login: $e');
      throw NetworkException('Network error: ${e.message}');
    } on FormatException catch (e) {
      debugPrint('Format Exception during phone login: $e');
      throw ApiException('Invalid response format: ${e.message}');
    } on ApiException {
      // Re-throw API exceptions without wrapping them
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during phone login: $e');
      debugPrint('Stack trace: $stackTrace');
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Create new user account with profile information
  /// 
  /// Throws [ApiException] on error
  /// Returns [SignupResponse] on success
  Future<SignupResponse> signupUser(SignupRequest request) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/signup/');
      final requestBody = json.encode(request.toJson());
      
      // Log request details
      debugPrint('=== SIGNUP REQUEST ===');
      debugPrint('URL: $uri');
      debugPrint('Method: POST');
      debugPrint('Headers: $_defaultHeaders');
      debugPrint('Request Body Length: ${requestBody.length} characters');
      debugPrint('Has Phone: ${request.phoneNumber != null}');
      debugPrint('Has Email: ${request.email != null}');
      debugPrint('======================');
      
      final response = await _client
          .post(
            uri,
            headers: _defaultHeaders,
            body: requestBody,
          )
          .timeout(_timeoutDuration);

      return _handleSignupResponse(response);
    } on SocketException catch (e) {
      debugPrint('Socket Exception during signup: $e');
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      debugPrint('HTTP Exception during signup: $e');
      throw NetworkException('Network error: ${e.message}');
    } on FormatException catch (e) {
      debugPrint('Format Exception during signup: $e');
      throw ApiException('Invalid response format: ${e.message}');
    } on ApiException {
      // Re-throw API exceptions without wrapping them
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during signup: $e');
      debugPrint('Stack trace: $stackTrace');
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Handle signup response and parse or throw appropriate exceptions
  SignupResponse _handleSignupResponse(http.Response response) {
    // Log all response details for debugging
    debugPrint('=== SIGNUP RESPONSE ===');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Headers: ${response.headers}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('=======================');
    
    switch (response.statusCode) {
      case 201:
      case 200:
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          debugPrint('Successfully parsed signup response: $jsonData');
          return SignupResponse.fromJson(jsonData);
        } catch (e) {
          debugPrint('Failed to parse successful signup response: $e');
          throw ApiException('Failed to parse signup response: $e');
        }
      
      case 400:
        final errorData = _parseErrorResponse(response);
        debugPrint('Signup validation error: $errorData');
        throw ValidationException(
          errorData['message'] ?? 'Invalid signup data',
          validationErrors: errorData['errors'],
          statusCode: 400,
        );
      
      case 409:
        debugPrint('User already exists');
        throw const ValidationException('User with this email or phone number already exists', statusCode: 409);
      
      case 404:
        debugPrint('Signup endpoint not found');
        throw const ApiException('Signup endpoint not found', statusCode: 404);
      
      case 500:
        debugPrint('Internal server error during signup');
        throw const ServerException('Internal server error', statusCode: 500);
      
      default:
        debugPrint('Unexpected status code during signup: ${response.statusCode}');
        throw ApiException(
          'Signup failed with status ${response.statusCode}',
          statusCode: response.statusCode,
        );
    }
  }

  /// Update user profile information
  /// 
  /// Throws [ApiException] on error
  /// Returns [User] on success
  Future<User> updateUserProfile(String token, ProfileUpdateRequest request) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/profile/');
      final requestBody = json.encode(request.toJson());
      
      // Log request details
      debugPrint('=== PROFILE UPDATE REQUEST ===');
      debugPrint('URL: $uri');
      debugPrint('Method: PUT');
      debugPrint('Headers: ${_authHeaders(token)}');
      debugPrint('Request Body Length: ${requestBody.length} characters');
      debugPrint('==============================');
      
      final response = await _client
          .put(
            uri,
            headers: _authHeaders(token),
            body: requestBody,
          )
          .timeout(_timeoutDuration);

      return _handleProfileUpdateResponse(response);
    } on SocketException catch (e) {
      debugPrint('Socket Exception during profile update: $e');
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      debugPrint('HTTP Exception during profile update: $e');
      throw NetworkException('Network error: ${e.message}');
    } on FormatException catch (e) {
      debugPrint('Format Exception during profile update: $e');
      throw ApiException('Invalid response format: ${e.message}');
    } on ApiException {
      // Re-throw API exceptions without wrapping them
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during profile update: $e');
      debugPrint('Stack trace: $stackTrace');
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Handle profile update response and parse or throw appropriate exceptions
  User _handleProfileUpdateResponse(http.Response response) {
    // Log all response details for debugging
    debugPrint('=== PROFILE UPDATE RESPONSE ===');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Headers: ${response.headers}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('===============================');
    
    switch (response.statusCode) {
      case 200:
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          debugPrint('Successfully parsed profile update response: $jsonData');
          return User.fromJson(jsonData);
        } catch (e) {
          debugPrint('Failed to parse successful profile update response: $e');
          throw ApiException('Failed to parse profile update response: $e');
        }
      
      case 400:
        final errorData = _parseErrorResponse(response);
        debugPrint('Profile update validation error: $errorData');
        throw ValidationException(
          errorData['message'] ?? 'Invalid profile data',
          validationErrors: errorData['errors'],
          statusCode: 400,
        );
      
      case 401:
        debugPrint('Profile update authentication failed');
        throw const AuthenticationException('Invalid or expired token');
      
      case 404:
        debugPrint('Profile update endpoint not found');
        throw const ApiException('Profile update endpoint not found', statusCode: 404);
      
      case 500:
        debugPrint('Internal server error during profile update');
        throw const ServerException('Internal server error', statusCode: 500);
      
      default:
        debugPrint('Unexpected status code during profile update: ${response.statusCode}');
        throw ApiException(
          'Profile update failed with status ${response.statusCode}',
          statusCode: response.statusCode,
        );
    }
  }

  /// Google Sign-In authentication
  /// 
  /// Throws [ApiException] on error
  /// Returns [GoogleSignInResponse] on success
  Future<GoogleSignInResponse> googleSignIn(GoogleSignInRequest request) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/google-signin/');
      final requestBody = json.encode(request.toJson());
      
      // Log request details
      debugPrint('=== GOOGLE SIGNIN REQUEST ===');
      debugPrint('URL: $uri');
      debugPrint('Method: POST');
      debugPrint('Headers: $_defaultHeaders');
      debugPrint('Email: ${request.email}');
      debugPrint('Display Name: ${request.displayName}');
      debugPrint('Google ID: ${request.googleId}');
      debugPrint('Firebase Token: ${request.firebaseIdToken.substring(0, 20)}...');
      debugPrint('=============================');
      
      final response = await _client
          .post(
            uri,
            headers: _defaultHeaders,
            body: requestBody,
          )
          .timeout(_timeoutDuration);

      return _handleGoogleSignInResponse(response);
    } on SocketException catch (e) {
      debugPrint('Socket Exception during Google sign-in: $e');
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      debugPrint('HTTP Exception during Google sign-in: $e');
      throw NetworkException('Network error: ${e.message}');
    } on FormatException catch (e) {
      debugPrint('Format Exception during Google sign-in: $e');
      throw ApiException('Invalid response format: ${e.message}');
    } on ApiException {
      // Re-throw API exceptions without wrapping them
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during Google sign-in: $e');
      debugPrint('Stack trace: $stackTrace');
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Check if phone number exists in the system
  /// 
  /// Throws [ApiException] on error
  /// Returns [PhoneCheckResponse] on success
  Future<PhoneCheckResponse> checkPhoneNumber(String phoneNumber) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/check-phone/?phone_number=$phoneNumber');
      
      // Log request details
      debugPrint('=== PHONE CHECK REQUEST ===');
      debugPrint('URL: $uri');
      debugPrint('Method: GET');
      debugPrint('Phone Number: $phoneNumber');
      debugPrint('==========================');
      
      final response = await _client
          .get(
            uri,
            headers: _defaultHeaders,
          )
          .timeout(_timeoutDuration);

      return _handlePhoneCheckResponse(response);
    } on SocketException catch (e) {
      debugPrint('Socket Exception during phone check: $e');
      throw const NetworkException('No internet connection available');
    } on HttpException catch (e) {
      debugPrint('HTTP Exception during phone check: $e');
      throw NetworkException('Network error: ${e.message}');
    } on FormatException catch (e) {
      debugPrint('Format Exception during phone check: $e');
      throw ApiException('Invalid response format: ${e.message}');
    } on ApiException {
      // Re-throw API exceptions without wrapping them
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during phone check: $e');
      debugPrint('Stack trace: $stackTrace');
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Handle phone check response and parse or throw appropriate exceptions
  PhoneCheckResponse _handlePhoneCheckResponse(http.Response response) {
    // Log all response details for debugging
    debugPrint('=== PHONE CHECK RESPONSE ===');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Headers: ${response.headers}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('============================');
    
    switch (response.statusCode) {
      case 200:
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          debugPrint('Successfully parsed phone check response: $jsonData');
          return PhoneCheckResponse.fromJson(jsonData);
        } catch (e) {
          debugPrint('Failed to parse successful phone check response: $e');
          throw ApiException('Failed to parse phone check response: $e');
        }
      
      case 400:
        final errorData = _parseErrorResponse(response);
        debugPrint('Phone check validation error: $errorData');
        throw ValidationException(
          errorData['message'] ?? 'Invalid phone number format',
          validationErrors: errorData['errors'],
          statusCode: 400,
        );
      
      case 404:
        debugPrint('Phone check endpoint not found');
        throw const ApiException('Phone check endpoint not found', statusCode: 404);
      
      case 500:
        debugPrint('Internal server error during phone check');
        throw const ServerException('Internal server error', statusCode: 500);
      
      default:
        debugPrint('Unexpected status code during phone check: ${response.statusCode}');
        throw ApiException(
          'Phone check failed with status ${response.statusCode}',
          statusCode: response.statusCode,
        );
    }
  }

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}