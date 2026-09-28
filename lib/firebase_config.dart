import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase project configuration.
///
/// The project is `until-8ef15`. These values are **public identifiers, not
/// secrets** — they ship inside every web bundle and every app binary, which is
/// why Firebase's own docs say to commit them. What actually protects the data
/// is `firestore.rules`, which is the authority for every read and write.
///
/// The per-platform files carry the same config and are read automatically by
/// `Firebase.initializeApp()` on Android and iOS:
///
///   android/app/google-services.json
///   ios/Runner/GoogleService-Info.plist
///
/// Regenerate both (and this file) with:
///
///   flutterfire configure --project=until-8ef15
///
/// After running that, you can replace the `currentPlatform` getter below with
/// the generated one-liner — `DefaultFirebaseOptions.currentPlatform` from
/// `lib/firebase_options.dart` — and delete this file.

/// Project ID — used by the emulator suite and by the rules deploy script.
const firebaseProjectId = 'until-8ef15';

/// Web is the one platform that cannot read a native config file, so its
/// options must be supplied here.
///
/// These are filled in by `flutterfire configure`. Until that runs, web build
/// **compile and render** but cannot connect to Firebase — the app will show
/// "Could not reach the sign-in service", which is the expected unsigned state.
///
/// You can supply them without regenerating this file by passing them at build
/// time instead, which keeps environment-specific values out of the source:
///
///   flutter run -d chrome \
///     --dart-define=FIREBASE_API_KEY=... \
///     --dart-define=FIREBASE_APP_ID=... \
///     --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///     --dart-define=FIREBASE_AUTH_DOMAIN=until-8ef15.firebaseapp.com \
///     --dart-define=FIREBASE_STORAGE_BUCKET=until-8ef15.appspot.com
const _webApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _webAppId = String.fromEnvironment('FIREBASE_APP_ID');
const _webSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _webAuthDomain = String.fromEnvironment(
  'FIREBASE_AUTH_DOMAIN',
  defaultValue: '$firebaseProjectId.firebaseapp.com',
);
const _webStorageBucket = String.fromEnvironment(
  'FIREBASE_STORAGE_BUCKET',
  defaultValue: '$firebaseProjectId.appspot.com',
);

/// True when the web config has actually been supplied.
///
/// Used to fail with a clear, actionable message instead of Firebase's opaque
/// "API key not valid" crash.
bool get hasWebFirebaseConfig => _webApiKey.isNotEmpty && _webAppId.isNotEmpty;

FirebaseOptions get firebaseOptions {
  if (kIsWeb) {
    return const FirebaseOptions(
      apiKey: _webApiKey,
      appId: _webAppId,
      messagingSenderId: _webSenderId,
      projectId: firebaseProjectId,
      authDomain: _webAuthDomain,
      storageBucket: _webStorageBucket,
    );
  }

  // Android and iOS read their own config files, so only the project id needs
  // to be stated here. `flutterfire configure` overwrites this whole getter.
  return const FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: firebaseProjectId,
    storageBucket: 'until-8ef15.appspot.com',
    iosBundleId: 'com.until.until',
    androidClientId: '',
    iosClientId: '',
  );
}