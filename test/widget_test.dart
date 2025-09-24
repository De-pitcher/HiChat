// This is a basic Flutter widget test for HiChat app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hichat_app/main.dart';

void main() {
  testWidgets('HiChat app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HiChatApp());

    // Verify that the login screen is displayed
    expect(find.text('Welcome to HiChat'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);

    // Verify that login form fields are present
    expect(find.byType(TextFormField), findsAtLeast(2)); // Email and password fields
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Don\'t have an account? Sign up'), findsOneWidget);
  });

  testWidgets('Login form validation test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HiChatApp());

    // Find the Sign In button and tap it without entering any data
    final signInButton = find.text('Sign In');
    await tester.tap(signInButton);
    await tester.pump();

    // Verify that validation error messages appear
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('Navigation to register screen test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HiChatApp());

    // Find and tap the "Sign up" link
    final signUpLink = find.text('Don\'t have an account? Sign up');
    await tester.tap(signUpLink);
    await tester.pumpAndSettle(); // Wait for navigation animation

    // Verify that we're now on the register screen
    expect(find.text('Create Account'), findsAtLeast(1)); // AppBar title and button
    expect(find.text('Join HiChat'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });
}
