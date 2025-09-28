class AppConstants {
  // App Information
  static const String appName = 'HiChat';
  static const String appVersion = '1.0.0';
  
  // API Configuration (TODO: Replace with your actual API endpoints)
  static const String baseUrl = 'https://your-api-url.com/api';
  static const String authEndpoint = '$baseUrl/auth';
  static const String usersEndpoint = '$baseUrl/users';
  static const String chatsEndpoint = '$baseUrl/chats';
  static const String messagesEndpoint = '$baseUrl/messages';
  
  // Storage Keys
  static const String userTokenKey = 'user_token';
  static const String userIdKey = 'user_id';
  static const String themeKey = 'theme_mode';
  static const String notificationsKey = 'notifications_enabled';
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double buttonHeight = 48.0;
  static const double appBarHeight = 56.0;
  
  // Chat Constants
  static const int maxMessageLength = 1000;
  static const int maxGroupNameLength = 50;
  static const int maxGroupMembers = 100;
  static const Duration typingIndicatorTimeout = Duration(seconds: 3);
  
  // File Upload Constants
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'gif'];
  static const List<String> allowedVideoTypes = ['mp4', 'mov', 'avi'];
  static const List<String> allowedAudioTypes = ['mp3', 'wav', 'aac'];
  static const List<String> allowedDocumentTypes = ['pdf', 'doc', 'docx', 'txt'];
  
  // Validation Rules
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 50;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 30;
  
  // Error Messages
  static const String networkError = 'Network error. Please check your connection.';
  static const String serverError = 'Server error. Please try again later.';
  static const String authError = 'Authentication failed. Please login again.';
  static const String invalidCredentials = 'Invalid email or password.';
  static const String userNotFound = 'User not found.';
  static const String emailAlreadyExists = 'Email already exists.';
  static const String usernameAlreadyExists = 'Username already exists.';
  
  // Success Messages
  static const String registrationSuccess = 'Account created successfully!';
  static const String loginSuccess = 'Welcome back!';
  static const String profileUpdated = 'Profile updated successfully!';
  static const String passwordChanged = 'Password changed successfully!';
  static const String messageSent = 'Message sent!';
  
  // Route Names
  static const String splashRoute = '/';
  static const String welcomeRoute = '/welcome';
  static const String authOptionsRoute = '/auth-options';
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String profileSetupRoute = '/profile-setup';
  static const String phoneSigninRoute = '/phone-signin';
  static const String otpVerificationRoute = '/otp-verification';
  static const String chatListRoute = '/chat-list';
  static const String chatRoute = '/chat';
  static const String profileRoute = '/profile';
  static const String settingsRoute = '/settings';
  static const String newChatRoute = '/new-chat';
  static const String groupChatRoute = '/group-chat';
  
  // Shared Preferences Keys
  static const String firstLaunchKey = 'first_launch';
  static const String languageKey = 'language';
  static const String fontSize = 'font_size';
  
  // Default Values
  static const String defaultProfileImage = 'assets/images/default_avatar.png';
  static const String defaultGroupImage = 'assets/images/default_group.png';
  
  // Camera Routes
  static const String cameraRoute = '/camera';
}