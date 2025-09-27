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
    apiKey: 'AIzaSyByifTOohJNjkMQg0_MUkUl47kmZx13onw',
    appId: '1:282657049766:web:d33c08bb18713535f7b867',
    messagingSenderId: '282657049766',
    projectId: 'hi-call-1fc56',
    authDomain: 'hi-call-1fc56.firebaseapp.com',
    storageBucket: 'hi-call-1fc56.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyByifTOohJNjkMQg0_MUkUl47kmZx13onw',
    appId: '1:282657049766:android:d33c08bb18713535f7b867',
    messagingSenderId: '282657049766',
    projectId: 'hi-call-1fc56',
    storageBucket: 'hi-call-1fc56.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyByifTOohJNjkMQg0_MUkUl47kmZx13onw',
    appId: '1:282657049766:ios:d33c08bb18713535f7b867',
    messagingSenderId: '282657049766',
    projectId: 'hi-call-1fc56',
    storageBucket: 'hi-call-1fc56.firebasestorage.app',
    iosBundleId: 'com.rodeni.hichat',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyByifTOohJNjkMQg0_MUkUl47kmZx13onw',
    appId: '1:282657049766:ios:d33c08bb18713535f7b867',
    messagingSenderId: '282657049766',
    projectId: 'hi-call-1fc56',
    storageBucket: 'hi-call-1fc56.firebasestorage.app',
    iosBundleId: 'com.rodeni.hichat',
  );
}