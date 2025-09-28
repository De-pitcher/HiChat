import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA5_RzaCrpTcTbOkfJi5QAvS67BTnz1z4M',
    appId: '1:840338952677:web:d088a5d6697a8d15afdf0c',
    messagingSenderId: '840338952677',
    projectId: 'hi-chat-12aa2',
    authDomain: 'hi-chat-12aa2.firebaseapp.com',
    storageBucket: 'hi-chat-12aa2.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA5_RzaCrpTcTbOkfJi5QAvS67BTnz1z4M',
    appId: '1:840338952677:android:d088a5d6697a8d15afdf0c',
    messagingSenderId: '840338952677',
    projectId: 'hi-chat-12aa2',
    storageBucket: 'hi-chat-12aa2.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA5_RzaCrpTcTbOkfJi5QAvS67BTnz1z4M',
    appId: '1:840338952677:ios:d088a5d6697a8d15afdf0c',
    messagingSenderId: '840338952677',
    projectId: 'hi-chat-12aa2',
    storageBucket: 'hi-chat-12aa2.firebasestorage.app',
    iosBundleId: 'com.rodeni.hi_chat',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA5_RzaCrpTcTbOkfJi5QAvS67BTnz1z4M',
    appId: '1:840338952677:ios:d088a5d6697a8d15afdf0c',
    messagingSenderId: '840338952677',
    projectId: 'hi-chat-12aa2',
    storageBucket: 'hi-chat-12aa2.firebasestorage.app',
    iosBundleId: 'com.rodeni.hi_chat',
  );
}