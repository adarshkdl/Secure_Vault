import '../../domain/builtin_categories.dart';
import '../../domain/category.dart';
import '../../domain/credential.dart';
import '../../domain/vault_data.dart';
import 'sync_models.dart';

class MergeOutcome {
  const MergeOutcome({
    required this.merged,
    required this.toPush,
    required this.inSync,
    required this.changed,
    required this.applied,
    required this.rejected,
  });

  /// The vault after applying every remote change that won.
  final VaultData merged;

  /// Local versions the cloud does not have yet.
  final List<SyncItem> toPush;

  /// id -> edit time for items now known to match the cloud.
  final Map<String, int> inSync;

  /// Whether [merged] differs from the local input.
  final bool changed;
  final int applied;

  /// Remote items that could not be decoded into a record.
  final int rejected;
}

/// Pure per-record merge: for every id the version with the newer edit time
/// wins. On a tie a deletion wins over a live copy; between two live copies
/// the local one stays. A permanent deletion is a tombstone, so a deleted item
/// is not brought back by a device that still has it, unless that device edits
/// it after the deletion.
///
/// [pushed] is what this device last uploaded (id -> edit time). A local item
/// whose edit time differs from it is "dirty" and goes into [MergeOutcome.toPush].
MergeOutcome mergeSync({
  required VaultData local,
  required List<SyncItem> remote,
  required Map<String, int> pushed,
  DateTime? now,
}) {
  final creds = {for (final c in local.credentials) c.id: c};
  final cats = {for (final c in local.customCategories) c.id: c};
  final tombs = Map<String, DateTime>.of(local.tombstones);
  final order = [
    ...local.credentials.map((c) => c.id),
    ...local.customCategories.map((c) => c.id),
  ];

  int? localUt(String id) {
    final c = creds[id];
    if (c != null) return ms(c.updatedAt);
    final k = cats[id];
    if (k != null) return k.updatedAt == null ? 0 : ms(k.updatedAt!);
    final t = tombs[id];
    return t == null ? null : ms(t);
  }

  bool localLive(String id) => creds.containsKey(id) || cats.containsKey(id);

  // Keep only the newest remote version of each id.
  final newest = <String, SyncItem>{};
  for (final r in remote) {
    final cur = newest[r.id];
    if (cur == null || r.ut > cur.ut) newest[r.id] = r;
  }

  final inSync = <String, int>{};
  var applied = 0, rejected = 0;
  var mutated = false; // anything in the merged vault differs from local

  for (final r in newest.values) {
    final lu = localUt(r.id);
    final bool remoteWins;
    if (lu == null) {
      remoteWins = true;
    } else if (r.ut != lu) {
      remoteWins = r.ut > lu;
    } else {
      // Same edit time. A deletion beats a live copy; otherwise already equal.
      remoteWins = r.deleted && localLive(r.id);
      if (!remoteWins) inSync[r.id] = r.ut;
    }
    if (!remoteWins) continue;

    if (r.deleted) {
      if (creds.remove(r.id) != null || cats.remove(r.id) != null) applied++;
      tombs[r.id] = r.updatedAt;
      inSync[r.id] = r.ut;
      mutated = true;
      continue;
    }
    try {
      if (r.kind == SyncKind.credential) {
        final c = Credential.fromJson(r.json!);
        if (c.id != r.id) throw const FormatException();
        creds[r.id] = c;
      } else {
        final k = Category.fromJson(r.json!);
        if (k.id != r.id) throw const FormatException();
        cats[r.id] = k;
      }
    } on Object {
      rejected++;
      continue;
    }
    tombs.remove(r.id);
    if (!order.contains(r.id)) order.add(r.id);
    inSync[r.id] = r.ut;
    applied++;
    mutated = true;
  }

  // A record whose custom category was deleted elsewhere moves to "account"
  // so it never points at a category that no longer exists.
  final builtIn = builtInCategories.map((c) => c.id).toSet();
  var orphans = 0;
  final t = now ?? DateTime.now();
  for (final e in creds.entries.toList()) {
    final cid = e.value.categoryId;
    if (!builtIn.contains(cid) && !cats.containsKey(cid)) {
      creds[e.key] = e.value.copyWith(categoryId: 'account', updatedAt: t);
      orphans++;
    }
  }

  final merged = VaultData(
    credentials: [
      for (final id in order)
        if (creds[id] != null) creds[id]!,
    ],
    customCategories: [
      for (final id in order)
        if (cats[id] != null) cats[id]!,
    ],
    tombstones: tombs,
  );

  // Everything the cloud may lack: dirty live items and tombstones.
  final toPush = <SyncItem>[];
  bool dirty(String id, int ut) => pushed[id] != ut && inSync[id] != ut;
  for (final c in merged.credentials) {
    if (dirty(c.id, ms(c.updatedAt))) {
      toPush.add(
        SyncItem(
          id: c.id,
          kind: SyncKind.credential,
          updatedAt: c.updatedAt,
          json: c.toJson(),
        ),
      );
    }
  }
  for (final k in merged.customCategories) {
    final u = k.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (dirty(k.id, ms(u))) {
      toPush.add(
        SyncItem(
          id: k.id,
          kind: SyncKind.category,
          updatedAt: u,
          json: k.toJson(),
        ),
      );
    }
  }
  for (final e in tombs.entries) {
    if (dirty(e.key, ms(e.value))) {
      // Kind is not known for a tombstone; the receiver only needs the id.
      toPush.add(
        SyncItem(id: e.key, kind: SyncKind.credential, updatedAt: e.value),
      );
    }
  }

  return MergeOutcome(
    merged: merged,
    toPush: toPush,
    inSync: inSync,
    changed: mutated || orphans > 0,
    applied: applied,
    rejected: rejected,
  );
}
