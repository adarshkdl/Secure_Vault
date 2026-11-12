import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/data/sync/sync_crypto.dart';
import 'package:secure_vault/data/sync/sync_engine.dart';
import 'package:secure_vault/data/sync/sync_models.dart';
import 'package:secure_vault/domain/category.dart';
import 'package:secure_vault/domain/credential.dart';
import 'package:secure_vault/domain/vault_data.dart';

// Synthetic data only.

class FakeRemote implements SyncRemote {
  RemoteHeader? header;
  final items = <String, RemoteItem>{};
  var _clock = 0;

  @override
  Future<RemoteHeader?> getHeader() async => header;
  @override
  Future<void> putHeader(RemoteHeader h) async => header = h;

  @override
  Future<List<RemoteItem>> fetchChanged(DateTime? since) async => [
    for (final i in items.values)
      if (since == null || i.serverTime!.isAfter(since)) i,
  ];

  @override
  Future<void> pushItems(List<RemoteItem> list) async {
    for (final i in list) {
      items[i.id] = RemoteItem(
        id: i.id,
        kind: i.kind,
        ut: i.ut,
        deleted: i.deleted,
        sealed: i.sealed,
        serverTime: DateTime(2030).add(Duration(seconds: ++_clock)),
      );
    }
  }

  @override
  Future<void> deleteEverything() async {
    items.clear();
    header = null;
  }
}

class MemStore implements SyncStateStore {
  final _m = <String, SyncState>{};
  @override
  SyncState load(String uid) => _m[uid] ?? const SyncState();
  @override
  Future<void> save(String uid, SyncState s) async => _m[uid] = s;
  @override
  Future<void> clear(String uid) async => _m.remove(uid);
}

class Device {
  Device(this.remote, this.dek, {String uid = 'user1'})
    : engine = SyncEngine(remote: remote, store: MemStore(), uid: uid);
  final FakeRemote remote;
  final List<int> dek;
  final SyncEngine engine;
  VaultData data = VaultData();

  Future<SyncRun> sync({bool commit = true}) async {
    final run = await engine.run(data, dek);
    data = run.merged;
    if (commit) await run.commit();
    return run;
  }

  Credential? find(String id) =>
      data.credentials.where((c) => c.id == id).firstOrNull;
}

final _t0 = DateTime(2030, 1, 1, 12);
Credential cred(
  String id,
  String title,
  int minute, {
  String cat = 'account',
  DateTime? deleted,
}) => Credential(
  id: id,
  categoryId: cat,
  title: title,
  values: {'password': 'synthetic-$id'},
  createdAt: _t0,
  updatedAt: _t0.add(Duration(minutes: minute)),
  deletedAt: deleted,
);

