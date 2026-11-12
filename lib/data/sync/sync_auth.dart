import 'package:firebase_auth/firebase_auth.dart';

class SyncUser {
  const SyncUser({required this.uid, required this.email});
  final String uid;
  final String? email;
}

/// Sign-in used only to identify which cloud account the encrypted data
/// belongs to. It does not unlock anything: the master password does that.
abstract class SyncAuth {
  SyncUser? get currentUser;
  Future<SyncUser> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseSyncAuth implements SyncAuth {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  static SyncUser? _map(User? u) =>
      u == null ? null : SyncUser(uid: u.uid, email: u.email);

  @override
  SyncUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<SyncUser> signInWithGoogle() async {
    final provider = GoogleAuthProvider()..addScope('email');
    final cred = await _auth.signInWithProvider(provider);
    return _map(cred.user)!;
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
