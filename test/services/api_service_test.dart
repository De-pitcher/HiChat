import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

import 'package:hichat_app/services/api_service.dart';
import 'package:hichat_app/services/api_exceptions.dart';
import 'package:hichat_app/models/user.dart';

// Generate mocks
@GenerateMocks([http.Client])
import 'api_service_test.mocks.dart';

void main() {
  group('ApiService', () {
    late ApiService apiService;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      apiService = ApiService(client: mockClient);
    });

    tearDown(() {
      apiService.dispose();
    });

    group('login', () {
      const testEmail = 'test@example.com';
      const testPassword = 'testpassword123';
      
      final loginRequest = LoginRequest(
        email: testEmail,
        password: testPassword,
      );

      final mockUserResponse = {
        'user': {
          'id': 1,
          'email': testEmail,
          'image_url': 'https://example.com/avatar.png',
          'username': 'testuser',
          'phone_number': '+1234567890',
          'token': 'mock_jwt_token_12345',
          'about': 'Test user bio',
          'date_of_birth': '1990-01-01',
          'availability': 'online',
          'created_at': '2025-08-19T16:55:16.299022Z',
        },
      };

      test('successful login returns LoginResponse', () async {
        // Arrange
        when(mockClient.post(
          Uri.parse('https://chatcornerbackend-production.up.railway.app/api/users/login/'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode(loginRequest.toJson()),
        )).thenAnswer((_) async => http.Response(
          json.encode(mockUserResponse),
          200,
        ));

        // Act
        final result = await apiService.login(loginRequest);

        // Assert
        expect(result, isA<LoginResponse>());
        expect(result.user.id, equals(1));
        expect(result.user.email, equals(testEmail));
        expect(result.user.username, equals('testuser'));
        expect(result.user.token, equals('mock_jwt_token_12345'));
        expect(result.user.availability, equals('online'));
        
        verify(mockClient.post(
          Uri.parse('https://chatcornerbackend-production.up.railway.app/api/users/login/'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode(loginRequest.toJson()),
        )).called(1);
      });

      test('login with 401 status throws AuthenticationException', () async {
        // Arrange
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(
          json.encode({'message': 'Invalid credentials'}),
          401,
        ));

        // Act & Assert
        expect(
          () async => await apiService.login(loginRequest),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('login with 400 status throws ValidationException', () async {
        // Arrange
        final errorResponse = {
          'message': 'Validation failed',
          'errors': {
            'email': ['Email is required'],
            'password': ['Password must be at least 6 characters'],
          },
        };

        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(
          json.encode(errorResponse),
          400,
        ));

        // Act & Assert
        try {
          await apiService.login(loginRequest);
          fail('Expected ValidationException');
        } catch (e) {
          expect(e, isA<ValidationException>());
          final validationError = e as ValidationException;
          expect(validationError.message, equals('Validation failed'));
          expect(validationError.statusCode, equals(400));
          expect(validationError.validationErrors, isNotNull);
        }
      });

      test('login with 500 status throws ServerException', () async {
        // Arrange
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(
          'Internal Server Error',
          500,
        ));

        // Act & Assert
        expect(
          () async => await apiService.login(loginRequest),
          throwsA(isA<ServerException>()),
        );
      });

      test('login with network error throws NetworkException', () async {
        // Arrange
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenThrow(const SocketException('No internet connection'));

        // Act & Assert
        expect(
          () async => await apiService.login(loginRequest),
          throwsA(isA<NetworkException>()),
        );
      });

      test('login with invalid JSON response throws ApiException', () async {
        // Arrange
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(
          'Invalid JSON response',
          200,
        ));

        // Act & Assert
        expect(
          () async => await apiService.login(loginRequest),
          throwsA(isA<ApiException>()),
        );
      });

      test('login request timeout throws ApiException', () async {
        // Arrange
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async {
          // Simulate a timeout by throwing TimeoutException
          throw TimeoutException('Request timeout', const Duration(seconds: 30));
        });

        // Act & Assert
        expect(
          () async => await apiService.login(loginRequest),
          throwsA(isA<ApiException>()),
        );
      });

      test('login with direct user response format returns LoginResponse', () async {
        // Arrange - Direct user data format (like your actual API)
        final directUserResponse = {
          'id': 1,
          'email': 'zalexbis@gmail.com',
          'image_url': 'http://res.cloudinary.com/dsazvjswi/image/upload/v1750348989/chat_corner/profile/edsbyxbrjhqnl7yymxsd',
          'username': 'Admin',
          'phone_number': '08107571819',
          'token': '4bd0415dc7bea0af3b4a6b2c1af82866d4a3d393',
          'about': 'I am legand',
          'date_of_birth': null,
          'availability': 'Very available',
          'created_at': '2025-05-31T11:53:50.385764Z',
        };

        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(
          json.encode(directUserResponse),
          200,
        ));

        // Act
        final result = await apiService.login(loginRequest);

        // Assert
        expect(result, isA<LoginResponse>());
        expect(result.user.id, equals(1));
        expect(result.user.email, equals('zalexbis@gmail.com'));
        expect(result.user.username, equals('Admin'));
        expect(result.user.token, equals('4bd0415dc7bea0af3b4a6b2c1af82866d4a3d393'));
        expect(result.user.availability, equals('Very available'));
      });
    });

    group('getUserProfile', () {
      const testToken = 'test_jwt_token';
      
      final mockUser = {
        'id': 1,
        'email': 'user@example.com',
        'image_url': 'https://example.com/avatar.png',
        'username': 'testuser',
        'phone_number': '+1234567890',
        'token': testToken,
        'about': 'Test user bio',
        'date_of_birth': '1990-01-01',
        'availability': 'online',
        'created_at': '2025-08-19T16:55:16.299022Z',
      };

      test('successful getUserProfile returns User', () async {
        // Arrange
        when(mockClient.get(
          Uri.parse('https://chatcornerbackend-production.up.railway.app/api/users/profile/'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $testToken',
          },
        )).thenAnswer((_) async => http.Response(
          json.encode(mockUser),
          200,
        ));

        // Act
        final result = await apiService.getUserProfile(testToken);

        // Assert
        expect(result, isA<User>());
        expect(result.id, equals(1));
        expect(result.email, equals('user@example.com'));
        expect(result.username, equals('testuser'));
      });

      test('getUserProfile with 401 throws AuthenticationException', () async {
        // Arrange
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response(
          json.encode({'message': 'Token expired'}),
          401,
        ));

        // Act & Assert
        expect(
          () async => await apiService.getUserProfile(testToken),
          throwsA(isA<AuthenticationException>()),
        );
      });
    });

    group('logout', () {
      const testToken = 'test_jwt_token';

      test('successful logout completes without error', () async {
        // Arrange
        when(mockClient.post(
          Uri.parse('https://chatcornerbackend-production.up.railway.app/api/users/logout/'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $testToken',
          },
        )).thenAnswer((_) async => http.Response('', 200));

        // Act & Assert
        expect(() async => await apiService.logout(testToken), returnsNormally);
      });

      test('logout with error status throws ApiException', () async {
        // Arrange
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Logout failed', 500));

        // Act & Assert
        expect(
          () async => await apiService.logout(testToken),
          throwsA(isA<ApiException>()),
        );
      });
    });
  });
}