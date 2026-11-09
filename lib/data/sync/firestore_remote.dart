import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/crypto/vault_crypto.dart';
import 'sync_models.dart';

/// Firestore implementation of [SyncRemote].
///
/// Layout (all under the signed-in user's own path):
///   users/{uid}/meta/vault   { v, kdf, wrapped, rev }        key header
///   users/{uid}/items/{id}   { v, k, ut, del, n, ct, mac, st } one encrypted item
///
/// Readable by the server: item id (random UUID), kind, edit time, deleted
/// flag, write time, and the size of each ciphertext. Everything else is
/// ciphertext. See firestore.rules for the access rules.
class FirestoreSyncRemote implements SyncRemote {
  FirestoreSyncRemote(this.uid, [FirebaseFirestore? db])
    : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  static const _pageSize = 300;
  static const _batchSize = 400;

  DocumentReference<Map<String, dynamic>> get _header =>
      _db.doc('users/$uid/meta/vault');
  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('users/$uid/items');

  static String _b64(List<int> b) => base64Encode(b);

  @override
  Future<RemoteHeader?> getHeader() async {
    final snap = await _header.get();
    final d = snap.data();
    if (d == null) return null;
    try {
      return RemoteHeader(
        kdf: KdfParams.fromJson(Map<String, dynamic>.from(d['kdf'] as Map)),
        wrapped: Sealed.fromJson(
          Map<String, dynamic>.from(d['wrapped'] as Map),
        ),
        rev: d['rev'] as int? ?? 1,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> putHeader(RemoteHeader h) => _header.set({
    'v': 1,
    'kdf': h.kdf.toJson(),
    'wrapped': h.wrapped.toJson(),
    'rev': h.rev,
    'st': FieldValue.serverTimestamp(),
  });

  RemoteItem? _parse(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final kind = SyncKind.fromCode(d['k'] as String?);
    final ut = d['ut'];
    if (kind == null || ut is! int) return null;
    try {
      return RemoteItem(
        id: doc.id,
        kind: kind,
        ut: ut,
        deleted: d['del'] == true,
        sealed: Sealed(
          base64Decode(d['n'] as String),
          base64Decode(d['ct'] as String),
          base64Decode(d['mac'] as String),
        ),
        serverTime: (d['st'] as Timestamp?)?.toDate(),
      );
    } on Object {
      return null; // malformed document: ignored, never crashes a sync
    }
  }

  @override
  Future<List<RemoteItem>> fetchChanged(DateTime? since) async {
    Query<Map<String, dynamic>> q = _items.orderBy('st');
    if (since != null) {
      q = q.where('st', isGreaterThan: Timestamp.fromDate(since));
    }
    final out = <RemoteItem>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      var page = q.limit(_pageSize);
      if (last != null) page = page.startAfterDocument(last);
      final snap = await page.get();
      for (final doc in snap.docs) {
        final r = _parse(doc);
        if (r != null) out.add(r);
      }
      if (snap.docs.length < _pageSize) break;
      last = snap.docs.last;
    }
    return out;
  }

  @override
  Future<void> pushItems(List<RemoteItem> items) async {
    for (var i = 0; i < items.length; i += _batchSize) {
      final batch = _db.batch();
      for (final r in items.skip(i).take(_batchSize)) {
        batch.set(_items.doc(r.id), {
          'v': 1,
          'k': r.kind.code,
          'ut': r.ut,
          'del': r.deleted,
          'n': _b64(r.sealed.nonce),
          'ct': _b64(r.sealed.cipherText),
          'mac': _b64(r.sealed.mac),
          'st': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<void> deleteEverything() async {
    while (true) {
      final snap = await _items.limit(_batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await _header.delete();
  }
}
