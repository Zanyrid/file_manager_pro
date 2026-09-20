enum ClipboardMode {
  copy,
  cut,
}

class ClipboardState {
  final List<String> paths;
  final ClipboardMode mode;

  const ClipboardState({
    this.paths = const [],
    this.mode = ClipboardMode.copy,
  });

  bool get isEmpty => paths.isEmpty;
  bool get isNotEmpty => paths.isNotEmpty;
  bool get isCut => mode == ClipboardMode.cut;

  ClipboardState copyWith({
    List<String>? paths,
    ClipboardMode? mode,
  }) {
    return ClipboardState(
      paths: paths ?? this.paths,
      mode: mode ?? this.mode,
    );
  }
}

enum LogLevel {
  info,
  command,
  progress,
  success,
  warning,
  error,
}

class LogEntry {
  final String text;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry(
    this.text, {
    this.level = LogLevel.info,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum OperationType {
  copy,
  move,
  delete,
}

enum OperationStatus {
  idle,
  running,
  done,
  error,
  cancelled,
}

enum ConflictAction {
  replace,
  skip,
  keepBoth,
}

class ConflictResolutionResult {
  final ConflictAction action;
  final bool applyToAll;

  const ConflictResolutionResult({
    required this.action,
    this.applyToAll = false,
  });
}

class OperationSummary {
  final int total;
  final int succeeded;
  final int skipped;
  final int failed;

  const OperationSummary({
    this.total = 0,
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
  });
}
