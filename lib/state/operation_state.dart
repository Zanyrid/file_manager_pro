import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/operation_models.dart';
import '../services/operation_service.dart';
import '../services/zip_service.dart';
import '../widgets/conflict_dialog.dart';
import 'app_state.dart';

/// Clipboard state provider
final clipboardProvider =
    StateNotifierProvider<ClipboardNotifier, ClipboardState>((ref) {
  return ClipboardNotifier();
});

class ClipboardNotifier extends StateNotifier<ClipboardState> {
  ClipboardNotifier() : super(const ClipboardState());

  void copy(List<String> paths) {
    state = ClipboardState(paths: List.from(paths), mode: ClipboardMode.copy);
  }

  void cut(List<String> paths) {
    state = ClipboardState(paths: List.from(paths), mode: ClipboardMode.cut);
  }

  void clear() {
    state = const ClipboardState();
  }
}

/// Operation state model
class OperationState {
  final OperationType? type;
  final OperationStatus status;
  final double progress;
  final String? currentItem;
  final int bytesDone;
  final int totalBytes;
  final List<LogEntry> logs;
  final OperationSummary? summary;
  final bool isTerminalOpen;
  final CancellationToken? cancellationToken;

  const OperationState({
    this.type,
    this.status = OperationStatus.idle,
    this.progress = 0.0,
    this.currentItem,
    this.bytesDone = 0,
    this.totalBytes = 0,
    this.logs = const [],
    this.summary,
    this.isTerminalOpen = false,
    this.cancellationToken,
  });

  bool get isRunning => status == OperationStatus.running;

  OperationState copyWith({
    OperationType? type,
    OperationStatus? status,
    double? progress,
    String? currentItem,
    int? bytesDone,
    int? totalBytes,
    List<LogEntry>? logs,
    OperationSummary? summary,
    bool? isTerminalOpen,
    CancellationToken? cancellationToken,
  }) {
    return OperationState(
      type: type ?? this.type,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentItem: currentItem ?? this.currentItem,
      bytesDone: bytesDone ?? this.bytesDone,
      totalBytes: totalBytes ?? this.totalBytes,
      logs: logs ?? this.logs,
      summary: summary ?? this.summary,
      isTerminalOpen: isTerminalOpen ?? this.isTerminalOpen,
      cancellationToken: cancellationToken ?? this.cancellationToken,
    );
  }
}

/// Operation state notifier
final operationNotifierProvider =
    StateNotifierProvider<OperationNotifier, OperationState>((ref) {
  return OperationNotifier(ref);
});

class OperationNotifier extends StateNotifier<OperationState> {
  final Ref ref;
  static const int maxLogs = 5000;

  OperationNotifier(this.ref) : super(const OperationState());

  void openTerminal() {
    state = state.copyWith(isTerminalOpen: true);
  }

  void closeTerminal() {
    state = state.copyWith(isTerminalOpen: false);
    // Refresh current directory when returning from terminal
    ref.read(fileListNotifierProvider.notifier).loadFiles();
  }

  void _addLog(LogEntry entry) {
    final updated = List<LogEntry>.from(state.logs)..add(entry);
    if (updated.length > maxLogs) {
      updated.removeRange(0, updated.length - maxLogs);
    }
    state = state.copyWith(logs: updated);
  }

  void cancel() {
    state.cancellationToken?.cancel();
    state = state.copyWith(status: OperationStatus.cancelled);
    _addLog(LogEntry('> Cancellation requested...', level: LogLevel.warning));
  }

