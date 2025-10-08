import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'constants/app_constants.dart';
import 'services/auth_state_manager.dart';
import 'services/chat_state_manager.dart';
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
import 'models/chat.dart';
import 'utils/page_transitions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const HiChatApp());
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
