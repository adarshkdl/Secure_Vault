# SecureVault

Offline-first Flutter credential vault, built from the product brief in [claude.md](claude.md).
Version 1 = **Option B**: a local encrypted vault per device, moved between devices with manually
transferred encrypted backup files. No account, no cloud sync, no analytics.

## Run

```bash
flutter pub get
flutter run                 # Android or iOS device/emulator
flutter analyze
flutter test                # unit + widget tests
flutter build apk --debug
```

Requires Flutter 3.47+ (Dart 3.13+). Android `minSdk` is 24 (needed by `local_auth`).

Android toolchain: Gradle 9.7.0, Android Gradle Plugin 9.2.1 with built-in Kotlin
(`android.builtInKotlin=true`), Kotlin 2.4.0, Java/Kotlin bytecode target 17. Builds
with the JDK bundled in current Android Studio (JDK 25); Gradle 9.1+ is needed for
JDK 25. Expect a Flutter warning that `firebase_core`/`firebase_auth` "apply KGP":
their build files only do so when built-in Kotlin is off, so it does not apply here.

## Architecture

```
lib/
  core/          crypto wrapper, validators, lockout policy, password tools, clipboard
  domain/        Category, FieldDef, Credential, VaultData (+ built-in categories, schema migration)
  data/          VaultRepository (encrypted file), BackupService (.svbackup), SettingsStore
  application/   Riverpod providers + VaultController (unlock, lockout, CRUD, biometrics)
  presentation/  screens, widgets, theme, auto-lock / privacy cover
```

Business logic lives in `core/`, `data/` and `application/`; widgets only render state.

## Security design

| Concern | Implementation |
|---|---|
| Encryption at rest | Whole vault (titles, fields, notes) sealed with **AES-256-GCM** (`package:cryptography`). Fresh random 96-bit nonce on every save. |
| Key derivation | **Argon2id** (19 MiB, t=2, p=1, OWASP minimum profile), random 16-byte salt per vault, parameters stored in the file so they can be raised later. Runs in a background isolate. |
| Key hierarchy | Random 256-bit data key, wrapped by the password-derived key. Changing the master password only re-wraps the data key. |
| Master password | Never stored. A wrong password fails GCM authentication of the wrapped key. |
| Unlock rate limit | 3 free attempts, then 30 s doubling up to 1 h. Counter persisted across restarts. |
| Biometrics | Data key stored in Keystore/Keychain (`flutter_secure_storage`, iOS `passcode` accessibility) and released only after a successful `local_auth` prompt. Master password remains the fallback. |
| Search | In-memory only after unlock, over non-sensitive fields. No plaintext index on disk. Secrets are never searched. |
| Backups | Versioned `.svbackup`; separate passphrase -> Argon2id -> AES-256-GCM. Header (version, date, record count) is bound in as AEAD associated data. Created only in encrypted form, verified by decrypting before sharing, temp file deleted afterwards. |
| Restore | Validate structure/version -> decrypt into memory -> show safe metadata -> explicit confirm -> master-password re-auth -> atomic replace. Failure leaves the existing vault untouched. |
| Auto-lock | Inactivity timer, lock on background, privacy cover in the app switcher, all pushed screens popped on lock. |
| Screenshots | Android `FLAG_SECURE`. (iOS: privacy cover only.) |
| Android backup | `allowBackup=false` and data-extraction rules exclude everything. |
| Clipboard | One field at a time; cleared after a configurable delay only if unchanged. |
| Sharing | Field picker (secrets unchecked), live preview, final confirmation dialog, re-auth if secrets are included, then the system share sheet. |
| QR transfer | Offline two-QR handshake: receiver shows a 2-minute offer (ephemeral X25519 public key); sender derives a one-time key (X25519 + HKDF-SHA256), encrypts with AES-256-GCM and shows the result; both show a 6-digit confirmation code; receiver key is single-use and the item is saved only after the user confirms. Max ~700 bytes of selected fields. |

