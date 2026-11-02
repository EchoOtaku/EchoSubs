enum SyncChannelKind { webdav, lan }

class ChannelReport {
  const ChannelReport({
    this.enabled = false,
    this.uploaded = 0,
    this.downloaded = 0,
    this.pendingUpload = 0,
    this.pendingDependencies = 0,
    this.conflicts = 0,
    this.quarantined = 0,
    this.errors = const [],
    this.errorCodes = const [],
    this.lastSuccess,
  });
  final bool enabled;
  final int uploaded,
      downloaded,
      pendingUpload,
      pendingDependencies,
      conflicts,
      quarantined;
  final List<String> errors;
  final List<String> errorCodes;
  bool get cancelled => errorCodes.contains('cancelled');
  final DateTime? lastSuccess;
  bool get succeeded =>
      enabled &&
      errors.isEmpty &&
      pendingUpload == 0 &&
      pendingDependencies == 0 &&
      conflicts == 0 &&
      quarantined == 0;
}

class SyncReport {
  const SyncReport(this.webdav, this.lan);
  final ChannelReport webdav, lan;
}

class SyncStatus {
  const SyncStatus({
    this.running = false,
    this.report = const SyncReport(ChannelReport(), ChannelReport()),
    this.remindersReconciled = false,
    this.retryMessage,
    this.failure,
    this.failureCode,
  });
  final bool running;
  final SyncReport report;
  // Task9 explicitly updates this after its independent reconciliation succeeds.
  final bool remindersReconciled;
  final String? retryMessage;
  final String? failure, failureCode;
}
