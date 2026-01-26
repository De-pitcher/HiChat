import 'package:flutter/material.dart';
import '../test/google_signin_test.dart';

class GoogleSignInTestPage extends StatefulWidget {
  const GoogleSignInTestPage({super.key});

  @override
  State<GoogleSignInTestPage> createState() => _GoogleSignInTestPageState();
}

class _GoogleSignInTestPageState extends State<GoogleSignInTestPage> {
  String _status = 'Ready to test';
  bool _isLoading = false;
  Map<String, dynamic>? _lastResult;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  void _checkCurrentStatus() {
    final isSignedIn = GoogleSignInTest.isSignedIn();
    setState(() {
      _status = isSignedIn ? 'Currently signed in' : 'Currently signed out';
    });
  }

  Future<void> _testSignIn() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing Google Sign-In...';
    });

    try {
      final result = await GoogleSignInTest.testGoogleSignIn();
      setState(() {
        _lastResult = result;
        if (result == null) {
          _status = 'Sign-in cancelled by user';
        } else if (result['success'] == true) {
          _status = 'Sign-in successful!';
        } else {
          _status = 'Sign-in failed: ${result['error']}';
        }
      });
    } catch (e) {
      setState(() {
        _status = 'Test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testSignOut() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing sign out...';
    });

    try {
      final success = await GoogleSignInTest.testSignOut();
      setState(() {
        _status = success ? 'Sign out successful' : 'Sign out failed';
        _lastResult = null;
      });
    } catch (e) {
      setState(() {
        _status = 'Sign out test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Sign-In Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Firebase-Independent Google Sign-In Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: $_status',
                      style: TextStyle(
                        color: _status.contains('successful') 
                            ? Colors.green 
                            : _status.contains('failed') 
                                ? Colors.red 
                                : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Test Google Sign-In'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _testSignOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
              child: const Text('Test Sign Out'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _checkCurrentStatus,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
              child: const Text('Check Status'),
            ),
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Result:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_lastResult!['success'] == true) ...[
                        Text('✅ Email: ${_lastResult!['email']}'),
                        Text('✅ Name: ${_lastResult!['displayName']}'),
                        Text('✅ Google ID: ${_lastResult!['googleId']}'),
                        Text('✅ ID Token: ${_lastResult!['idToken'] != null ? "Available" : "Missing"}'),
                        Text('✅ Access Token: ${_lastResult!['accessToken'] != null ? "Available" : "Missing"}'),
                      ] else ...[
                        Text('❌ Error: ${_lastResult!['error']}'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const Spacer(),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Instructions:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Tap "Test Google Sign-In" to test authentication'),
                    Text('2. Select your Google account'),
                    Text('3. Check if tokens are received successfully'),
                    Text('4. Test sign out functionality'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}