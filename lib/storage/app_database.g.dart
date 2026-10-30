// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LedgerRecordsTable extends LedgerRecords
    with TableInfo<$LedgerRecordsTable, LedgerRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<Uint8List> metadata = GeneratedColumn<Uint8List>(
    'metadata',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ledgerId, metadata];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LedgerRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    } else if (isInserting) {
      context.missing(_metadataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId};
  @override
  LedgerRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerRecord(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}metadata'],
      )!,
    );
  }

  @override
  $LedgerRecordsTable createAlias(String alias) {
    return $LedgerRecordsTable(attachedDatabase, alias);
  }
}

class LedgerRecord extends DataClass implements Insertable<LedgerRecord> {
  final String ledgerId;
  final Uint8List metadata;
  const LedgerRecord({required this.ledgerId, required this.metadata});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['metadata'] = Variable<Uint8List>(metadata);
    return map;
  }

  LedgerRecordsCompanion toCompanion(bool nullToAbsent) {
    return LedgerRecordsCompanion(
      ledgerId: Value(ledgerId),
      metadata: Value(metadata),
    );
  }

  factory LedgerRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerRecord(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      metadata: serializer.fromJson<Uint8List>(json['metadata']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'metadata': serializer.toJson<Uint8List>(metadata),
    };
  }

  LedgerRecord copyWith({String? ledgerId, Uint8List? metadata}) =>
      LedgerRecord(
        ledgerId: ledgerId ?? this.ledgerId,
        metadata: metadata ?? this.metadata,
      );
  LedgerRecord copyWithCompanion(LedgerRecordsCompanion data) {
    return LedgerRecord(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerRecord(')
          ..write('ledgerId: $ledgerId, ')
          ..write('metadata: $metadata')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, $driftBlobEquality.hash(metadata));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerRecord &&
          other.ledgerId == this.ledgerId &&
          $driftBlobEquality.equals(other.metadata, this.metadata));
}

