import 'errors.dart';
import 'ids.dart';
import 'ledger.dart';

class EntityRef extends ModelValue implements Comparable<EntityRef> {
  EntityRef(this.kind, this.id) {
    validateId(id);
  }
  final EntityKind kind;
  final EntityId id;
  factory EntityRef.fromJson(Map<String, dynamic> value) => parseModel(
    () => EntityRef(
      enumValue(EntityKind.values, value['kind']),
      value['id'] as String,
    ),
  );
  @override
  Map<String, Object?> toJson() => {'kind': kind.name, 'id': id};
  @override
  int compareTo(EntityRef other) {
    final kinds = kind.name.compareTo(other.kind.name);
    return kinds == 0 ? id.compareTo(other.id) : kinds;
  }
}

class Mutation extends ModelValue {
  Mutation(this.ref, Iterable<BatchId> parentBatchIds, this.value)
    : parentBatchIds = immutableIds(parentBatchIds) {
    if (value != null && (value!.kind != ref.kind || value!.id != ref.id))
      invalidModel();
  }
  final EntityRef ref;
  final List<BatchId> parentBatchIds;
  final LedgerEntity? value;
  factory Mutation.fromJson(Map<String, dynamic> json) => parseModel(() {
    final ref = EntityRef.fromJson(jsonMap(json['ref']));
    return Mutation(
      ref,
      jsonList(json['parentBatchIds']).cast<String>(),
      json['value'] == null
          ? null
          : LedgerEntity.fromJson(ref.kind, jsonMap(json['value'])),
    );
  });
  @override
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'parentBatchIds': parentBatchIds,
    'value': value?.toJson(),
  };
}

class ChangeBatch extends ModelValue {
  ChangeBatch({
    required this.id,
    required this.ledgerId,
    required this.deviceId,
    required this.createdAtUtc,
    required Iterable<Mutation> mutations,
  }) : mutations = List.unmodifiable(
         mutations.toList()..sort((a, b) => a.ref.compareTo(b.ref)),
       ) {
    validateId(id);
    validateId(ledgerId);
    validateId(deviceId);
    if (!createdAtUtc.isUtc ||
        this.mutations.isEmpty ||
        this.mutations.map((mutation) => mutation.ref).toSet().length !=
            this.mutations.length ||
        this.mutations.any((mutation) => mutation.parentBatchIds.contains(id)))
      invalidModel();
  }
  final BatchId id;
  final LedgerId ledgerId;
  final DeviceId deviceId;
  final DateTime createdAtUtc;
  final List<Mutation> mutations;
  factory ChangeBatch.fromJson(Map<String, dynamic> value) => parseModel(
    () => ChangeBatch(
      id: value['id'] as String,
      ledgerId: value['ledgerId'] as String,
      deviceId: value['deviceId'] as String,
      createdAtUtc: DateTime.parse(value['createdAtUtc'] as String),
      mutations: jsonList(
        value['mutations'],
      ).map((mutation) => Mutation.fromJson(jsonMap(mutation))),
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'ledgerId': ledgerId,
    'deviceId': deviceId,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'mutations': mutations.map((mutation) => mutation.toJson()).toList(),
  };
}

List<EntityRef> _refs(Iterable<EntityRef> values) =>
    List.unmodifiable(values.toSet().toList()..sort());

class Conflict extends ModelValue {
  Conflict({
    required this.id,
    required Iterable<BatchId> competingBatchIds,
    required Iterable<EntityRef> affectedRefs,
  }) : competingBatchIds = immutableIds(competingBatchIds),
       affectedRefs = _refs(affectedRefs) {
    validateId(id);
    if (this.competingBatchIds.length < 2 || this.affectedRefs.isEmpty)
      invalidModel();
  }
  final String id;
  final List<BatchId> competingBatchIds;
  final List<EntityRef> affectedRefs;
  factory Conflict.fromJson(Map<String, dynamic> value) => parseModel(
    () => Conflict(
      id: value['id'] as String,
      competingBatchIds: jsonList(value['competingBatchIds']).cast<String>(),
      affectedRefs: jsonList(
        value['affectedRefs'],
      ).map((ref) => EntityRef.fromJson(jsonMap(ref))),
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'competingBatchIds': competingBatchIds,
    'affectedRefs': affectedRefs.map((ref) => ref.toJson()).toList(),
  };
}

class LedgerProjection extends ModelValue {
  LedgerProjection({
    Map<EntityRef, LedgerEntity> entities = const {},
    Iterable<Conflict> conflicts = const [],
    Iterable<BatchId> pendingBatchIds = const [],
  }) : entities = Map.unmodifiable(entities),
       conflicts = List.unmodifiable(
         conflicts.toList()..sort((a, b) => a.id.compareTo(b.id)),
       ),
       pendingBatchIds = immutableIds(pendingBatchIds) {
    for (final entry in this.entities.entries) {
      if (entry.key.id != entry.value.id || entry.key.kind != entry.value.kind)
        invalidModel();
    }
    if (this.conflicts.map((conflict) => conflict.id).toSet().length !=
        this.conflicts.length)
      invalidModel();
  }
  final Map<EntityRef, LedgerEntity> entities;
  final List<Conflict> conflicts;
  final List<BatchId> pendingBatchIds;
  factory LedgerProjection.fromJson(Map<String, dynamic> value) =>
      parseModel(() {
        final entities = <EntityRef, LedgerEntity>{};
        for (final item in jsonList(value['entities'])) {
          final entry = jsonMap(item);
          final ref = EntityRef.fromJson(jsonMap(entry['ref']));
          if (entities.containsKey(ref)) invalidModel();
          entities[ref] = LedgerEntity.fromJson(
            ref.kind,
            jsonMap(entry['value']),
          );
        }
        return LedgerProjection(
          entities: entities,
          conflicts: jsonList(
            value['conflicts'],
          ).map((conflict) => Conflict.fromJson(jsonMap(conflict))),
          pendingBatchIds: jsonList(value['pendingBatchIds']).cast<String>(),
        );
      });
  @override
  Map<String, Object?> toJson() {
    final refs = entities.keys.toList()..sort();
    return {
      'entities': [
        for (final ref in refs)
          {'ref': ref.toJson(), 'value': entities[ref]!.toJson()},
      ],
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
      'pendingBatchIds': pendingBatchIds,
    };
  }
}