void main() {
  late FakeRemote remote;
  late List<int> dek;
  late Device a, b;

  setUp(() {
    remote = FakeRemote();
    dek = VaultCrypto.newKey();
    a = Device(remote, dek);
    b = Device(remote, dek);
  });

  test('records created on one device appear on the other', () async {
    a.data.credentials.add(cred('1', 'Mail', 1));
    await a.sync();
    await b.sync();
    expect(b.find('1')?.title, 'Mail');
    expect(b.find('1')?.values['password'], 'synthetic-1');
  });

  test('second sync is a no-op (nothing pushed, nothing applied)', () async {
    a.data.credentials.add(cred('1', 'Mail', 1));
    await a.sync();
    final r = await a.sync();
    expect(r.report.pushed, 0);
    expect(r.report.applied, 0);
    final rb = await b.sync();
    expect(rb.report.applied, 1);
    final rb2 = await b.sync();
    expect(rb2.report.pushed, 0);
    expect(rb2.report.applied, 0);
  });

  test('concurrent edits: the newer edit wins on both devices', () async {
    a.data.credentials.add(cred('1', 'v0', 1));
    await a.sync();
    await b.sync();
    a.data.credentials[0] = cred('1', 'edited on A', 10);
    b.find('1');
    b.data.credentials[0] = cred('1', 'edited on B later', 20);
    await a.sync(); // A uploads its edit
    await b.sync(); // B has the newer edit: keeps it and uploads
    await a.sync(); // A receives B's edit
    expect(a.find('1')!.title, 'edited on B later');
    expect(b.find('1')!.title, 'edited on B later');
  });

  test('independent edits to different records are both kept', () async {
    a.data.credentials
      ..add(cred('1', 'one', 1))
      ..add(cred('2', 'two', 1));
    await a.sync();
    await b.sync();
    a.data.credentials[0] = cred('1', 'one (A)', 5);
    b.data.credentials[1] = cred('2', 'two (B)', 6);
    await a.sync();
    await b.sync();
    await a.sync();
    for (final d in [a, b]) {
      expect(d.find('1')!.title, 'one (A)');
      expect(d.find('2')!.title, 'two (B)');
    }
  });

  test('permanent delete propagates and does not come back', () async {
    a.data.credentials.add(cred('1', 'gone', 1));
    await a.sync();
    await b.sync();
    a.data.credentials.clear();
    a.data.tombstones['1'] = _t0.add(const Duration(minutes: 30));
    await a.sync();
    await b.sync();
    expect(b.find('1'), isNull);
    // B syncing again must not resurrect it on A.
    await b.sync();
    await a.sync();
    expect(a.find('1'), isNull);
    expect(b.data.tombstones.containsKey('1'), isTrue);
  });

  test('an edit made after a remote deletion brings the record back', () async {
    a.data.credentials.add(cred('1', 'keep me', 1));
    await a.sync();
    await b.sync();
    a.data.credentials.clear();
    a.data.tombstones['1'] = _t0.add(const Duration(minutes: 30));
    await a.sync();
    b.data.credentials[0] = cred('1', 'edited later', 60); // after deletion
    await b.sync();
    await a.sync();
    expect(a.find('1')!.title, 'edited later');
    expect(a.data.tombstones.containsKey('1'), isFalse);
  });

  test('soft delete (Recently Deleted) syncs as a normal edit', () async {
    a.data.credentials.add(cred('1', 'trash me', 1));
    await a.sync();
    await b.sync();
    a.data.credentials[0] = cred(
      '1',
      'trash me',
      9,
      deleted: _t0.add(const Duration(minutes: 9)),
    );
    await a.sync();
    await b.sync();
    expect(b.find('1')!.isDeleted, isTrue);
  });

  test('custom categories sync; orphaned records move to Account', () async {
    final k = Category(
      id: 'k1',
      name: 'Gym',
      iconKey: 'folder',
      colorKey: 'blue',
      fields: const [],
      updatedAt: _t0,
    );
    a.data.customCategories.add(k);
    a.data.credentials.add(cred('1', 'locker', 2, cat: 'k1'));
    await a.sync();
    await b.sync();
    expect(b.data.customCategories.single.name, 'Gym');
    expect(b.find('1')!.categoryId, 'k1');

    // A deletes the category (after moving nothing); B adds a record in it.
    a.data.credentials.clear();
    a.data.tombstones['1'] = _t0.add(const Duration(minutes: 3));
    a.data.customCategories.clear();
    a.data.tombstones['k1'] = _t0.add(const Duration(minutes: 3));
    b.data.credentials.add(cred('2', 'new in gym', 4, cat: 'k1'));
    await a.sync();
    await b.sync();
    expect(b.data.customCategories, isEmpty);
    expect(
      b.find('2')!.categoryId,
      'account',
    ); // never points at a gone category
  });

  test('nothing readable by the server: no titles or passwords', () async {
    a.data.credentials.add(cred('1', 'My Secret Bank Login', 1));
    await a.sync();
    final text = remote.items.values
        .map((i) => jsonEncode(i.sealed.toJson()) + i.id + i.kind.code)
        .join();
    expect(text.contains('Secret Bank'), isFalse);
    expect(text.contains('synthetic-1'), isFalse);
    // The plaintext of the cipher blob is not valid JSON either.
    final raw = base64Decode(
      jsonDecode(jsonEncode(remote.items['1']!.sealed.toJson()))['ct']
          as String,
    );
    expect(
      () => jsonDecode(utf8.decode(raw, allowMalformed: true)),
      throwsA(anything),
    );
  });

  test('ciphertext moved to another item id is rejected', () async {
    a.data.credentials
      ..add(cred('1', 'one', 1))
      ..add(cred('2', 'two', 1));
    await a.sync();
    final one = remote.items['1']!;
    remote.items['2'] = RemoteItem(
      id: '2',
      kind: one.kind,
      ut: one.ut,
      deleted: one.deleted,
      sealed: one.sealed,
      serverTime: DateTime(2031),
    );
    final r = await b.sync();
    expect(r.report.rejected, 1);
    expect(b.find('2'), isNull);
    expect(b.find('1')!.title, 'one');
  });

  test('a changed edit time on the server is detected', () async {
    a.data.credentials.add(cred('1', 'one', 1));
    await a.sync();
    final x = remote.items['1']!;
    remote.items['1'] = RemoteItem(
      id: '1',
      kind: x.kind,
      ut: x.ut + 5000,
      deleted: x.deleted,
      sealed: x.sealed,
      serverTime: DateTime(2031),
    );
    final r = await b.sync();
    expect(r.report.rejected, 1);
    expect(b.find('1'), isNull);
  });

  test(
    'a device with a different key rejects everything and keeps its data',
    () async {
      a.data.credentials.add(cred('1', 'one', 1));
      await a.sync();
      final other = Device(remote, VaultCrypto.newKey());
      other.data.credentials.add(cred('9', 'mine', 1));
      final r = await other.sync();
      expect(r.report.rejected, 1);
      expect(other.find('9')!.title, 'mine');
      expect(other.find('1'), isNull);
    },
  );

  test(
    'state is only saved on commit, so a failed local save loses nothing',
    () async {
      a.data.credentials.add(cred('1', 'one', 1));
      await a.sync();
      final before = b.data;
      final r1 = await b.sync(commit: false); // pretend the local save failed
      expect(r1.report.applied, 1);
      b.data = before; // local vault unchanged
      final r2 = await b.sync(); // the next pass must fetch it again
      expect(r2.report.applied, 1);
      expect(b.find('1')!.title, 'one');
    },
  );

  test('accounts are isolated by the bound account id', () async {
    a.data.credentials.add(cred('1', 'one', 1));
    await a.sync();
    final intruder = Device(remote, dek, uid: 'someone-else');
    final r = await intruder.sync();
    expect(r.report.rejected, 1);
    expect(intruder.find('1'), isNull);
  });

  test('sync key is derived, not the vault key', () async {
    final k = await SyncCrypto.deriveKey(dek);
    expect(k, isNot(dek));
    expect(k.length, 32);
  });
}
