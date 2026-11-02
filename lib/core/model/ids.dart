import 'dart:convert';
import 'dart:math';
import 'errors.dart';

typedef LedgerId = String;
typedef DeviceId = String;
typedef EntityId = String;
typedef BatchId = String;

final _idPattern = RegExp(r'^[0-9a-f]{32}$');
void validateId(String value) {
  if (!_idPattern.hasMatch(value)) invalidModel();
}

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Value equality uses sorted JSON keys, never insertion order or Map identity.
abstract class ModelValue {
  Map<String, Object?> toJson();
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ModelValue &&
          canonicalModelJson(toJson()) == canonicalModelJson(other.toJson());
  @override
  int get hashCode => Object.hash(runtimeType, canonicalModelJson(toJson()));
}

String canonicalModelJson(Object? value) => jsonEncode(_canonical(value));
Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List<Object?>) return value.map(_canonical).toList();
  return value;
}

List<String> immutableIds(Iterable<String> values) {
  final ids = values.toSet().toList()..sort();
  for (final id in ids) {
    validateId(id);
  }
  return List.unmodifiable(ids);
}

Map<String, dynamic> jsonMap(Object? value) =>
    (value as Map).cast<String, dynamic>();
List<Object?> jsonList(Object? value) => (value as List).cast<Object?>();
T enumValue<T extends Enum>(List<T> values, Object? name) =>
    values.firstWhere((value) => value.name == name, orElse: invalidModel);