## Known limitations

- Not independently security reviewed. Do not store real high-value secrets before a review.
- Dart cannot guarantee memory zeroisation; key material is wiped best-effort.
- Biometric key is protected by the OS keystore but not bound to a per-use biometric key operation.
- Clipboard auto-clear only runs while the app process is alive.
- Lockout counters live in SharedPreferences, so a rooted device could reset them (the Argon2id cost still applies).
- Recently Deleted keeps records for 30 days inside the encrypted vault.
- No iOS screenshot blocking; iOS has not been built or run in this environment.
- Expiry reminders: in-app only (home card + list) for every date field, window set in Settings (default 30 days). No OS notifications on purpose - they would expose record titles on the lock screen.
- Email accounts: no title box (the address is the title), Personal/Office mail type, provider list with icons, several mobile numbers. IMAP/POP/SMTP and username fields were removed; values saved earlier under those keys are kept but no longer shown.
- Wi-Fi: no title box (the SSID is the title), no router/admin URL, no custom fields. Older records keep any such values but they are no longer shown.
- Website login: no title box (the website name is the title), no recovery field, no custom fields. Older records keep such values but they are no longer shown.
- Look and feel: light theme follows the VaultKeeper mockup (deep-blue headers, white cards, blue buttons); dark theme is the navy glass style. Light is the default for new installs; dark and system remain in Settings. Splash (native + in-app), unlock screen and Home dashboard (stat tiles, Quick Access, Recent Items) follow the mockup. App icon and splash images are rendered from the in-code logo: `flutter test tool/gen_icons_test.dart`, then `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.
- Static IP: no title box (the configuration name is the title), no MAC, VLAN or location fields, no custom fields. Older records keep such values but they are no longer shown.
- Import: Bitwarden JSON/CSV, 1Password, LastPass, Chrome/Edge/Firefox and generic CSV logins, parsed in memory only, re-auth required, duplicates skipped, cached picker copy cleared. Cards, identities and notes are not imported.
- Cloud sync (optional, Firebase): per-record end-to-end encrypted sync. Each record is sealed on the device (AES-256-GCM, key derived from the vault key with HKDF, record id and edit time bound in as associated data) and stored as its own Firestore document; the server sees only ids, edit times, deleted flags and sizes. Google sign-in identifies the account; the master password still unlocks the vault and is never uploaded. Newer edit wins per record, permanent deletes are remembered (tombstones). After a reinstall or on a new phone, **Restore from cloud** on the welcome screen rebuilds the vault from the cloud with the same master password (all records are downloaded and verified before anything is written; never runs over an existing vault). Setup: docs/FIREBASE_SETUP.md; rules: firestore.rules. Needs your own Firebase project; without google-services.json the app runs offline-only.
- Not implemented: field-level merge, App Check, iOS verification of cloud sync.

## Manual test checklist (Android and iOS)

1. First launch -> create vault (weak password rejected, mismatch rejected) -> optional biometric prompt.
2. Add one record per built-in category; static IP rejects `999.1.1.1`, accepts IPv6 and `/64`.
3. Lists/home never show passwords; detail shows `••••` until the eye icon; copy then confirm the clipboard clears.
4. Background the app: app-switcher shows a lock icon (Android: blank/secure). Return after the lock setting -> lock screen.
5. Wrong password x3 -> countdown; kill and relaunch -> still locked out.
6. Create custom category with a sensitive field; add a record.
7. Share a record: secrets unchecked, preview matches what arrives in the target app.
8. Create backup -> receive file on another device -> restore with wrong passphrase (rejected), then correct (shows date + count, asks confirmation and master password).
9. Edit a backup file with a hex editor -> restore must fail. Truncate it -> must fail.
10. Delete a record -> Recently deleted -> restore.
11. Change master password; old one stops working; biometrics still work.
12. Erase vault requires password and typing `ERASE`.