class LedgerRecordsCompanion extends UpdateCompanion<LedgerRecord> {
  final Value<String> ledgerId;
  final Value<Uint8List> metadata;
  final Value<int> rowid;
  const LedgerRecordsCompanion({
    this.ledgerId = const Value.absent(),
    this.metadata = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgerRecordsCompanion.insert({
    required String ledgerId,
    required Uint8List metadata,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       metadata = Value(metadata);
  static Insertable<LedgerRecord> custom({
    Expression<String>? ledgerId,
    Expression<Uint8List>? metadata,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (metadata != null) 'metadata': metadata,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgerRecordsCompanion copyWith({
    Value<String>? ledgerId,
    Value<Uint8List>? metadata,
    Value<int>? rowid,
  }) {
    return LedgerRecordsCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      metadata: metadata ?? this.metadata,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<Uint8List>(metadata.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerRecordsCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('metadata: $metadata, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntityVersionsTable extends EntityVersions
    with TableInfo<$EntityVersionsTable, EntityVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntityVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ledgerId,
    kind,
    entityId,
    batchId,
    valueJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entity_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntityVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, kind, entityId, batchId};
  @override
  EntityVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntityVersion(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      ),
    );
  }

  @override
  $EntityVersionsTable createAlias(String alias) {
    return $EntityVersionsTable(attachedDatabase, alias);
  }
}

class EntityVersion extends DataClass implements Insertable<EntityVersion> {
  final String ledgerId;
  final String kind;
  final String entityId;
  final String batchId;
  final String? valueJson;
  const EntityVersion({
    required this.ledgerId,
    required this.kind,
    required this.entityId,
    required this.batchId,
    this.valueJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['kind'] = Variable<String>(kind);
    map['entity_id'] = Variable<String>(entityId);
    map['batch_id'] = Variable<String>(batchId);
    if (!nullToAbsent || valueJson != null) {
      map['value_json'] = Variable<String>(valueJson);
    }
    return map;
  }

  EntityVersionsCompanion toCompanion(bool nullToAbsent) {
    return EntityVersionsCompanion(
      ledgerId: Value(ledgerId),
      kind: Value(kind),
      entityId: Value(entityId),
      batchId: Value(batchId),
      valueJson: valueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(valueJson),
    );
  }

  factory EntityVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntityVersion(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      kind: serializer.fromJson<String>(json['kind']),
      entityId: serializer.fromJson<String>(json['entityId']),
      batchId: serializer.fromJson<String>(json['batchId']),
      valueJson: serializer.fromJson<String?>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'kind': serializer.toJson<String>(kind),
      'entityId': serializer.toJson<String>(entityId),
      'batchId': serializer.toJson<String>(batchId),
      'valueJson': serializer.toJson<String?>(valueJson),
    };
  }

  EntityVersion copyWith({
    String? ledgerId,
    String? kind,
    String? entityId,
    String? batchId,
    Value<String?> valueJson = const Value.absent(),
  }) => EntityVersion(
    ledgerId: ledgerId ?? this.ledgerId,
    kind: kind ?? this.kind,
    entityId: entityId ?? this.entityId,
    batchId: batchId ?? this.batchId,
    valueJson: valueJson.present ? valueJson.value : this.valueJson,
  );
  EntityVersion copyWithCompanion(EntityVersionsCompanion data) {
    return EntityVersion(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      kind: data.kind.present ? data.kind.value : this.kind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntityVersion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('kind: $kind, ')
          ..write('entityId: $entityId, ')
          ..write('batchId: $batchId, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, kind, entityId, batchId, valueJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityVersion &&
          other.ledgerId == this.ledgerId &&
          other.kind == this.kind &&
          other.entityId == this.entityId &&
          other.batchId == this.batchId &&
          other.valueJson == this.valueJson);
}

class EntityVersionsCompanion extends UpdateCompanion<EntityVersion> {
  final Value<String> ledgerId;
  final Value<String> kind;
  final Value<String> entityId;
  final Value<String> batchId;
  final Value<String?> valueJson;
  final Value<int> rowid;
  const EntityVersionsCompanion({
    this.ledgerId = const Value.absent(),
    this.kind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntityVersionsCompanion.insert({
    required String ledgerId,
    required String kind,
    required String entityId,
    required String batchId,
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       kind = Value(kind),
       entityId = Value(entityId),
       batchId = Value(batchId);
  static Insertable<EntityVersion> custom({
    Expression<String>? ledgerId,
    Expression<String>? kind,
    Expression<String>? entityId,
    Expression<String>? batchId,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (kind != null) 'kind': kind,
      if (entityId != null) 'entity_id': entityId,
      if (batchId != null) 'batch_id': batchId,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntityVersionsCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? kind,
    Value<String>? entityId,
    Value<String>? batchId,
    Value<String?>? valueJson,
    Value<int>? rowid,
  }) {
    return EntityVersionsCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      kind: kind ?? this.kind,
      entityId: entityId ?? this.entityId,
      batchId: batchId ?? this.batchId,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntityVersionsCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('kind: $kind, ')
          ..write('entityId: $entityId, ')
          ..write('batchId: $batchId, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChangeBatchesTable extends ChangeBatches
    with TableInfo<$ChangeBatchesTable, ChangeBatche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChangeBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ledgerId, batchId, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'change_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChangeBatche> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, batchId};
  @override
  ChangeBatche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChangeBatche(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $ChangeBatchesTable createAlias(String alias) {
    return $ChangeBatchesTable(attachedDatabase, alias);
  }
}

class ChangeBatche extends DataClass implements Insertable<ChangeBatche> {
  final String ledgerId;
  final String batchId;
  final String body;
  const ChangeBatche({
    required this.ledgerId,
    required this.batchId,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['batch_id'] = Variable<String>(batchId);
    map['body'] = Variable<String>(body);
    return map;
  }

  ChangeBatchesCompanion toCompanion(bool nullToAbsent) {
    return ChangeBatchesCompanion(
      ledgerId: Value(ledgerId),
      batchId: Value(batchId),
      body: Value(body),
    );
  }

  factory ChangeBatche.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChangeBatche(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      batchId: serializer.fromJson<String>(json['batchId']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'batchId': serializer.toJson<String>(batchId),
      'body': serializer.toJson<String>(body),
    };
  }

  ChangeBatche copyWith({String? ledgerId, String? batchId, String? body}) =>
      ChangeBatche(
        ledgerId: ledgerId ?? this.ledgerId,
        batchId: batchId ?? this.batchId,
        body: body ?? this.body,
      );
  ChangeBatche copyWithCompanion(ChangeBatchesCompanion data) {
    return ChangeBatche(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChangeBatche(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, batchId, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChangeBatche &&
          other.ledgerId == this.ledgerId &&
          other.batchId == this.batchId &&
          other.body == this.body);
}

class ChangeBatchesCompanion extends UpdateCompanion<ChangeBatche> {
  final Value<String> ledgerId;
  final Value<String> batchId;
  final Value<String> body;
  final Value<int> rowid;
  const ChangeBatchesCompanion({
    this.ledgerId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChangeBatchesCompanion.insert({
    required String ledgerId,
    required String batchId,
    required String body,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       batchId = Value(batchId),
       body = Value(body);
  static Insertable<ChangeBatche> custom({
    Expression<String>? ledgerId,
    Expression<String>? batchId,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (batchId != null) 'batch_id': batchId,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChangeBatchesCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? batchId,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return ChangeBatchesCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      batchId: batchId ?? this.batchId,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChangeBatchesCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CipherObjectsTable extends CipherObjects
    with TableInfo<$CipherObjectsTable, CipherObject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CipherObjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<String> nonce = GeneratedColumn<String>(
    'nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ledgerId,
    batchId,
    sha256,
    nonce,
    bytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cipher_objects';
  @override
  VerificationContext validateIntegrity(
    Insertable<CipherObject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, batchId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ledgerId, nonce},
  ];
  @override
  CipherObject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CipherObject(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nonce'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
    );
  }

  @override
  $CipherObjectsTable createAlias(String alias) {
    return $CipherObjectsTable(attachedDatabase, alias);
  }
}

class CipherObject extends DataClass implements Insertable<CipherObject> {
  final String ledgerId;
  final String batchId;
  final String sha256;
  final String nonce;
  final Uint8List bytes;
  const CipherObject({
    required this.ledgerId,
    required this.batchId,
    required this.sha256,
    required this.nonce,
    required this.bytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['batch_id'] = Variable<String>(batchId);
    map['sha256'] = Variable<String>(sha256);
    map['nonce'] = Variable<String>(nonce);
    map['bytes'] = Variable<Uint8List>(bytes);
    return map;
  }

  CipherObjectsCompanion toCompanion(bool nullToAbsent) {
    return CipherObjectsCompanion(
      ledgerId: Value(ledgerId),
      batchId: Value(batchId),
      sha256: Value(sha256),
      nonce: Value(nonce),
      bytes: Value(bytes),
    );
  }

  factory CipherObject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CipherObject(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      batchId: serializer.fromJson<String>(json['batchId']),
      sha256: serializer.fromJson<String>(json['sha256']),
      nonce: serializer.fromJson<String>(json['nonce']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'batchId': serializer.toJson<String>(batchId),
      'sha256': serializer.toJson<String>(sha256),
      'nonce': serializer.toJson<String>(nonce),
      'bytes': serializer.toJson<Uint8List>(bytes),
    };
  }

  CipherObject copyWith({
    String? ledgerId,
    String? batchId,
    String? sha256,
    String? nonce,
    Uint8List? bytes,
  }) => CipherObject(
    ledgerId: ledgerId ?? this.ledgerId,
    batchId: batchId ?? this.batchId,
    sha256: sha256 ?? this.sha256,
    nonce: nonce ?? this.nonce,
    bytes: bytes ?? this.bytes,
  );
  CipherObject copyWithCompanion(CipherObjectsCompanion data) {
    return CipherObject(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CipherObject(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('sha256: $sha256, ')
          ..write('nonce: $nonce, ')
          ..write('bytes: $bytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ledgerId,
    batchId,
    sha256,
    nonce,
    $driftBlobEquality.hash(bytes),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CipherObject &&
          other.ledgerId == this.ledgerId &&
          other.batchId == this.batchId &&
          other.sha256 == this.sha256 &&
          other.nonce == this.nonce &&
          $driftBlobEquality.equals(other.bytes, this.bytes));
}

class CipherObjectsCompanion extends UpdateCompanion<CipherObject> {
  final Value<String> ledgerId;
  final Value<String> batchId;
  final Value<String> sha256;
  final Value<String> nonce;
  final Value<Uint8List> bytes;
  final Value<int> rowid;
  const CipherObjectsCompanion({
    this.ledgerId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.nonce = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CipherObjectsCompanion.insert({
    required String ledgerId,
    required String batchId,
    required String sha256,
    required String nonce,
    required Uint8List bytes,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       batchId = Value(batchId),
       sha256 = Value(sha256),
       nonce = Value(nonce),
       bytes = Value(bytes);
  static Insertable<CipherObject> custom({
    Expression<String>? ledgerId,
    Expression<String>? batchId,
    Expression<String>? sha256,
    Expression<String>? nonce,
    Expression<Uint8List>? bytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (batchId != null) 'batch_id': batchId,
      if (sha256 != null) 'sha256': sha256,
      if (nonce != null) 'nonce': nonce,
      if (bytes != null) 'bytes': bytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CipherObjectsCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? batchId,
    Value<String>? sha256,
    Value<String>? nonce,
    Value<Uint8List>? bytes,
    Value<int>? rowid,
  }) {
    return CipherObjectsCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      batchId: batchId ?? this.batchId,
      sha256: sha256 ?? this.sha256,
      nonce: nonce ?? this.nonce,
      bytes: bytes ?? this.bytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<String>(nonce.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CipherObjectsCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('sha256: $sha256, ')
          ..write('nonce: $nonce, ')
          ..write('bytes: $bytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingUploadsTable extends PendingUploads
    with TableInfo<$PendingUploadsTable, PendingUpload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ledgerId, batchId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingUpload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, batchId};
  @override
  PendingUpload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingUpload(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
    );
  }

  @override
  $PendingUploadsTable createAlias(String alias) {
    return $PendingUploadsTable(attachedDatabase, alias);
  }
}

class PendingUpload extends DataClass implements Insertable<PendingUpload> {
  final String ledgerId;
  final String batchId;
  const PendingUpload({required this.ledgerId, required this.batchId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['batch_id'] = Variable<String>(batchId);
    return map;
  }

  PendingUploadsCompanion toCompanion(bool nullToAbsent) {
    return PendingUploadsCompanion(
      ledgerId: Value(ledgerId),
      batchId: Value(batchId),
    );
  }

  factory PendingUpload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingUpload(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      batchId: serializer.fromJson<String>(json['batchId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'batchId': serializer.toJson<String>(batchId),
    };
  }

  PendingUpload copyWith({String? ledgerId, String? batchId}) => PendingUpload(
    ledgerId: ledgerId ?? this.ledgerId,
    batchId: batchId ?? this.batchId,
  );
  PendingUpload copyWithCompanion(PendingUploadsCompanion data) {
    return PendingUpload(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingUpload(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, batchId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingUpload &&
          other.ledgerId == this.ledgerId &&
          other.batchId == this.batchId);
}

class PendingUploadsCompanion extends UpdateCompanion<PendingUpload> {
  final Value<String> ledgerId;
  final Value<String> batchId;
  final Value<int> rowid;
  const PendingUploadsCompanion({
    this.ledgerId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingUploadsCompanion.insert({
    required String ledgerId,
    required String batchId,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       batchId = Value(batchId);
  static Insertable<PendingUpload> custom({
    Expression<String>? ledgerId,
    Expression<String>? batchId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (batchId != null) 'batch_id': batchId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingUploadsCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? batchId,
    Value<int>? rowid,
  }) {
    return PendingUploadsCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      batchId: batchId ?? this.batchId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingUploadsCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReceivedBatchesTable extends ReceivedBatches
    with TableInfo<$ReceivedBatchesTable, ReceivedBatche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceivedBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ledgerId, batchId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'received_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceivedBatche> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, batchId};
  @override
  ReceivedBatche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceivedBatche(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
    );
  }

  @override
  $ReceivedBatchesTable createAlias(String alias) {
    return $ReceivedBatchesTable(attachedDatabase, alias);
  }
}

class ReceivedBatche extends DataClass implements Insertable<ReceivedBatche> {
  final String ledgerId;
  final String batchId;
  const ReceivedBatche({required this.ledgerId, required this.batchId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['batch_id'] = Variable<String>(batchId);
    return map;
  }

  ReceivedBatchesCompanion toCompanion(bool nullToAbsent) {
    return ReceivedBatchesCompanion(
      ledgerId: Value(ledgerId),
      batchId: Value(batchId),
    );
  }

  factory ReceivedBatche.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceivedBatche(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      batchId: serializer.fromJson<String>(json['batchId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'batchId': serializer.toJson<String>(batchId),
    };
  }

  ReceivedBatche copyWith({String? ledgerId, String? batchId}) =>
      ReceivedBatche(
        ledgerId: ledgerId ?? this.ledgerId,
        batchId: batchId ?? this.batchId,
      );
  ReceivedBatche copyWithCompanion(ReceivedBatchesCompanion data) {
    return ReceivedBatche(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceivedBatche(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, batchId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceivedBatche &&
          other.ledgerId == this.ledgerId &&
          other.batchId == this.batchId);
}

class ReceivedBatchesCompanion extends UpdateCompanion<ReceivedBatche> {
  final Value<String> ledgerId;
  final Value<String> batchId;
  final Value<int> rowid;
  const ReceivedBatchesCompanion({
    this.ledgerId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceivedBatchesCompanion.insert({
    required String ledgerId,
    required String batchId,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       batchId = Value(batchId);
  static Insertable<ReceivedBatche> custom({
    Expression<String>? ledgerId,
    Expression<String>? batchId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (batchId != null) 'batch_id': batchId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceivedBatchesCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? batchId,
    Value<int>? rowid,
  }) {
    return ReceivedBatchesCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      batchId: batchId ?? this.batchId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceivedBatchesCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredConflictsTable extends StoredConflicts
    with TableInfo<$StoredConflictsTable, StoredConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conflictIdMeta = const VerificationMeta(
    'conflictId',
  );
  @override
  late final GeneratedColumn<String> conflictId = GeneratedColumn<String>(
    'conflict_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ledgerId, conflictId, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('conflict_id')) {
      context.handle(
        _conflictIdMeta,
        conflictId.isAcceptableOrUnknown(data['conflict_id']!, _conflictIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conflictIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, conflictId};
  @override
  StoredConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredConflict(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      conflictId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $StoredConflictsTable createAlias(String alias) {
    return $StoredConflictsTable(attachedDatabase, alias);
  }
}

class StoredConflict extends DataClass implements Insertable<StoredConflict> {
  final String ledgerId;
  final String conflictId;
  final String body;
  const StoredConflict({
    required this.ledgerId,
    required this.conflictId,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['conflict_id'] = Variable<String>(conflictId);
    map['body'] = Variable<String>(body);
    return map;
  }

  StoredConflictsCompanion toCompanion(bool nullToAbsent) {
    return StoredConflictsCompanion(
      ledgerId: Value(ledgerId),
      conflictId: Value(conflictId),
      body: Value(body),
    );
  }

  factory StoredConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredConflict(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      conflictId: serializer.fromJson<String>(json['conflictId']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'conflictId': serializer.toJson<String>(conflictId),
      'body': serializer.toJson<String>(body),
    };
  }

  StoredConflict copyWith({
    String? ledgerId,
    String? conflictId,
    String? body,
  }) => StoredConflict(
    ledgerId: ledgerId ?? this.ledgerId,
    conflictId: conflictId ?? this.conflictId,
    body: body ?? this.body,
  );
  StoredConflict copyWithCompanion(StoredConflictsCompanion data) {
    return StoredConflict(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      conflictId: data.conflictId.present
          ? data.conflictId.value
          : this.conflictId,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredConflict(')
          ..write('ledgerId: $ledgerId, ')
          ..write('conflictId: $conflictId, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, conflictId, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredConflict &&
          other.ledgerId == this.ledgerId &&
          other.conflictId == this.conflictId &&
          other.body == this.body);
}

class StoredConflictsCompanion extends UpdateCompanion<StoredConflict> {
  final Value<String> ledgerId;
  final Value<String> conflictId;
  final Value<String> body;
  final Value<int> rowid;
  const StoredConflictsCompanion({
    this.ledgerId = const Value.absent(),
    this.conflictId = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredConflictsCompanion.insert({
    required String ledgerId,
    required String conflictId,
    required String body,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       conflictId = Value(conflictId),
       body = Value(body);
  static Insertable<StoredConflict> custom({
    Expression<String>? ledgerId,
    Expression<String>? conflictId,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (conflictId != null) 'conflict_id': conflictId,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredConflictsCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? conflictId,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return StoredConflictsCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      conflictId: conflictId ?? this.conflictId,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (conflictId.present) {
      map['conflict_id'] = Variable<String>(conflictId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredConflictsCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('conflictId: $conflictId, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotificationStatesTable extends NotificationStates
    with TableInfo<$NotificationStatesTable, NotificationState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notificationIdMeta = const VerificationMeta(
    'notificationId',
  );
  @override
  late final GeneratedColumn<String> notificationId = GeneratedColumn<String>(
    'notification_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ledgerId, notificationId, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('notification_id')) {
      context.handle(
        _notificationIdMeta,
        notificationId.isAcceptableOrUnknown(
          data['notification_id']!,
          _notificationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_notificationIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, notificationId};
  @override
  NotificationState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationState(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      notificationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notification_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $NotificationStatesTable createAlias(String alias) {
    return $NotificationStatesTable(attachedDatabase, alias);
  }
}

class NotificationState extends DataClass
    implements Insertable<NotificationState> {
  final String ledgerId;
  final String notificationId;
  final String body;
  const NotificationState({
    required this.ledgerId,
    required this.notificationId,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['notification_id'] = Variable<String>(notificationId);
    map['body'] = Variable<String>(body);
    return map;
  }

  NotificationStatesCompanion toCompanion(bool nullToAbsent) {
    return NotificationStatesCompanion(
      ledgerId: Value(ledgerId),
      notificationId: Value(notificationId),
      body: Value(body),
    );
  }

  factory NotificationState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationState(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      notificationId: serializer.fromJson<String>(json['notificationId']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'notificationId': serializer.toJson<String>(notificationId),
      'body': serializer.toJson<String>(body),
    };
  }

  NotificationState copyWith({
    String? ledgerId,
    String? notificationId,
    String? body,
  }) => NotificationState(
    ledgerId: ledgerId ?? this.ledgerId,
    notificationId: notificationId ?? this.notificationId,
    body: body ?? this.body,
  );
  NotificationState copyWithCompanion(NotificationStatesCompanion data) {
    return NotificationState(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationState(')
          ..write('ledgerId: $ledgerId, ')
          ..write('notificationId: $notificationId, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerId, notificationId, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationState &&
          other.ledgerId == this.ledgerId &&
          other.notificationId == this.notificationId &&
          other.body == this.body);
}

class NotificationStatesCompanion extends UpdateCompanion<NotificationState> {
  final Value<String> ledgerId;
  final Value<String> notificationId;
  final Value<String> body;
  final Value<int> rowid;
  const NotificationStatesCompanion({
    this.ledgerId = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationStatesCompanion.insert({
    required String ledgerId,
    required String notificationId,
    required String body,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       notificationId = Value(notificationId),
       body = Value(body);
  static Insertable<NotificationState> custom({
    Expression<String>? ledgerId,
    Expression<String>? notificationId,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (notificationId != null) 'notification_id': notificationId,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationStatesCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? notificationId,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return NotificationStatesCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      notificationId: notificationId ?? this.notificationId,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (notificationId.present) {
      map['notification_id'] = Variable<String>(notificationId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationStatesCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('notificationId: $notificationId, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuarantinedObjectsTable extends QuarantinedObjects
    with TableInfo<$QuarantinedObjectsTable, QuarantinedObject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuarantinedObjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ledgerId,
    batchId,
    sha256,
    bytes,
    body,
    reason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'quarantined_objects';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuarantinedObject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerId, batchId, sha256};
  @override
  QuarantinedObject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuarantinedObject(
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
    );
  }

  @override
  $QuarantinedObjectsTable createAlias(String alias) {
    return $QuarantinedObjectsTable(attachedDatabase, alias);
  }
}

class QuarantinedObject extends DataClass
    implements Insertable<QuarantinedObject> {
  final String ledgerId;
  final String batchId;
  final String sha256;
  final Uint8List bytes;
  final String body;
  final String reason;
  const QuarantinedObject({
    required this.ledgerId,
    required this.batchId,
    required this.sha256,
    required this.bytes,
    required this.body,
    required this.reason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_id'] = Variable<String>(ledgerId);
    map['batch_id'] = Variable<String>(batchId);
    map['sha256'] = Variable<String>(sha256);
    map['bytes'] = Variable<Uint8List>(bytes);
    map['body'] = Variable<String>(body);
    map['reason'] = Variable<String>(reason);
    return map;
  }

  QuarantinedObjectsCompanion toCompanion(bool nullToAbsent) {
    return QuarantinedObjectsCompanion(
      ledgerId: Value(ledgerId),
      batchId: Value(batchId),
      sha256: Value(sha256),
      bytes: Value(bytes),
      body: Value(body),
      reason: Value(reason),
    );
  }

  factory QuarantinedObject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuarantinedObject(
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      batchId: serializer.fromJson<String>(json['batchId']),
      sha256: serializer.fromJson<String>(json['sha256']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      body: serializer.fromJson<String>(json['body']),
      reason: serializer.fromJson<String>(json['reason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerId': serializer.toJson<String>(ledgerId),
      'batchId': serializer.toJson<String>(batchId),
      'sha256': serializer.toJson<String>(sha256),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'body': serializer.toJson<String>(body),
      'reason': serializer.toJson<String>(reason),
    };
  }

  QuarantinedObject copyWith({
    String? ledgerId,
    String? batchId,
    String? sha256,
    Uint8List? bytes,
    String? body,
    String? reason,
  }) => QuarantinedObject(
    ledgerId: ledgerId ?? this.ledgerId,
    batchId: batchId ?? this.batchId,
    sha256: sha256 ?? this.sha256,
    bytes: bytes ?? this.bytes,
    body: body ?? this.body,
    reason: reason ?? this.reason,
  );
  QuarantinedObject copyWithCompanion(QuarantinedObjectsCompanion data) {
    return QuarantinedObject(
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      body: data.body.present ? data.body.value : this.body,
      reason: data.reason.present ? data.reason.value : this.reason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuarantinedObject(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('sha256: $sha256, ')
          ..write('bytes: $bytes, ')
          ..write('body: $body, ')
          ..write('reason: $reason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ledgerId,
    batchId,
    sha256,
    $driftBlobEquality.hash(bytes),
    body,
    reason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuarantinedObject &&
          other.ledgerId == this.ledgerId &&
          other.batchId == this.batchId &&
          other.sha256 == this.sha256 &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.body == this.body &&
          other.reason == this.reason);
}

class QuarantinedObjectsCompanion extends UpdateCompanion<QuarantinedObject> {
  final Value<String> ledgerId;
  final Value<String> batchId;
  final Value<String> sha256;
  final Value<Uint8List> bytes;
  final Value<String> body;
  final Value<String> reason;
  final Value<int> rowid;
  const QuarantinedObjectsCompanion({
    this.ledgerId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.bytes = const Value.absent(),
    this.body = const Value.absent(),
    this.reason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QuarantinedObjectsCompanion.insert({
    required String ledgerId,
    required String batchId,
    required String sha256,
    required Uint8List bytes,
    required String body,
    required String reason,
    this.rowid = const Value.absent(),
  }) : ledgerId = Value(ledgerId),
       batchId = Value(batchId),
       sha256 = Value(sha256),
       bytes = Value(bytes),
       body = Value(body),
       reason = Value(reason);
  static Insertable<QuarantinedObject> custom({
    Expression<String>? ledgerId,
    Expression<String>? batchId,
    Expression<String>? sha256,
    Expression<Uint8List>? bytes,
    Expression<String>? body,
    Expression<String>? reason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (batchId != null) 'batch_id': batchId,
      if (sha256 != null) 'sha256': sha256,
      if (bytes != null) 'bytes': bytes,
      if (body != null) 'body': body,
      if (reason != null) 'reason': reason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QuarantinedObjectsCompanion copyWith({
    Value<String>? ledgerId,
    Value<String>? batchId,
    Value<String>? sha256,
    Value<Uint8List>? bytes,
    Value<String>? body,
    Value<String>? reason,
    Value<int>? rowid,
  }) {
    return QuarantinedObjectsCompanion(
      ledgerId: ledgerId ?? this.ledgerId,
      batchId: batchId ?? this.batchId,
      sha256: sha256 ?? this.sha256,
      bytes: bytes ?? this.bytes,
      body: body ?? this.body,
      reason: reason ?? this.reason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuarantinedObjectsCompanion(')
          ..write('ledgerId: $ledgerId, ')
          ..write('batchId: $batchId, ')
          ..write('sha256: $sha256, ')
          ..write('bytes: $bytes, ')
          ..write('body: $body, ')
          ..write('reason: $reason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LedgerRecordsTable ledgerRecords = $LedgerRecordsTable(this);
  late final $EntityVersionsTable entityVersions = $EntityVersionsTable(this);
  late final $ChangeBatchesTable changeBatches = $ChangeBatchesTable(this);
  late final $CipherObjectsTable cipherObjects = $CipherObjectsTable(this);
  late final $PendingUploadsTable pendingUploads = $PendingUploadsTable(this);
  late final $ReceivedBatchesTable receivedBatches = $ReceivedBatchesTable(
    this,
  );
  late final $StoredConflictsTable storedConflicts = $StoredConflictsTable(
    this,
  );
  late final $NotificationStatesTable notificationStates =
      $NotificationStatesTable(this);
  late final $QuarantinedObjectsTable quarantinedObjects =
      $QuarantinedObjectsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    ledgerRecords,
    entityVersions,
    changeBatches,
    cipherObjects,
    pendingUploads,
    receivedBatches,
    storedConflicts,
    notificationStates,
    quarantinedObjects,
  ];
}

typedef $$LedgerRecordsTableCreateCompanionBuilder =
    LedgerRecordsCompanion Function({
      required String ledgerId,
      required Uint8List metadata,
      Value<int> rowid,
    });
typedef $$LedgerRecordsTableUpdateCompanionBuilder =
    LedgerRecordsCompanion Function({
      Value<String> ledgerId,
      Value<Uint8List> metadata,
      Value<int> rowid,
    });

class $$LedgerRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $LedgerRecordsTable> {
  $$LedgerRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LedgerRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgerRecordsTable> {
  $$LedgerRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LedgerRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgerRecordsTable> {
  $$LedgerRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<Uint8List> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);
}

class $$LedgerRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LedgerRecordsTable,
          LedgerRecord,
          $$LedgerRecordsTableFilterComposer,
          $$LedgerRecordsTableOrderingComposer,
          $$LedgerRecordsTableAnnotationComposer,
          $$LedgerRecordsTableCreateCompanionBuilder,
          $$LedgerRecordsTableUpdateCompanionBuilder,
          (
            LedgerRecord,
            BaseReferences<_$AppDatabase, $LedgerRecordsTable, LedgerRecord>,
          ),
          LedgerRecord,
          PrefetchHooks Function()
        > {
  $$LedgerRecordsTableTableManager(_$AppDatabase db, $LedgerRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<Uint8List> metadata = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerRecordsCompanion(
                ledgerId: ledgerId,
                metadata: metadata,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required Uint8List metadata,
                Value<int> rowid = const Value.absent(),
              }) => LedgerRecordsCompanion.insert(
                ledgerId: ledgerId,
                metadata: metadata,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LedgerRecordsTable, LedgerRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LedgerRecordsTable,
                    LedgerRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LedgerRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LedgerRecordsTable,
      LedgerRecord,
      $$LedgerRecordsTableFilterComposer,
      $$LedgerRecordsTableOrderingComposer,
      $$LedgerRecordsTableAnnotationComposer,
      $$LedgerRecordsTableCreateCompanionBuilder,
      $$LedgerRecordsTableUpdateCompanionBuilder,
      (
        LedgerRecord,
        BaseReferences<_$AppDatabase, $LedgerRecordsTable, LedgerRecord>,
      ),
      LedgerRecord,
      PrefetchHooks Function()
    >;
typedef $$EntityVersionsTableCreateCompanionBuilder =
    EntityVersionsCompanion Function({
      required String ledgerId,
      required String kind,
      required String entityId,
      required String batchId,
      Value<String?> valueJson,
      Value<int> rowid,
    });
typedef $$EntityVersionsTableUpdateCompanionBuilder =
    EntityVersionsCompanion Function({
      Value<String> ledgerId,
      Value<String> kind,
      Value<String> entityId,
      Value<String> batchId,
      Value<String?> valueJson,
      Value<int> rowid,
    });

class $$EntityVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $EntityVersionsTable> {
  $$EntityVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntityVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $EntityVersionsTable> {
  $$EntityVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntityVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntityVersionsTable> {
  $$EntityVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);
}

class $$EntityVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntityVersionsTable,
          EntityVersion,
          $$EntityVersionsTableFilterComposer,
          $$EntityVersionsTableOrderingComposer,
          $$EntityVersionsTableAnnotationComposer,
          $$EntityVersionsTableCreateCompanionBuilder,
          $$EntityVersionsTableUpdateCompanionBuilder,
          (
            EntityVersion,
            BaseReferences<_$AppDatabase, $EntityVersionsTable, EntityVersion>,
          ),
          EntityVersion,
          PrefetchHooks Function()
        > {
  $$EntityVersionsTableTableManager(
    _$AppDatabase db,
    $EntityVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntityVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntityVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntityVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String?> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntityVersionsCompanion(
                ledgerId: ledgerId,
                kind: kind,
                entityId: entityId,
                batchId: batchId,
                valueJson: valueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String kind,
                required String entityId,
                required String batchId,
                Value<String?> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntityVersionsCompanion.insert(
                ledgerId: ledgerId,
                kind: kind,
                entityId: entityId,
                batchId: batchId,
                valueJson: valueJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntityVersionsTable, EntityVersion>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $EntityVersionsTable,
                    EntityVersion
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntityVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntityVersionsTable,
      EntityVersion,
      $$EntityVersionsTableFilterComposer,
      $$EntityVersionsTableOrderingComposer,
      $$EntityVersionsTableAnnotationComposer,
      $$EntityVersionsTableCreateCompanionBuilder,
      $$EntityVersionsTableUpdateCompanionBuilder,
      (
        EntityVersion,
        BaseReferences<_$AppDatabase, $EntityVersionsTable, EntityVersion>,
      ),
      EntityVersion,
      PrefetchHooks Function()
    >;
typedef $$ChangeBatchesTableCreateCompanionBuilder =
    ChangeBatchesCompanion Function({
      required String ledgerId,
      required String batchId,
      required String body,
      Value<int> rowid,
    });
typedef $$ChangeBatchesTableUpdateCompanionBuilder =
    ChangeBatchesCompanion Function({
      Value<String> ledgerId,
      Value<String> batchId,
      Value<String> body,
      Value<int> rowid,
    });

class $$ChangeBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $ChangeBatchesTable> {
  $$ChangeBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChangeBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChangeBatchesTable> {
  $$ChangeBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChangeBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChangeBatchesTable> {
  $$ChangeBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$ChangeBatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChangeBatchesTable,
          ChangeBatche,
          $$ChangeBatchesTableFilterComposer,
          $$ChangeBatchesTableOrderingComposer,
          $$ChangeBatchesTableAnnotationComposer,
          $$ChangeBatchesTableCreateCompanionBuilder,
          $$ChangeBatchesTableUpdateCompanionBuilder,
          (
            ChangeBatche,
            BaseReferences<_$AppDatabase, $ChangeBatchesTable, ChangeBatche>,
          ),
          ChangeBatche,
          PrefetchHooks Function()
        > {
  $$ChangeBatchesTableTableManager(_$AppDatabase db, $ChangeBatchesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChangeBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChangeBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChangeBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChangeBatchesCompanion(
                ledgerId: ledgerId,
                batchId: batchId,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String batchId,
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => ChangeBatchesCompanion.insert(
                ledgerId: ledgerId,
                batchId: batchId,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChangeBatchesTable, ChangeBatche>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChangeBatchesTable,
                    ChangeBatche
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChangeBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChangeBatchesTable,
      ChangeBatche,
      $$ChangeBatchesTableFilterComposer,
      $$ChangeBatchesTableOrderingComposer,
      $$ChangeBatchesTableAnnotationComposer,
      $$ChangeBatchesTableCreateCompanionBuilder,
      $$ChangeBatchesTableUpdateCompanionBuilder,
      (
        ChangeBatche,
        BaseReferences<_$AppDatabase, $ChangeBatchesTable, ChangeBatche>,
      ),
      ChangeBatche,
      PrefetchHooks Function()
    >;
typedef $$CipherObjectsTableCreateCompanionBuilder =
    CipherObjectsCompanion Function({
      required String ledgerId,
      required String batchId,
      required String sha256,
      required String nonce,
      required Uint8List bytes,
      Value<int> rowid,
    });
typedef $$CipherObjectsTableUpdateCompanionBuilder =
    CipherObjectsCompanion Function({
      Value<String> ledgerId,
      Value<String> batchId,
      Value<String> sha256,
      Value<String> nonce,
      Value<Uint8List> bytes,
      Value<int> rowid,
    });

class $$CipherObjectsTableFilterComposer
    extends Composer<_$AppDatabase, $CipherObjectsTable> {
  $$CipherObjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CipherObjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $CipherObjectsTable> {
  $$CipherObjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CipherObjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CipherObjectsTable> {
  $$CipherObjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);
}

class $$CipherObjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CipherObjectsTable,
          CipherObject,
          $$CipherObjectsTableFilterComposer,
          $$CipherObjectsTableOrderingComposer,
          $$CipherObjectsTableAnnotationComposer,
          $$CipherObjectsTableCreateCompanionBuilder,
          $$CipherObjectsTableUpdateCompanionBuilder,
          (
            CipherObject,
            BaseReferences<_$AppDatabase, $CipherObjectsTable, CipherObject>,
          ),
          CipherObject,
          PrefetchHooks Function()
        > {
  $$CipherObjectsTableTableManager(_$AppDatabase db, $CipherObjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CipherObjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CipherObjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CipherObjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> nonce = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CipherObjectsCompanion(
                ledgerId: ledgerId,
                batchId: batchId,
                sha256: sha256,
                nonce: nonce,
                bytes: bytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String batchId,
                required String sha256,
                required String nonce,
                required Uint8List bytes,
                Value<int> rowid = const Value.absent(),
              }) => CipherObjectsCompanion.insert(
                ledgerId: ledgerId,
                batchId: batchId,
                sha256: sha256,
                nonce: nonce,
                bytes: bytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CipherObjectsTable, CipherObject>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CipherObjectsTable,
                    CipherObject
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CipherObjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CipherObjectsTable,
      CipherObject,
      $$CipherObjectsTableFilterComposer,
      $$CipherObjectsTableOrderingComposer,
      $$CipherObjectsTableAnnotationComposer,
      $$CipherObjectsTableCreateCompanionBuilder,
      $$CipherObjectsTableUpdateCompanionBuilder,
      (
        CipherObject,
        BaseReferences<_$AppDatabase, $CipherObjectsTable, CipherObject>,
      ),
      CipherObject,
      PrefetchHooks Function()
    >;
typedef $$PendingUploadsTableCreateCompanionBuilder =
    PendingUploadsCompanion Function({
      required String ledgerId,
      required String batchId,
      Value<int> rowid,
    });
typedef $$PendingUploadsTableUpdateCompanionBuilder =
    PendingUploadsCompanion Function({
      Value<String> ledgerId,
      Value<String> batchId,
      Value<int> rowid,
    });

class $$PendingUploadsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingUploadsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingUploadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);
}

class $$PendingUploadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingUploadsTable,
          PendingUpload,
          $$PendingUploadsTableFilterComposer,
          $$PendingUploadsTableOrderingComposer,
          $$PendingUploadsTableAnnotationComposer,
          $$PendingUploadsTableCreateCompanionBuilder,
          $$PendingUploadsTableUpdateCompanionBuilder,
          (
            PendingUpload,
            BaseReferences<_$AppDatabase, $PendingUploadsTable, PendingUpload>,
          ),
          PendingUpload,
          PrefetchHooks Function()
        > {
  $$PendingUploadsTableTableManager(
    _$AppDatabase db,
    $PendingUploadsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingUploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingUploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingUploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingUploadsCompanion(
                ledgerId: ledgerId,
                batchId: batchId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String batchId,
                Value<int> rowid = const Value.absent(),
              }) => PendingUploadsCompanion.insert(
                ledgerId: ledgerId,
                batchId: batchId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingUploadsTable, PendingUpload>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingUploadsTable,
                    PendingUpload
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingUploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingUploadsTable,
      PendingUpload,
      $$PendingUploadsTableFilterComposer,
      $$PendingUploadsTableOrderingComposer,
      $$PendingUploadsTableAnnotationComposer,
      $$PendingUploadsTableCreateCompanionBuilder,
      $$PendingUploadsTableUpdateCompanionBuilder,
      (
        PendingUpload,
        BaseReferences<_$AppDatabase, $PendingUploadsTable, PendingUpload>,
      ),
      PendingUpload,
      PrefetchHooks Function()
    >;
typedef $$ReceivedBatchesTableCreateCompanionBuilder =
    ReceivedBatchesCompanion Function({
      required String ledgerId,
      required String batchId,
      Value<int> rowid,
    });
typedef $$ReceivedBatchesTableUpdateCompanionBuilder =
    ReceivedBatchesCompanion Function({
      Value<String> ledgerId,
      Value<String> batchId,
      Value<int> rowid,
    });

class $$ReceivedBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $ReceivedBatchesTable> {
  $$ReceivedBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReceivedBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceivedBatchesTable> {
  $$ReceivedBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReceivedBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceivedBatchesTable> {
  $$ReceivedBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);
}

class $$ReceivedBatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceivedBatchesTable,
          ReceivedBatche,
          $$ReceivedBatchesTableFilterComposer,
          $$ReceivedBatchesTableOrderingComposer,
          $$ReceivedBatchesTableAnnotationComposer,
          $$ReceivedBatchesTableCreateCompanionBuilder,
          $$ReceivedBatchesTableUpdateCompanionBuilder,
          (
            ReceivedBatche,
            BaseReferences<
              _$AppDatabase,
              $ReceivedBatchesTable,
              ReceivedBatche
            >,
          ),
          ReceivedBatche,
          PrefetchHooks Function()
        > {
  $$ReceivedBatchesTableTableManager(
    _$AppDatabase db,
    $ReceivedBatchesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceivedBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceivedBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceivedBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceivedBatchesCompanion(
                ledgerId: ledgerId,
                batchId: batchId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String batchId,
                Value<int> rowid = const Value.absent(),
              }) => ReceivedBatchesCompanion.insert(
                ledgerId: ledgerId,
                batchId: batchId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReceivedBatchesTable, ReceivedBatche>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReceivedBatchesTable,
                    ReceivedBatche
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReceivedBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceivedBatchesTable,
      ReceivedBatche,
      $$ReceivedBatchesTableFilterComposer,
      $$ReceivedBatchesTableOrderingComposer,
      $$ReceivedBatchesTableAnnotationComposer,
      $$ReceivedBatchesTableCreateCompanionBuilder,
      $$ReceivedBatchesTableUpdateCompanionBuilder,
      (
        ReceivedBatche,
        BaseReferences<_$AppDatabase, $ReceivedBatchesTable, ReceivedBatche>,
      ),
      ReceivedBatche,
      PrefetchHooks Function()
    >;
typedef $$StoredConflictsTableCreateCompanionBuilder =
    StoredConflictsCompanion Function({
      required String ledgerId,
      required String conflictId,
      required String body,
      Value<int> rowid,
    });
typedef $$StoredConflictsTableUpdateCompanionBuilder =
    StoredConflictsCompanion Function({
      Value<String> ledgerId,
      Value<String> conflictId,
      Value<String> body,
      Value<int> rowid,
    });

class $$StoredConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $StoredConflictsTable> {
  $$StoredConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredConflictsTable> {
  $$StoredConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredConflictsTable> {
  $$StoredConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$StoredConflictsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoredConflictsTable,
          StoredConflict,
          $$StoredConflictsTableFilterComposer,
          $$StoredConflictsTableOrderingComposer,
          $$StoredConflictsTableAnnotationComposer,
          $$StoredConflictsTableCreateCompanionBuilder,
          $$StoredConflictsTableUpdateCompanionBuilder,
          (
            StoredConflict,
            BaseReferences<
              _$AppDatabase,
              $StoredConflictsTable,
              StoredConflict
            >,
          ),
          StoredConflict,
          PrefetchHooks Function()
        > {
  $$StoredConflictsTableTableManager(
    _$AppDatabase db,
    $StoredConflictsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> conflictId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredConflictsCompanion(
                ledgerId: ledgerId,
                conflictId: conflictId,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String conflictId,
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => StoredConflictsCompanion.insert(
                ledgerId: ledgerId,
                conflictId: conflictId,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoredConflictsTable, StoredConflict>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $StoredConflictsTable,
                    StoredConflict
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoredConflictsTable,
      StoredConflict,
      $$StoredConflictsTableFilterComposer,
      $$StoredConflictsTableOrderingComposer,
      $$StoredConflictsTableAnnotationComposer,
      $$StoredConflictsTableCreateCompanionBuilder,
      $$StoredConflictsTableUpdateCompanionBuilder,
      (
        StoredConflict,
        BaseReferences<_$AppDatabase, $StoredConflictsTable, StoredConflict>,
      ),
      StoredConflict,
      PrefetchHooks Function()
    >;
typedef $$NotificationStatesTableCreateCompanionBuilder =
    NotificationStatesCompanion Function({
      required String ledgerId,
      required String notificationId,
      required String body,
      Value<int> rowid,
    });
typedef $$NotificationStatesTableUpdateCompanionBuilder =
    NotificationStatesCompanion Function({
      Value<String> ledgerId,
      Value<String> notificationId,
      Value<String> body,
      Value<int> rowid,
    });

class $$NotificationStatesTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationStatesTable> {
  $$NotificationStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationStatesTable> {
  $$NotificationStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationStatesTable> {
  $$NotificationStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$NotificationStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationStatesTable,
          NotificationState,
          $$NotificationStatesTableFilterComposer,
          $$NotificationStatesTableOrderingComposer,
          $$NotificationStatesTableAnnotationComposer,
          $$NotificationStatesTableCreateCompanionBuilder,
          $$NotificationStatesTableUpdateCompanionBuilder,
          (
            NotificationState,
            BaseReferences<
              _$AppDatabase,
              $NotificationStatesTable,
              NotificationState
            >,
          ),
          NotificationState,
          PrefetchHooks Function()
        > {
  $$NotificationStatesTableTableManager(
    _$AppDatabase db,
    $NotificationStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotificationStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> notificationId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationStatesCompanion(
                ledgerId: ledgerId,
                notificationId: notificationId,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String notificationId,
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => NotificationStatesCompanion.insert(
                ledgerId: ledgerId,
                notificationId: notificationId,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotificationStatesTable, NotificationState>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $NotificationStatesTable,
                    NotificationState
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationStatesTable,
      NotificationState,
      $$NotificationStatesTableFilterComposer,
      $$NotificationStatesTableOrderingComposer,
      $$NotificationStatesTableAnnotationComposer,
      $$NotificationStatesTableCreateCompanionBuilder,
      $$NotificationStatesTableUpdateCompanionBuilder,
      (
        NotificationState,
        BaseReferences<
          _$AppDatabase,
          $NotificationStatesTable,
          NotificationState
        >,
      ),
      NotificationState,
      PrefetchHooks Function()
    >;
typedef $$QuarantinedObjectsTableCreateCompanionBuilder =
    QuarantinedObjectsCompanion Function({
      required String ledgerId,
      required String batchId,
      required String sha256,
      required Uint8List bytes,
      required String body,
      required String reason,
      Value<int> rowid,
    });
typedef $$QuarantinedObjectsTableUpdateCompanionBuilder =
    QuarantinedObjectsCompanion Function({
      Value<String> ledgerId,
      Value<String> batchId,
      Value<String> sha256,
      Value<Uint8List> bytes,
      Value<String> body,
      Value<String> reason,
      Value<int> rowid,
    });

class $$QuarantinedObjectsTableFilterComposer
    extends Composer<_$AppDatabase, $QuarantinedObjectsTable> {
  $$QuarantinedObjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QuarantinedObjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $QuarantinedObjectsTable> {
  $$QuarantinedObjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QuarantinedObjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $QuarantinedObjectsTable> {
  $$QuarantinedObjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);
}

class $$QuarantinedObjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QuarantinedObjectsTable,
          QuarantinedObject,
          $$QuarantinedObjectsTableFilterComposer,
          $$QuarantinedObjectsTableOrderingComposer,
          $$QuarantinedObjectsTableAnnotationComposer,
          $$QuarantinedObjectsTableCreateCompanionBuilder,
          $$QuarantinedObjectsTableUpdateCompanionBuilder,
          (
            QuarantinedObject,
            BaseReferences<
              _$AppDatabase,
              $QuarantinedObjectsTable,
              QuarantinedObject
            >,
          ),
          QuarantinedObject,
          PrefetchHooks Function()
        > {
  $$QuarantinedObjectsTableTableManager(
    _$AppDatabase db,
    $QuarantinedObjectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuarantinedObjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuarantinedObjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuarantinedObjectsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ledgerId = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QuarantinedObjectsCompanion(
                ledgerId: ledgerId,
                batchId: batchId,
                sha256: sha256,
                bytes: bytes,
                body: body,
                reason: reason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ledgerId,
                required String batchId,
                required String sha256,
                required Uint8List bytes,
                required String body,
                required String reason,
                Value<int> rowid = const Value.absent(),
              }) => QuarantinedObjectsCompanion.insert(
                ledgerId: ledgerId,
                batchId: batchId,
                sha256: sha256,
                bytes: bytes,
                body: body,
                reason: reason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QuarantinedObjectsTable, QuarantinedObject>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $QuarantinedObjectsTable,
                    QuarantinedObject
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QuarantinedObjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QuarantinedObjectsTable,
      QuarantinedObject,
      $$QuarantinedObjectsTableFilterComposer,
      $$QuarantinedObjectsTableOrderingComposer,
      $$QuarantinedObjectsTableAnnotationComposer,
      $$QuarantinedObjectsTableCreateCompanionBuilder,
      $$QuarantinedObjectsTableUpdateCompanionBuilder,
      (
        QuarantinedObject,
        BaseReferences<
          _$AppDatabase,
          $QuarantinedObjectsTable,
          QuarantinedObject
        >,
      ),
      QuarantinedObject,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LedgerRecordsTableTableManager get ledgerRecords =>
      $$LedgerRecordsTableTableManager(_db, _db.ledgerRecords);
  $$EntityVersionsTableTableManager get entityVersions =>
      $$EntityVersionsTableTableManager(_db, _db.entityVersions);
  $$ChangeBatchesTableTableManager get changeBatches =>
      $$ChangeBatchesTableTableManager(_db, _db.changeBatches);
  $$CipherObjectsTableTableManager get cipherObjects =>
      $$CipherObjectsTableTableManager(_db, _db.cipherObjects);
  $$PendingUploadsTableTableManager get pendingUploads =>
      $$PendingUploadsTableTableManager(_db, _db.pendingUploads);
  $$ReceivedBatchesTableTableManager get receivedBatches =>
      $$ReceivedBatchesTableTableManager(_db, _db.receivedBatches);
  $$StoredConflictsTableTableManager get storedConflicts =>
      $$StoredConflictsTableTableManager(_db, _db.storedConflicts);
  $$NotificationStatesTableTableManager get notificationStates =>
      $$NotificationStatesTableTableManager(_db, _db.notificationStates);
  $$QuarantinedObjectsTableTableManager get quarantinedObjects =>
      $$QuarantinedObjectsTableTableManager(_db, _db.quarantinedObjects);
}
