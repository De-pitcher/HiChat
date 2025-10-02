import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/user.dart';

/// User search result model matching the API response format
class UserSearchResult {
  final List<User> results;
  final int count;

  const UserSearchResult({
    required this.results,
    required this.count,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    developer.log(
      'Parsing UserSearchResult from JSON',
      name: 'UserSearchResult',
      error: {
        'jsonKeys': json.keys.toList(),
        'rawJson': json,
      },
      level: 800,
    );
    
    final List<dynamic> resultsJson = json['results'] ?? [];
    developer.log(
      'Extracted results array',
      name: 'UserSearchResult',
      error: {
        'resultsLength': resultsJson.length,
        'resultsType': resultsJson.runtimeType.toString(),
      },
      level: 800,
    );
    
    try {
      final List<User> users = resultsJson
          .map((userJson) {
            developer.log(
              'Parsing individual user',
              name: 'UserSearchResult',
              error: {
                'userJson': userJson,
                'userJsonType': userJson.runtimeType.toString(),
              },
              level: 800,
            );
            return User.fromJson(userJson as Map<String, dynamic>);
          })
          .toList();

      final count = json['count'] ?? users.length;
      
      developer.log(
        'Successfully created UserSearchResult',
        name: 'UserSearchResult',
        error: {
          'usersCount': users.length,
          'reportedCount': count,
          'users': users.map((u) => {
            'id': u.id,
            'username': u.username,
            'email': u.email,
          }).toList(),
        },
        level: 800,
      );

      return UserSearchResult(
        results: users,
        count: count,
      );
    } catch (e) {
      developer.log(
        'Error parsing UserSearchResult',
        name: 'UserSearchResult',
        error: {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
          'stackTrace': e is Error ? e.stackTrace.toString() : 'No stack trace',
          'rawJson': json,
        },
        level: 1000,
      );
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'results': results.map((user) => user.toJson()).toList(),
      'count': count,
    };
  }

  @override
  String toString() {
    return 'UserSearchResult(count: $count, results: ${results.length} users)';
  }
}

/// Service for user search and management via REST API
class UserSearchService {
  static const String _baseUrl = 'https://chatcornerbackend-production.up.railway.app';
  
  /// Search results response from the API
  static Future<UserSearchResult> searchUsers(String searchTerm, String authToken) async {
    developer.log(
      'Starting user search',
      name: 'UserSearchService',
      error: null,
      level: 800,
    );
    
    if (searchTerm.trim().isEmpty) {
      developer.log(
        'Search term is empty, returning empty results',
        name: 'UserSearchService',
        level: 800,
      );
      return const UserSearchResult(results: [], count: 0);
    }
    
    final url = '$_baseUrl/api/users/search/?q=${Uri.encodeComponent(searchTerm)}';
    developer.log(
      'Making search request',
      name: 'UserSearchService',
      error: {
        'url': url,
        'searchTerm': searchTerm,
        'hasAuthToken': authToken.isNotEmpty,
        'authTokenLength': authToken.length,
      },
      level: 800,
    );
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Token $authToken',
          'Content-Type': 'application/json',
        },
      );
      
      developer.log(
        'Received search response',
        name: 'UserSearchService',
        error: {
          'statusCode': response.statusCode,
          'responseBody': response.body,
          'responseHeaders': response.headers,
        },
        level: 800,
      );
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body) as Map<String, dynamic>;
          developer.log(
            'Successfully parsed response data',
            name: 'UserSearchService',
            error: {
              'parsedData': data,
              'resultsCount': data['results']?.length ?? 0,
            },
            level: 800,
          );
          
          final result = UserSearchResult.fromJson(data);
          developer.log(
            'Successfully created UserSearchResult',
            name: 'UserSearchService',
            error: {
              'resultCount': result.count,
              'actualResults': result.results.length,
              'users': result.results.map((u) => {
                'id': u.id,
                'username': u.username,
                'email': u.email,
                'availability': u.availability,
              }).toList(),
            },
            level: 800,
          );
          
          return result;
        } catch (parseError) {
          developer.log(
            'Error parsing successful response',
            name: 'UserSearchService',
            error: {
              'parseError': parseError.toString(),
              'rawResponse': response.body,
            },
            level: 1000,
          );
          throw Exception('Failed to parse search response: $parseError');
        }
      } else if (response.statusCode == 400) {
        try {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final errorMessage = data['error'] ?? 'Search query parameter "q" is required';
          developer.log(
            'Bad request error (400)',
            name: 'UserSearchService',
            error: {
              'errorMessage': errorMessage,
              'responseData': data,
            },
            level: 900,
          );
          throw Exception(errorMessage);
        } catch (parseError) {
          developer.log(
            'Error parsing 400 response',
            name: 'UserSearchService',
            error: {
              'parseError': parseError.toString(),
              'rawResponse': response.body,
            },
            level: 1000,
          );
          throw Exception('Bad request: ${response.body}');
        }
      } else if (response.statusCode == 401) {
        developer.log(
          'Authentication error (401)',
          name: 'UserSearchService',
          error: {
            'responseBody': response.body,
            'authToken': authToken.substring(0, 10) + '...',
          },
          level: 900,
        );
        throw Exception('Authentication credentials were not provided');
      } else {
        developer.log(
          'Unexpected status code',
          name: 'UserSearchService',
          error: {
            'statusCode': response.statusCode,
            'responseBody': response.body,
            'responseHeaders': response.headers,
          },
          level: 1000,
        );
        throw Exception('Search failed with status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      developer.log(
        'Network or other error during search',
        name: 'UserSearchService',
        error: {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
          'stackTrace': e is Error ? e.stackTrace.toString() : 'No stack trace',
        },
        level: 1000,
      );
      
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }
  
  /// Get user profile by ID
  static Future<User?> getUserById(int userId, String authToken) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/users/$userId/'),
        headers: {
          'Authorization': 'Token $authToken',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return User.fromJson(data);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get user profile: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }
}