  Future<void> startCopy({
    required List<String> sourcePaths,
    required String destinationDir,
    required BuildContext context,
  }) async {
    if (state.isRunning) return;

    final cancelToken = CancellationToken();
    state = OperationState(
      type: OperationType.copy,
      status: OperationStatus.running,
      progress: 0.0,
      isTerminalOpen: true,
      cancellationToken: cancelToken,
      logs: [],
    );

    _addLog(LogEntry('=== STARTING COPY OPERATION ===', level: LogLevel.info));

    try {
      final summary = await OperationService.copyItems(
        sourcePaths: sourcePaths,
        destinationDir: destinationDir,
        cancellationToken: cancelToken,
        onConflict: (src, target, isDir) async {
          if (!context.mounted) {
            return const ConflictResolutionResult(action: ConflictAction.skip);
          }
          final res = await ConflictDialog.show(
            context,
            sourcePath: src,
            targetPath: target,
            isDirectory: isDir,
          );
          return res ?? const ConflictResolutionResult(action: ConflictAction.skip);
        },
        onLog: _addLog,
        onProgress: (prog, item, bytesDone, totalBytes) {
          state = state.copyWith(
            progress: prog,
            currentItem: item,
            bytesDone: bytesDone,
            totalBytes: totalBytes,
          );
        },
      );

      final finalStatus = cancelToken.isCancelled
          ? OperationStatus.cancelled
          : (summary.failed > 0 ? OperationStatus.error : OperationStatus.done);

      state = state.copyWith(
        status: finalStatus,
        summary: summary,
        progress: 1.0,
      );

      _addLog(LogEntry('=== COPY FINISHED ===', level: LogLevel.info));
    } catch (e) {
      _addLog(LogEntry('[ERROR] Unhandled copy exception: $e', level: LogLevel.error));
      state = state.copyWith(status: OperationStatus.error);
    }
  }

  Future<void> startMove({
    required List<String> sourcePaths,
    required String destinationDir,
    required BuildContext context,
  }) async {
    if (state.isRunning) return;

    final cancelToken = CancellationToken();
    state = OperationState(
      type: OperationType.move,
      status: OperationStatus.running,
      progress: 0.0,
      isTerminalOpen: true,
      cancellationToken: cancelToken,
      logs: [],
    );

    _addLog(LogEntry('=== STARTING MOVE OPERATION ===', level: LogLevel.info));

    try {
      final summary = await OperationService.moveItems(
        sourcePaths: sourcePaths,
        destinationDir: destinationDir,
        cancellationToken: cancelToken,
        onConflict: (src, target, isDir) async {
          if (!context.mounted) {
            return const ConflictResolutionResult(action: ConflictAction.skip);
          }
          final res = await ConflictDialog.show(
            context,
            sourcePath: src,
            targetPath: target,
            isDirectory: isDir,
          );
          return res ?? const ConflictResolutionResult(action: ConflictAction.skip);
        },
        onLog: _addLog,
        onProgress: (prog, item, bytesDone, totalBytes) {
          state = state.copyWith(
            progress: prog,
            currentItem: item,
            bytesDone: bytesDone,
            totalBytes: totalBytes,
          );
        },
      );

      final finalStatus = cancelToken.isCancelled
          ? OperationStatus.cancelled
          : (summary.failed > 0 ? OperationStatus.error : OperationStatus.done);

      state = state.copyWith(
        status: finalStatus,
        summary: summary,
        progress: 1.0,
      );

      // If cut was successful, clear clipboard
      if (!cancelToken.isCancelled && summary.failed == 0) {
        ref.read(clipboardProvider.notifier).clear();
      }

      _addLog(LogEntry('=== MOVE FINISHED ===', level: LogLevel.info));
    } catch (e) {
      _addLog(LogEntry('[ERROR] Unhandled move exception: $e', level: LogLevel.error));
      state = state.copyWith(status: OperationStatus.error);
    }
  }

  Future<void> startDelete({
    required List<String> paths,
  }) async {
    if (state.isRunning) return;

    final cancelToken = CancellationToken();
    state = OperationState(
      type: OperationType.delete,
      status: OperationStatus.running,
      progress: 0.0,
      isTerminalOpen: true,
      cancellationToken: cancelToken,
      logs: [],
    );

    // Clear selection
    ref.read(selectedFilesProvider.notifier).clear();

    _addLog(LogEntry('=== STARTING DELETE OPERATION ===', level: LogLevel.info));

    try {
      final summary = await OperationService.deleteItems(
        paths: paths,
        cancellationToken: cancelToken,
        onLog: _addLog,
        onProgress: (prog, item, done, total) {
          state = state.copyWith(
            progress: prog,
            currentItem: item,
            bytesDone: done,
            totalBytes: total,
          );
        },
      );

      final finalStatus = cancelToken.isCancelled
          ? OperationStatus.cancelled
          : (summary.failed > 0 ? OperationStatus.error : OperationStatus.done);

      state = state.copyWith(
        status: finalStatus,
        summary: summary,
        progress: 1.0,
      );

      _addLog(LogEntry('=== DELETE FINISHED ===', level: LogLevel.info));
    } catch (e) {
      _addLog(LogEntry('[ERROR] Unhandled delete exception: $e', level: LogLevel.error));
      state = state.copyWith(status: OperationStatus.error);
    }
  }

