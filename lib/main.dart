import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/providers.dart';
import 'application/sync_controller.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Application-support dir is private to the app (not user-visible storage).
  final dir = await getApplicationSupportDirectory();

  // Cloud sync is optional. Without google-services.json (Android) or
  // GoogleService-Info.plist (iOS) initialisation fails and the app simply
  // runs offline-only.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } on Object {
    firebaseReady = false;
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        vaultDirProvider.overrideWithValue(dir),
        firebaseReadyProvider.overrideWithValue(firebaseReady),
      ],
      child: const SecureVaultApp(),
    ),
  );
}
