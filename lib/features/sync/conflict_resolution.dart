import '../../core/model/change_batch.dart';
import '../../core/model/errors.dart';
import 'materializer.dart';

/// Explicit resolution must select every entity in the current atomic component.
/// Incoming validation independently enforces the same rule against causal past.
void validateConflictResolution(
  CausalAnalysis state,
  Conflict conflict,
  List<Mutation> changes,
) {
  if (!state.projection.conflicts.contains(conflict)) {
    throw const EchoFailure('conflict', '冲突已变化，请重新加载');
  }
  final refs = changes.map((m) => m.ref).toSet();
  if (!refs.containsAll(conflict.affectedRefs)) {
    throw const EchoFailure('conflict', '必须明确选择全部关联订阅与付款');
  }
  for (final c in state.projection.conflicts) {
    if (c.affectedRefs.any(refs.contains) &&
        !refs.containsAll(c.affectedRefs)) {
      throw const EchoFailure('conflict', '解决记录缺少关联业务实体');
    }
  }
  for (final m in changes) {
    final expected = state.heads[m.ref] ?? {};
    if (state.unsafeRefs.contains(m.ref) ||
        expected.length != m.parentBatchIds.length ||
        !expected.containsAll(m.parentBatchIds)) {
      throw const EchoFailure('conflict', '解决记录必须引用全部竞争版本');
    }
  }
}