  Future<void> startExtractZip({
    required String zipPath,
    required String destinationDir,
    Map<String, ConflictAction> conflictMap = const {},
  }) async {
    if (state.isRunning) return;

    final cancelToken = CancellationToken();
    state = OperationState(
      type: OperationType.extract,
      status: OperationStatus.running,
      progress: 0.0,
      isTerminalOpen: true,
      cancellationToken: cancelToken,
      logs: [],
    );

    // Clear selection
    ref.read(selectedFilesProvider.notifier).clear();

    _addLog(LogEntry('=== STARTING ZIP EXTRACTION ===', level: LogLevel.info));

    try {
      final summary = await ZipService.extractZip(
        zipPath: zipPath,
        destinationDir: destinationDir,
        conflictMap: conflictMap,
        cancellationToken: cancelToken,
        onLog: _addLog,
        onProgress: (prog, item, bytesDone, totalBytes) {
          state = state.copyWith(
            progress: prog,
            currentItem: item,
            bytesDone: bytesDone,
            totalBytes: totalBytes,
          );
        },
      );

      final OperationStatus finalStatus;
      if (cancelToken.isCancelled) {
        finalStatus = OperationStatus.cancelled;
      } else if (summary.failed > 0) {
        finalStatus = OperationStatus.error;
      } else if (summary.succeeded > 0) {
        finalStatus = OperationStatus.done;
      } else {
        // Nothing extracted (all skipped, or invalid archive)
        finalStatus = OperationStatus.error;
      }

      state = state.copyWith(
        status: finalStatus,
        summary: summary,
        progress: 1.0,
      );

      _addLog(LogEntry('=== EXTRACTION FINISHED ===', level: LogLevel.info));
    } catch (e) {
      _addLog(LogEntry('[ERROR] Unhandled extraction exception: $e', level: LogLevel.error));
      state = state.copyWith(
        status: OperationStatus.error,
        summary: const OperationSummary(total: 0, succeeded: 0, skipped: 0, failed: 1),
      );
    }
  }

  Future<void> startCompressZip({
    required List<String> sourcePaths,
    required String outputZipPath,
  }) async {
    if (state.isRunning) return;

    final cancelToken = CancellationToken();
    state = OperationState(
      type: OperationType.compress,
      status: OperationStatus.running,
      progress: 0.0,
      isTerminalOpen: true,
      cancellationToken: cancelToken,
      logs: [],
    );

    // Clear selection
    ref.read(selectedFilesProvider.notifier).clear();

    _addLog(LogEntry('=== STARTING ZIP COMPRESSION ===', level: LogLevel.info));

    try {
      final summary = await ZipService.compressToZip(
        sourcePaths: sourcePaths,
        outputZipPath: outputZipPath,
        cancellationToken: cancelToken,
        onLog: _addLog,
        onProgress: (prog, item, bytesDone, totalBytes) {
          state = state.copyWith(
            progress: prog,
            currentItem: item,
            bytesDone: bytesDone,
            totalBytes: totalBytes,
          );
        },
      );

      final OperationStatus finalStatus;
      if (cancelToken.isCancelled) {
        finalStatus = OperationStatus.cancelled;
      } else if (summary.failed > 0 && summary.succeeded == 0) {
        finalStatus = OperationStatus.error;
      } else if (summary.succeeded > 0) {
        finalStatus = OperationStatus.done;
      } else {
        finalStatus = OperationStatus.error;
      }

      state = state.copyWith(
        status: finalStatus,
        summary: summary,
        progress: 1.0,
      );

      _addLog(LogEntry('=== COMPRESSION FINISHED ===', level: LogLevel.info));
    } catch (e) {
      _addLog(LogEntry('[ERROR] Unhandled compression exception: $e', level: LogLevel.error));
      state = state.copyWith(
        status: OperationStatus.error,
        summary: const OperationSummary(total: 0, succeeded: 0, skipped: 0, failed: 1),
      );
    }
  }
}

