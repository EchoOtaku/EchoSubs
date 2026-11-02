import '../../core/model/change_batch.dart';
import '../../core/model/errors.dart';
import '../../core/model/ids.dart';
import '../../core/model/ledger.dart';

/// Pure deterministic reconstruction. Transport delivery state is never input.
LedgerProjection materialize(Set<ChangeBatch> batches) =>
    analyzeBatches(batches).projection;

class CausalAnalysis {
  CausalAnalysis(
    this.projection,
    Map<EntityRef, Set<BatchId>> heads,
    Iterable<BatchId> quarantined,
    Iterable<EntityRef> unsafeRefs,
  ) : heads = Map.unmodifiable(
        heads.map((ref, ids) => MapEntry(ref, Set<BatchId>.unmodifiable(ids))),
      ),
      quarantinedBatchIds = Set.unmodifiable(quarantined),
      unsafeRefs = Set.unmodifiable(unsafeRefs);
  final LedgerProjection projection;

  /// Valid, dependency-complete versions, including unresolved conflict heads.
  final Map<EntityRef, Set<BatchId>> heads;
  final Set<BatchId> quarantinedBatchIds;
  final Set<EntityRef> unsafeRefs;

  List<BatchId> parentsFor(EntityRef ref) {
    if (unsafeRefs.contains(ref) ||
        projection.conflicts.any((c) => c.affectedRefs.contains(ref))) {
      throw const EchoFailure('conflict', '记录存在冲突或隔离数据，请先处理');
    }
    return (heads[ref]?.toList() ?? <BatchId>[])..sort();
  }
}

Set<BatchId> _parents(ChangeBatch b) =>
    b.mutations.expand((m) => m.parentBatchIds).toSet();
bool _same(Set<BatchId> a, Iterable<BatchId> b) =>
    a.length == b.length && a.containsAll(b);

CausalAnalysis analyzeBatches(
  Iterable<ChangeBatch> input, {
  Set<BatchId> quarantinedBatchIds = const {},
}) {
  final all = input.toList();
  if (all.map((b) => b.ledgerId).toSet().length > 1) {
    throw const EchoFailure('integrity', '不能合并不同账本');
  }
  final byId = <BatchId, ChangeBatch>{};
  final invalid = {...quarantinedBatchIds};
  for (final b in all) {
    if (byId.containsKey(b.id) && byId[b.id] != b) invalid.add(b.id);
    byId[b.id] = b;
  }
  final pending = <BatchId>{};
  for (final b in byId.values) {
    for (final m in b.mutations) {
      for (final p in m.parentBatchIds) {
        if (!byId.containsKey(p) && !invalid.contains(p)) pending.add(b.id);
        if (byId.containsKey(p) &&
            !byId[p]!.mutations.any((v) => v.ref == m.ref))
          invalid.add(b.id);
      }
    }
  }
  void propagate(Set<BatchId> ids) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final b in byId.values) {
        if (!ids.contains(b.id) && _parents(b).any(ids.contains)) {
          ids.add(b.id);
          changed = true;
        }
      }
    }
  }

  propagate(invalid);
  propagate(pending);
  pending.removeAll(invalid);
  final remaining = byId.keys.toSet().difference(invalid).difference(pending);
  final valid = <BatchId, ChangeBatch>{};
  final ancestors = <BatchId, Set<BatchId>>{};
  final resolutions = <BatchId, Set<BatchId>>{};
  while (remaining.isNotEmpty) {
    final ready =
        remaining
            .where(
              (id) => _parents(byId[id]!).every((p) => !remaining.contains(p)),
            )
            .toList()
          ..sort();
    if (ready.isEmpty) {
      invalid.addAll(remaining);
      break;
    }
    for (final id in ready) {
      remaining.remove(id);
      final b = byId[id]!;
      final parents = _parents(b);
      if (parents.any(invalid.contains)) {
        invalid.add(id);
        continue;
      }
      final past = <BatchId>{
        for (final p in parents) ...{p, ...ancestors[p]!},
      };
      final history = [for (final p in past) valid[p]!];
      final state = _state(history, resolutions);
      var legal = true;
      // A parent denotes a version of this entity; every head visible in this
      // batch's causal past must be named. Unseen future branches stay concurrent.
      for (final m in b.mutations) {
        if (!_same(state.heads[m.ref] ?? {}, m.parentBatchIds)) legal = false;
      }
      final refs = b.mutations.map((m) => m.ref).toSet();
      for (final c in state.conflicts) {
        if (c.affectedRefs.any(refs.contains) &&
            !refs.containsAll(c.affectedRefs))
          legal = false;
      }
      if (!legal) {
        invalid.add(id);
        continue;
      }
      resolutions[id] = {
        for (final c in state.conflicts)
          if (c.affectedRefs.any(refs.contains)) ...c.competingBatchIds,
      };
      ancestors[id] = past;
      valid[id] = b;
    }
  }
  propagate(invalid);
  pending.removeAll(invalid);
  final state = _state(valid.values.toList(), resolutions);
  return CausalAnalysis(
    LedgerProjection(
      entities: state.entities,
      conflicts: state.conflicts,
      pendingBatchIds: pending,
    ),
    state.heads,
    invalid,
    all
        .where((b) => invalid.contains(b.id))
        .expand((b) => b.mutations.map((m) => m.ref)),
  );
}

