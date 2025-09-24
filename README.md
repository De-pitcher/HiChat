# HiChat 💬

A modern, elegant chat application built with **Flutter** that provides seamless real-time messaging with beautiful animations and intuitive user experience.

[![Flutter Version](https://img.shields.io/badge/Flutter-3.8.1-blue.svg)](https://flutter.dev/)
[![Dart Version](https://img.shields.io/badge/Dart-2.19.6-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## ✨ Features

### 🔐 Authentication System
- **Secure Login/Registration** with email validation and password encryption
- **Remember Me Functionality** - Stores credentials for quick access (form convenience only)
- **Session Management** - Automatic login state persistence with secure logout
- **Password Reset** - *Coming Soon*

### 💬 Chat System
- **Real-time Messaging** - Instant message delivery and updates
- **Chat List** - Overview of all conversations with unread indicators
- **User Profiles** - Rich user information and avatar support
- **Message Status** - Read/unread indicators and timestamps
- **Group Chats** - *Coming Soon*

### 🎨 UI/UX Excellence
- **Smooth Animations** - Custom page transitions and micro-interactions
- **Material Design** - Following Google's design principles
- **Responsive Layout** - Optimized for different screen sizes
- **Dark/Light Theme** - *Coming Soon*
- **Accessibility** - Screen reader support and proper contrast ratios

### 🚀 Performance & Architecture
- **State Management** - Provider pattern for reactive UI updates
- **API Integration** - RESTful API with proper error handling
- **Offline Support** - *Coming Soon*
- **Push Notifications** - *Coming Soon*

## 📱 Screenshots

| Welcome Screen | Login Screen | Chat List |
|:---:|:---:|:---:|
| ![Welcome](docs/screenshots/welcome.png) | ![Login](docs/screenshots/login.png) | ![Chat List](docs/screenshots/chat_list.png) |

*Screenshots coming soon*

## 🏗️ Architecture

```
lib/
├── constants/          # App constants, themes, and configurations
│   ├── app_constants.dart
│   └── app_theme.dart
├── models/            # Data models and entities
│   ├── user.dart
│   ├── chat.dart
│   └── message.dart
├── screens/           # UI screens and pages
│   ├── auth/         # Authentication screens
│   ├── chat/         # Chat-related screens
│   └── welcome/      # Welcome and onboarding
├── services/          # Business logic and API services
│   ├── api_service.dart
│   ├── auth_state_manager.dart
│   └── chat_service.dart
├── utils/             # Utility functions and helpers
│   └── page_transitions.dart
├── widgets/           # Reusable UI components
└── main.dart          # App entry point
```

## 🛠️ Tech Stack

- **Frontend**: Flutter 3.8.1
- **Language**: Dart 2.19.6
- **State Management**: Provider 6.1.5
- **HTTP Client**: http 1.2.2
- **Local Storage**: SharedPreferences 2.2.2
- **Typography**: Google Fonts 6.2.1
- **Testing**: flutter_test, mockito

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.8.1 or higher
- Dart SDK 2.19.6 or higher
- iOS Simulator / Android Emulator or physical device
- IDE (VS Code, Android Studio, or IntelliJ)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/De-pitcher/HiChat.git
   cd HiChat
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   # For development
   flutter run
   
   # For release build
   flutter run --release
   ```

### Development Setup

1. **Configure API endpoint** (if using backend)
   ```dart
   // lib/constants/app_constants.dart
   static const String baseUrl = 'https://your-api-url.com/api';
   ```

2. **Run tests**
   ```bash
   # Unit tests
   flutter test
   
   # Integration tests
   flutter test integration_test/
   ```

3. **Code analysis**
   ```bash
   flutter analyze
   ```

## 📚 Documentation

- [Navigation Animations](docs/NAVIGATION_ANIMATIONS.md) - Custom page transitions and animations
- [API Integration](docs/API_INTEGRATION.md) - *Coming Soon*
- [State Management](docs/STATE_MANAGEMENT.md) - *Coming Soon*
- [Testing Guide](docs/TESTING.md) - *Coming Soon*

## 🎯 Roadmap

### Phase 1: Core Features ✅
- [x] Authentication system
- [x] Basic chat interface
- [x] Navigation animations
- [x] State management

### Phase 2: Enhanced Features 🚧
- [ ] Real-time messaging (WebSocket)
- [ ] Push notifications
- [ ] File sharing (images, documents)
- [ ] Group chats

### Phase 3: Advanced Features 📋
- [ ] Voice messages
- [ ] Video calls
- [ ] Message encryption
- [ ] Offline support
- [ ] Dark theme

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👥 Team

- **De-pitcher** - *Lead Developer* - [@De-pitcher](https://github.com/De-pitcher)

## 🎉 Acknowledgments

- Flutter team for the amazing framework
- Material Design for the design principles
- The open-source community for inspiration and tools

## 📞 Support

If you have any questions or need help, please:

1. Check the [documentation](docs/)
2. Search [existing issues](https://github.com/De-pitcher/HiChat/issues)
3. Create a [new issue](https://github.com/De-pitcher/HiChat/issues/new) if needed

---

<div align="center">
  
**Built with ❤️ using Flutter**

[⭐ Star this project](https://github.com/De-pitcher/HiChat) if you find it helpful!

</div>
