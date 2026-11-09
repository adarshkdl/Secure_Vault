import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/providers.dart';
import 'package:secure_vault/application/sync_controller.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/data/sync/sync_auth.dart';
import 'package:secure_vault/data/sync/sync_engine.dart';
import 'package:secure_vault/data/sync/sync_state_prefs.dart';
import 'package:secure_vault/data/vault_repository.dart';
import 'package:secure_vault/domain/credential.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_test.dart' show FakeRemote;

// Synthetic data only.

class FakeAuth implements SyncAuth {
  SyncUser? user;
  @override
  SyncUser? get currentUser => user;
  @override
  Future<SyncUser> signInWithGoogle() async =>
      user = const SyncUser(uid: 'user-1', email: 'demo@example.test');
  @override
  Future<void> signOut() async => user = null;
}

/// Per-device sync bookkeeping in memory (SharedPreferences is a singleton).
class MemSyncStore extends PrefsSyncStateStore {
  MemSyncStore(super.p);
  String? _uid;
  final _m = <String, SyncState>{};
  @override
  String? get enabledUid => _uid;
  @override
  Future<void> setEnabledUid(String? uid) async => _uid = uid;
  @override
  SyncState load(String uid) => _m[uid] ?? const SyncState();
  @override
  Future<void> save(String uid, SyncState s) async => _m[uid] = s;
  @override
  Future<void> clear(String uid) async => _m.remove(uid);
}

Credential cred(String id, String title) {
  final t = DateTime.now();
  return Credential(
    id: id,
    categoryId: 'account',
    title: title,
    values: {'password': 'synthetic-$id'},
    createdAt: t,
    updatedAt: t,
  );
}

Future<ProviderContainer> device(
  SharedPreferences prefs,
  FakeRemote remote,
  FakeAuth auth,
) async {
  final dir = await Directory.systemTemp.createTemp('sv_sync');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // temp dir only
    }
  });
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      vaultDirProvider.overrideWithValue(dir),
      repositoryProvider.overrideWith(
        (ref) => VaultRepository(
          dir,
          kdfFactory: () => KdfParams.fresh(memoryKiB: 64, iterations: 1),
        ),
      ),
      firebaseReadyProvider.overrideWithValue(true),
      syncAuthProvider.overrideWithValue(auth),
      syncRemoteFactoryProvider.overrideWithValue((_) => remote),
      syncStoreProvider.overrideWithValue(MemSyncStore(prefs)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  late SharedPreferences prefs;
  late FakeRemote remote;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    remote = FakeRemote();
  });

  test('device A creates the cloud vault; device B joins and merges', () async {
    const pwA = 'Synthetic-Pass-A-1234!';
    const pwB = 'Synthetic-Pass-B-5678!';

    // --- Device A -----------------------------------------------------------
    final a = await device(prefs, remote, FakeAuth());
    final av = a.read(vaultProvider.notifier);
    await av.createVault(pwA);
    await av.saveCredential(cred('a1', 'Mail from A'));
    final async = a.read(syncControllerProvider.notifier);
    await async.signIn();
    expect(a.read(syncControllerProvider).phase, SyncPhase.needsSetup);

    expect(await async.createCloudVault('wrong-password-xx'), isNotNull);
    expect(await async.createCloudVault(pwA), isNull);
    expect(a.read(syncControllerProvider).phase, SyncPhase.ready);
    expect(remote.header, isNotNull);
    expect(remote.items.keys, contains('a1'));
    // The cloud header uses the stronger key-stretching settings.
    expect(remote.header!.kdf.memoryKiB, KdfParams.cloudMemoryKiB);
    // Nothing readable in the cloud.
    expect(
      remote.items.values.map((i) => i.sealed.toJson().toString()).join(),
      isNot(contains('Mail from A')),
    );

    // --- Device B (its own vault, own password, own record) -----------------
    final b = await device(prefs, remote, FakeAuth());
    final bv = b.read(vaultProvider.notifier);
    await bv.createVault(pwB);
    await bv.saveCredential(cred('b1', 'Wifi from B'));
    final bsync = b.read(syncControllerProvider.notifier);
    await bsync.signIn();
    expect(b.read(syncControllerProvider).phase, SyncPhase.needsJoin);

    // Wrong cloud password is rejected and changes nothing.
    expect(await bsync.joinCloudVault(pwB), isNotNull);
    expect(b.read(vaultProvider).data!.credentials.single.id, 'b1');

    expect(await bsync.joinCloudVault(pwA), isNull);
    final bTitles = b
        .read(vaultProvider)
        .data!
        .credentials
        .map((c) => c.title)
        .toSet();
    expect(bTitles, {'Mail from A', 'Wifi from B'}); // merged, nothing lost
    expect(b.read(syncControllerProvider).phase, SyncPhase.ready);

    // B now shares A's data key and uses the cloud master password.
    expect(bv.syncKeys()!.dek, av.syncKeys()!.dek);
    bv.lock();
    expect(await bv.unlock(pwB), UnlockResult.wrongPassword);
    expect(await bv.unlock(pwA), UnlockResult.ok);
    expect(b.read(vaultProvider).data!.credentials.map((c) => c.id).toSet(), {
      'a1',
      'b1',
    });

    // --- A receives B's record ---------------------------------------------
    await async.syncNow();
    expect(a.read(vaultProvider).data!.credentials.map((c) => c.id).toSet(), {
      'a1',
      'b1',
    });
  });

  test('a permanent delete on one device removes it on the other', () async {
    const pw = 'Synthetic-Pass-Same-1!';
    final a = await device(prefs, remote, FakeAuth());
    final av = a.read(vaultProvider.notifier);
    await av.createVault(pw);
    await av.saveCredential(cred('x1', 'Delete me'));
    final asc = a.read(syncControllerProvider.notifier);
    await asc.signIn();
    await asc.createCloudVault(pw);

    final b = await device(prefs, remote, FakeAuth());
    final bv = b.read(vaultProvider.notifier);
    await bv.createVault('Synthetic-Pass-Other-2!');
    final bsc = b.read(syncControllerProvider.notifier);
    await bsc.signIn();
    await bsc.joinCloudVault(pw);
    expect(b.read(vaultProvider).data!.credentials.map((c) => c.id), ['x1']);

    await av.softDelete('x1');
    await av.deleteForever('x1');
    expect(a.read(vaultProvider).data!.tombstones.containsKey('x1'), isTrue);
    await asc.syncNow();
    await bsc.syncNow();
    expect(b.read(vaultProvider).data!.credentials, isEmpty);
    // And it stays gone after another round.
    await bsc.syncNow();
    await asc.syncNow();
    expect(a.read(vaultProvider).data!.credentials, isEmpty);
  });

  test('turning sync off can erase the cloud copy', () async {
    const pw = 'Synthetic-Pass-Off-3!';
    final a = await device(prefs, remote, FakeAuth());
    final av = a.read(vaultProvider.notifier);
    await av.createVault(pw);
    await av.saveCredential(cred('z1', 'Temp'));
    final asc = a.read(syncControllerProvider.notifier);
    await asc.signIn();
    await asc.createCloudVault(pw);
    expect(remote.items, isNotEmpty);
    await asc.disable(deleteCloud: true);
    expect(remote.items, isEmpty);
    expect(remote.header, isNull);
    expect(a.read(syncControllerProvider).phase, SyncPhase.signedOut);
    // Local data is untouched.
    expect(a.read(vaultProvider).data!.credentials.single.id, 'z1');
  });
}
