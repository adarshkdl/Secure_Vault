# Firebase setup for SecureVault cloud sync

Cloud sync is optional. The app builds and works fully offline without any of
this. Do these steps once to turn sync on. You need a Google account and about
15 minutes. The free **Spark** plan is plenty for a personal vault.

What ends up in Firebase: your Google account id, random record ids, edit times,
a deleted flag, and **encrypted** record data. Titles, usernames, passwords,
notes and category names are encrypted on the phone before upload.

## 1. Create the project

1. Open <https://console.firebase.google.com> and sign in.
2. **Add project** -> name it (for example `securevault-yourname`).
3. Turn **Google Analytics off** (not needed) -> **Create project**.

## 2. Register the Android app

1. Project overview -> **Add app** -> Android.
2. **Android package name:** `com.securevault.secure_vault`
3. Nickname: `SecureVault Android`. Leave SHA-1 empty for now -> **Register app**.
4. Download **google-services.json** and put it at:

   ```
   android/app/google-services.json
   ```

   Skip the "Add Firebase SDK" steps in the console; the project already has them.
   The file is listed in `.gitignore` so it is not committed.

## 3. Turn on Google sign-in

1. **Build -> Authentication -> Get started**.
2. **Sign-in method -> Google -> Enable**, choose a support email, **Save**.
3. Recommended: add your debug SHA-1 so sign-in is accepted on development
   builds. In a terminal:

   ```
   cd android
   ./gradlew signingReport
   ```

   Copy the **SHA-1** of the `debug` variant, then in the console:
   **Project settings -> Your apps -> Android -> Add fingerprint**.
   If Google sign-in later fails with a developer/config error, this is the
   usual cause. Download a fresh `google-services.json` afterwards and replace
   the old one. Add your **release** key's SHA-1 the same way before publishing.

## 4. Create the database and publish the rules

1. **Build -> Firestore Database -> Create database**.
2. Choose **Production mode** and a location close to you (cannot be changed later).
3. Open the **Rules** tab, replace everything with the contents of
   [`firestore.rules`](../firestore.rules) from this project, then **Publish**.
   Or, with the Firebase CLI (`brew install firebase-cli`, then `firebase login`),
   set your project id in [`.firebaserc`](../.firebaserc) and run
   `firebase deploy --only firestore:rules` from the project root.

   These rules let a signed-in user read and write only their own
   `users/{their uid}/...` documents and reject malformed writes. Without them
   (or with test-mode rules) your data is not protected.

## 5. Run the app

```
flutter clean
flutter run
```

Open **Settings -> Cloud sync**. If it says "not set up in this build", the
`google-services.json` is missing or in the wrong folder.

### First device

1. **Sign in with Google.**
2. **Create cloud vault** and enter your master password. The app makes the
   master-password protection of the key stronger first (64 MiB, 3 passes), then
   uploads the encrypted key header and your encrypted records.

### Every other device

1. Install the app and create a vault (any password; you will switch to the
   cloud one) or just set it up normally.
2. **Settings -> Cloud sync -> Sign in with Google** (same account).
3. **Join cloud vault** and enter the master password from the first device.
   This device then uses that master password. Records already on it are kept
   and merged in.

After that, changes sync automatically a few seconds after you save, when you
unlock, and when you tap **Sync now**. Sync only runs while the vault is
unlocked, because the key lives only in memory then.

## iOS (not tested in this project)

1. Firebase console -> **Add app** -> iOS. **Bundle ID:**
   `com.securevault.secureVault` (note: different spelling from Android).
2. Download **GoogleService-Info.plist** and add it to `ios/Runner/` through
   Xcode (check "Copy items if needed", target Runner). It is in `.gitignore`.
3. In `GoogleService-Info.plist` find `REVERSED_CLIENT_ID`. In
   `ios/Runner/Info.plist` add a URL type whose scheme is that value:

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>PASTE_REVERSED_CLIENT_ID_HERE</string></array>
     </dict>
   </array>
   ```
4. Build on a Mac. iOS needs a one-time `pod install` (run by `flutter build ios`).

## Security notes

- **Use a long, unique master password.** The encrypted key header is stored in
  your Google account. Anyone who gets into that account (or the Firebase
  project) could try to guess the master password offline. Argon2id at 64 MiB
  slows that down but cannot save a short password.
- Turn on **2-step verification** for the Google account that owns the project
  and for any account you sign in with.
- `google-services.json` is not a secret (it identifies the project), but you
  can restrict its API key to the app's package name and SHA-1 under
  Google Cloud Console -> APIs & Services -> Credentials.
- Optional hardening: enable **App Check** (Play Integrity) so only your app can
  reach Firestore. This needs extra setup and is not required for the data to
  be safe, because the data is encrypted and the rules are per user.
- Set a **budget alert** in Google Cloud so you are told if usage ever grows.
- To remove your data: **Settings -> Cloud sync -> Turn off sync -> Turn off and
  erase cloud copy**, or delete the user's documents in the console.
- Sync is not a backup. A bug, a bad edit, or deleting the Firebase project can
  lose data. Keep encrypted backups (Settings -> Backup & restore) as well.

## Known limits

- Conflict handling is per record: the newer edit wins; there is no field-level
  merge, and clocks on your devices should be roughly correct.
- Changing the master password on one device does not change it on devices that
  already joined; new devices join with the newest password.
- A malicious or compromised server cannot read or alter records without
  detection, but it can withhold updates or replay an older valid version.
