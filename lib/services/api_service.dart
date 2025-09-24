import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'api_exceptions.dart';

/// Service class for handling API calls to the ChatCorner backend
class ApiService {
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

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}