import 'dart:async';
import '../models/user.dart';

class AuthService {
  User? _currentUser;
  final _authController = StreamController<User?>.broadcast();
  
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  // Simulate authentication state changes
  Stream<User?> get authStateChanges => _authController.stream;

  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    // TODO: Implement actual authentication with your backend
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2));
    
    // Mock validation
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email and password are required');
    }
    
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      throw Exception('Invalid email format');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    // For demo purposes, accept any valid email/password
    _currentUser = User(
      id: 'currentUser',
      username: email.split('@')[0],
      email: email,
      isOnline: true,
      createdAt: DateTime.now(),
    );

    _authController.add(_currentUser);
    return _currentUser!;
  }

  Future<User> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    // TODO: Implement actual registration with your backend
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2));
    
    // Mock validation
    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      throw Exception('All fields are required');
    }
    
    if (username.length < 3) {
      throw Exception('Username must be at least 3 characters');
    }
    
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      throw Exception('Invalid email format');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    // For demo purposes, create a new user
    final user = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      username: username,
      email: email,
      isOnline: true,
      createdAt: DateTime.now(),
    );

    return user;
  }

  Future<void> signOut() async {
    // TODO: Implement actual sign out with your backend
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    _currentUser = null;
    _authController.add(null);
  }

  Future<void> updateProfile({
    String? username,
    String? profileImageUrl,
  }) async {
    if (_currentUser == null) {
      throw Exception('User not authenticated');
    }

    // TODO: Implement actual profile update with your backend
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    _currentUser = _currentUser!.copyWith(
      username: username ?? _currentUser!.username,
      profileImageUrl: profileImageUrl ?? _currentUser!.profileImageUrl,
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_currentUser == null) {
      throw Exception('User not authenticated');
    }

    // TODO: Implement actual password change with your backend
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    if (newPassword.length < 6) {
      throw Exception('New password must be at least 6 characters');
    }

    // Mock validation - in real app, verify current password with backend
    if (currentPassword.isEmpty) {
      throw Exception('Current password is required');
    }
  }

  Future<void> resetPassword({required String email}) async {
    // TODO: Implement actual password reset with your backend
    
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      throw Exception('Invalid email format');
    }
  }

  void dispose() {
    _authController.close();
  }
}