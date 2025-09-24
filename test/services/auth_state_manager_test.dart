import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hichat_app/services/auth_state_manager.dart';

void main() {
  group('AuthStateManager', () {
    late AuthStateManager authManager;

    setUp(() {
      authManager = AuthStateManager();
      // Mock SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      authManager.dispose();
    });

    test('initial state should be logged out', () {
      expect(authManager.isLoggedIn, false);
      expect(authManager.currentUser, null);
      expect(authManager.isLoading, false);
      expect(authManager.rememberMe, false);
    });

    test('updateRememberMe should update the state', () async {
      await authManager.updateRememberMe(true);
      expect(authManager.rememberMe, true);

      await authManager.updateRememberMe(false);
      expect(authManager.rememberMe, false);
    });

    test('logout should clear session state only', () async {
      // Simulate a basic logout (with no remember me data initially)
      await authManager.logout();
      
      expect(authManager.isLoggedIn, false);
      expect(authManager.currentUser, null);
      expect(authManager.rememberMe, false);
      expect(authManager.rememberedEmail, '');
      expect(authManager.rememberedPassword, '');
    });

    test('logout should clear session data but preserve remember me', () async {
      // Mock SharedPreferences with remember me data
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'current_user': '{"id":1,"email":"test@example.com","username":"testuser","token":"test_token","phone_number":"123","about":"test","availability":"online","created_at":"2025-01-01T00:00:00.000Z"}',
        'remember_me': true,
        'remembered_email': 'test@example.com',
        'remembered_password': 'password123',
      });
      
      final testAuthManager = AuthStateManager();
      await testAuthManager.initialize();
      
      // Verify initial state (user should be logged in)
      expect(testAuthManager.isLoggedIn, true);
      expect(testAuthManager.currentUser?.email, 'test@example.com');
      expect(testAuthManager.rememberMe, true);
      expect(testAuthManager.rememberedEmail, 'test@example.com');
      
      // Logout
      await testAuthManager.logout();
      
      // Verify session data is cleared but remember me is preserved
      expect(testAuthManager.isLoggedIn, false);
      expect(testAuthManager.currentUser, null);
      expect(testAuthManager.rememberMe, true); // Should remain true
      expect(testAuthManager.rememberedEmail, 'test@example.com'); // Should remain
      expect(testAuthManager.rememberedPassword, 'password123'); // Should remain
      
      testAuthManager.dispose();
    });

    test('after logout, remember me credentials should be preserved', () async {
      // Mock SharedPreferences with remember me data
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'current_user': '{"id":1,"email":"test@example.com","username":"testuser","token":"test_token","phone_number":"123","about":"test","availability":"online","created_at":"2025-01-01T00:00:00.000Z"}',
        'remember_me': true,
        'remembered_email': 'test@example.com',
        'remembered_password': 'password123',
      });
      
      final testAuthManager1 = AuthStateManager();
      await testAuthManager1.initialize();
      
      // Verify user is initially logged in with remember me
      expect(testAuthManager1.isLoggedIn, true);
      expect(testAuthManager1.rememberMe, true);
      expect(testAuthManager1.rememberedEmail, 'test@example.com');
      
      // Logout
      await testAuthManager1.logout();
      
      // Verify session is cleared but remember me is preserved
      expect(testAuthManager1.isLoggedIn, false);
      expect(testAuthManager1.currentUser, null);
      expect(testAuthManager1.rememberMe, true); // Should still be true
      expect(testAuthManager1.rememberedEmail, 'test@example.com'); // Should still be preserved
      
      testAuthManager1.dispose();
      
      // Create new instance and initialize (simulating app restart)
      final testAuthManager2 = AuthStateManager();
      await testAuthManager2.initialize();
      
      // Should NOT auto-login, but remember me data should be available for form pre-filling
      expect(testAuthManager2.isLoggedIn, false);
      expect(testAuthManager2.currentUser, null);
      expect(testAuthManager2.rememberMe, true); // Remember me preference preserved
      expect(testAuthManager2.rememberedEmail, 'test@example.com'); // Email available for pre-filling
      
      testAuthManager2.dispose();
    });

    test('initialize should load saved state', () async {
      // Pre-populate SharedPreferences with saved state
      SharedPreferences.setMockInitialValues({
        'remember_me': true,
        'remembered_email': 'test@example.com',
      });

      await authManager.initialize();
      
      expect(authManager.rememberMe, true);
      expect(authManager.rememberedEmail, 'test@example.com');
    });
  });
}