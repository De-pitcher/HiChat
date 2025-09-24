// This is a basic Flutter widget test for HiChat app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hichat_app/screens/auth/login_screen.dart';
import 'package:hichat_app/screens/auth/register_screen.dart';
import 'package:hichat_app/services/auth_state_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Initialize SharedPreferences for testing
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HiChat app smoke test', (WidgetTester tester) async {
    // Create an AuthStateManager
    final authStateManager = AuthStateManager();
    
    // Build the login screen directly with Provider
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthStateManager>(
          create: (_) => authStateManager,
          child: const LoginScreen(),
        ),
      ),
    );

    // Wait for any async operations
    await tester.pump();

    // Verify that the login screen is displayed
    expect(find.text('Login to Your Account'), findsOneWidget);

    // Verify that login form fields are present
    expect(find.byType(TextFormField), findsAtLeast(2)); // Email and password fields
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text("Don't have an account?"), findsOneWidget);
  });

  testWidgets('Login form validation test', (WidgetTester tester) async {
    // Create an AuthStateManager
    final authStateManager = AuthStateManager();
    
    // Build the login screen directly with Provider
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthStateManager>(
          create: (_) => authStateManager,
          child: const LoginScreen(),
        ),
      ),
    );

    // Wait for any async operations
    await tester.pump();

    // Find the Sign in button and tap it without entering any data
    final signInButton = find.text('Sign in');
    await tester.tap(signInButton);
    await tester.pump();

    // Verify that validation error messages appear
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('Navigation to register screen test', (WidgetTester tester) async {
    // Create an AuthStateManager
    final authStateManager = AuthStateManager();
    
    // Build the login screen with navigation capability
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthStateManager>(
          create: (_) => authStateManager,
          child: const LoginScreen(),
        ),
        routes: {
          '/register': (context) => const RegisterScreen(),
        },
      ),
    );

    // Wait for any async operations
    await tester.pump();

    // Find and tap the " Sign Up" link
    final signUpLink = find.text(' Sign Up');
    await tester.tap(signUpLink);
    await tester.pumpAndSettle(); // Wait for navigation animation

    // Verify that we're now on the register screen
    expect(find.text('Create Account'), findsAtLeast(1)); // AppBar title and button
    expect(find.text('Join HiChat'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });
}