class _State {
  _State(this.entities, this.heads, this.conflicts);
  final Map<EntityRef, LedgerEntity> entities;
  final Map<EntityRef, Set<BatchId>> heads;
  final List<Conflict> conflicts;
}

Map<EntityRef, Set<BatchId>> _heads(List<ChangeBatch> batches) {
  final versions = <EntityRef, Set<BatchId>>{};
  final retired = <EntityRef, Set<BatchId>>{};
  for (final b in batches) {
    for (final m in b.mutations) {
      versions.putIfAbsent(m.ref, () => {}).add(b.id);
      retired.putIfAbsent(m.ref, () => {}).addAll(m.parentBatchIds);
    }
  }
  for (final ref in versions.keys) {
    versions[ref]!.removeAll(retired[ref]!);
  }
  return versions;
}

/// Remove whole competing batches and all dependants, then repeat: removing a
/// disputed resolution can expose its earlier unresolved competing branches.
_State _state(
  List<ChangeBatch> batches,
  Map<BatchId, Set<BatchId>> resolutions,
) {
  final byId = {for (final b in batches) b.id: b};
  final blocked = <BatchId>{};
  var changed = true;
  while (changed) {
    final before = blocked.length;
    final visible = batches.where((b) => !blocked.contains(b.id)).toList();
    for (final entry in _heads(visible).entries) {
      if (entry.value.length < 2) continue;
      final branches = <Set<BatchId>>[];
      for (final tip in entry.value) {
        final branch = <BatchId>{};
        final todo = [tip];
        while (todo.isNotEmpty) {
          final id = todo.removeLast();
          if (!branch.add(id)) continue;
          todo.addAll(
            byId[id]!.mutations
                .singleWhere((m) => m.ref == entry.key)
                .parentBatchIds,
          );
        }
        branches.add(branch);
      }
      final common = branches.reduce((a, b) => a.intersection(b));
      blocked.addAll(branches.expand((b) => b).toSet().difference(common));
    }
    var grew = true;
    while (grew) {
      grew = false;
      for (final id in blocked.toList()) {
        final before = blocked.length;
        blocked.addAll(resolutions[id] ?? {});
        if (blocked.length != before) grew = true;
      }
      for (final b in batches) {
        if (!blocked.contains(b.id) && _parents(b).any(blocked.contains)) {
          blocked.add(b.id);
          grew = true;
        }
      }
    }
    changed = blocked.length != before;
  }
  // Shared writes and dependency edges join atomic business components.
  final components = <Set<BatchId>>[];
  for (final id in blocked.toList()..sort()) {
    var component = <BatchId>{id};
    final refs = byId[id]!.mutations.map((m) => m.ref).toSet();
    for (var i = components.length - 1; i >= 0; i--) {
      final other = components[i];
      if (other.any(
        (p) =>
            byId[p]!.mutations.any((m) => refs.contains(m.ref)) ||
            _parents(byId[id]!).contains(p) ||
            _parents(byId[p]!).contains(id),
      )) {
        component.addAll(other);
        components.removeAt(i);
      }
    }
    components.add(component);
  }
  final confirmed = batches.where((b) => !blocked.contains(b.id)).toList();
  final entities = <EntityRef, LedgerEntity>{};
  for (final entry in _heads(confirmed).entries) {
    if (entry.value.isEmpty) continue;
    final m = byId[entry.value.single]!.mutations.singleWhere(
      (m) => m.ref == entry.key,
    );
    if (m.value != null) entities[entry.key] = m.value!;
  }
  return _State(entities, _heads(batches), [
    for (final component in components)
      Conflict(
        id: (component.toList()..sort()).first,
        competingBatchIds: component,
        affectedRefs: component.expand(
          (id) => byId[id]!.mutations.map((m) => m.ref),
        ),
      ),
  ]);
}
