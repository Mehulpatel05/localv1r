import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        return windows;
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
    apiKey: 'AIzaSyBSEkMzK2etCTIT2l5TofUt21w-abnCedg',
    appId: '1:353458725270:web:a445942b270910ba0fbdb7',
    messagingSenderId: '353458725270',
    projectId: 'free-fee25',
    authDomain: 'free-fee25.firebaseapp.com',
    storageBucket: 'free-fee25.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC7ItsvwYUHZshMqWy9qklWFM7w-PbStgA',
    appId: '1:353458725270:android:daa96e09da9ba8710fbdb7',
    messagingSenderId: '353458725270',
    projectId: 'free-fee25',
    storageBucket: 'free-fee25.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB9pQRmql2l6Dy6urPexd3KJxeXE6yqRcw',
    appId: '1:353458725270:ios:c0ea24775fab3fb20fbdb7',
    messagingSenderId: '353458725270',
    projectId: 'free-fee25',
    storageBucket: 'free-fee25.firebasestorage.app',
    iosBundleId: 'com.social.nearhood',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyB9pQRmql2l6Dy6urPexd3KJxeXE6yqRcw',
    appId: '1:353458725270:ios:c0ea24775fab3fb20fbdb7',
    messagingSenderId: '353458725270',
    projectId: 'free-fee25',
    storageBucket: 'free-fee25.firebasestorage.app',
    iosBundleId: 'com.social.nearhood',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBSEkMzK2etCTIT2l5TofUt21w-abnCedg',
    appId: '1:353458725270:web:a445942b270910ba0fbdb7',
    messagingSenderId: '353458725270',
    projectId: 'free-fee25',
    authDomain: 'free-fee25.firebaseapp.com',
    storageBucket: 'free-fee25.firebasestorage.app',
  );
}
