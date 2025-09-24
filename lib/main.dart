import 'package:flutter/material.dart';
import 'constants/app_theme.dart';
import 'constants/app_constants.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/welcome/welcome_screen.dart';
import 'screens/auth/auth_options_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'models/chat.dart';

void main() {
  runApp(const HiChatApp());
}

class HiChatApp extends StatelessWidget {
  const HiChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      initialRoute: AppConstants.splashRoute,
      routes: {
        AppConstants.splashRoute: (context) => const SplashScreen(),
        AppConstants.welcomeRoute: (context) => const WelcomeScreen(),
        AppConstants.authOptionsRoute: (context) => const AuthOptionsScreen(),
        AppConstants.loginRoute: (context) => const LoginScreen(),
        AppConstants.registerRoute: (context) => const RegisterScreen(),
        AppConstants.chatListRoute: (context) => const ChatListScreen(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case AppConstants.chatRoute:
            final chat = settings.arguments as Chat;
            return MaterialPageRoute(
              builder: (context) => ChatScreen(chat: chat),
            );
          default:
            return MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            );
        }
      },
    );
  }
}
