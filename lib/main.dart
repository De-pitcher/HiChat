import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'constants/app_theme.dart';
import 'constants/app_constants.dart';
import 'services/auth_state_manager.dart';
import 'screens/welcome/welcome_screen.dart';
import 'screens/auth/auth_options_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'models/chat.dart';
import 'utils/page_transitions.dart';

void main() {
  runApp(const HiChatApp());
}

class HiChatApp extends StatelessWidget {
  const HiChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AuthStateManager(),
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
              return PageTransitions.fade(const AuthWrapper(), settings: settings);
              
            case AppConstants.authOptionsRoute:
              return PageTransitions.slideFromRight(const AuthOptionsScreen(), settings: settings);
            
            case AppConstants.loginRoute:
              return PageTransitions.slideFromRight(const LoginScreen(), settings: settings);
            
            case AppConstants.registerRoute:
              return PageTransitions.slideFromRight(const RegisterScreen(), settings: settings);
            
            case AppConstants.chatRoute:
              final chat = settings.arguments as Chat;
              return PageTransitions.slideFromRight(
                ChatScreen(chat: chat),
                settings: settings,
              );
            
            default:
              return PageTransitions.fade(const AuthWrapper(), settings: settings);
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
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
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
