import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_item.dart';
import '../models/operation_models.dart';
import 'file_service.dart';

class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      for (final listener in _listeners) {
        listener();
      }
    }
  }
}

typedef ConflictHandler = Future<ConflictResolutionResult> Function(
  String sourcePath,
  String targetPath,
  bool isDirectory,
);

typedef LogCallback = void Function(LogEntry entry);
typedef ProgressCallback = void Function(double progress, String currentItem, int bytesDone, int totalBytes);

class OperationService {
  static const int chunkSize = 64 * 1024; // 64 KB

  /// Recursively counts total bytes for a list of file/directory paths.
  static Future<int> calculateTotalBytes(List<String> paths) async {
    int total = 0;
    for (final path in paths) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          final stat = await File(path).stat();
          total += stat.size;
        } else if (type == FileSystemEntityType.directory) {
          await for (final entity in Directory(path).list(recursive: true, followLinks: false)) {
            if (entity is File) {
              try {
                final stat = await entity.stat();
                total += stat.size;
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
    return total;
  }

  /// Copies a list of items to [destinationDir].
  static Future<OperationSummary> copyItems({
    required List<String> sourcePaths,
    required String destinationDir,
    required CancellationToken cancellationToken,
    required ConflictHandler onConflict,
    required LogCallback onLog,
    required ProgressCallback onProgress,
  }) async {
    int succeeded = 0;
    int skipped = 0;
    int failed = 0;
    ConflictResolutionResult? globalConflictResult;

    final destDir = Directory(destinationDir);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    onLog(LogEntry('\$ copy ${sourcePaths.length} item(s) -> $destinationDir', level: LogLevel.command));

    final totalBytes = await calculateTotalBytes(sourcePaths);
    int totalBytesDone = 0;

    for (int i = 0; i < sourcePaths.length; i++) {
      if (cancellationToken.isCancelled) {
        onLog(LogEntry('> Operation cancelled by user.', level: LogLevel.warning));
        break;
      }

      final src = sourcePaths[i];
      final srcName = p.basename(src);

      try {
        final type = await FileSystemEntity.type(src, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          onLog(LogEntry('[ERROR] Source not found: $src', level: LogLevel.error));
          failed++;
          continue;
        }

        final isDir = type == FileSystemEntityType.directory;

        // Block copying folder into itself or its own subfolder
        if (isDir && FileService.isSubfolder(src, destinationDir)) {
          onLog(LogEntry(
            '[ERROR] Cannot copy folder "$srcName" into itself or its own subfolder ($destinationDir).',
            level: LogLevel.error,
          ));
          failed++;
          continue;
        }

        String targetName = srcName;
        final targetPath = p.join(destinationDir, targetName);

        // Check for conflict
        final hasConflict = await FileService.checkNameConflict(destinationDir, targetName);
        if (hasConflict) {
          ConflictResolutionResult resolution;
          if (globalConflictResult != null && globalConflictResult.applyToAll) {
            resolution = globalConflictResult;
          } else {
            resolution = await onConflict(src, targetPath, isDir);
            if (resolution.applyToAll) {
              globalConflictResult = resolution;
            }
          }

          if (resolution.action == ConflictAction.skip) {
            onLog(LogEntry('> Skipped: $srcName (conflict)', level: LogLevel.warning));
            skipped++;
            continue;
          } else if (resolution.action == ConflictAction.keepBoth) {
            targetName = await FileService.generateNonConflictingName(destinationDir, srcName);
            onLog(LogEntry('> Renamed copy to: $targetName', level: LogLevel.info));
          } else if (resolution.action == ConflictAction.replace) {
            onLog(LogEntry('> Replacing existing: $targetName', level: LogLevel.warning));
            final existingTarget = p.join(destinationDir, targetName);
            await FileService.deleteEntity(existingTarget);
          }
        }

        final finalTargetPath = p.join(destinationDir, targetName);

        if (isDir) {
          final res = await _copyDirectoryRecursive(
            sourceDir: Directory(src),
            targetDir: Directory(finalTargetPath),
            cancellationToken: cancellationToken,
            onLog: onLog,
            onBytesCopied: (bytes) {
              totalBytesDone += bytes;
              final progress = totalBytes > 0 ? (totalBytesDone / totalBytes).clamp(0.0, 1.0) : 0.0;
              onProgress(progress, srcName, totalBytesDone, totalBytes);
            },
          );
          if (res) {
            succeeded++;
            onLog(LogEntry('> Completed folder: $srcName', level: LogLevel.success));
          } else {
            if (cancellationToken.isCancelled) break;
            failed++;
          }
        } else {
          final stat = await File(src).stat();
          final sizeFormatted = FileItem.fromFileSystemEntity(File(src), stat: stat).size;
          onLog(LogEntry('> Copying: $srcName ($sizeFormatted)', level: LogLevel.info));

          final res = await _copyFileStream(
            sourceFile: File(src),
            targetFile: File(finalTargetPath),
            fileSize: stat.size,
            cancellationToken: cancellationToken,
            onLog: onLog,
            onBytesCopied: (bytes) {
              totalBytesDone += bytes;
              final progress = totalBytes > 0 ? (totalBytesDone / totalBytes).clamp(0.0, 1.0) : 0.0;
              onProgress(progress, srcName, totalBytesDone, totalBytes);
            },
          );
          if (res) {
            succeeded++;
            onLog(LogEntry('> Completed: $srcName', level: LogLevel.success));
          } else {
            if (cancellationToken.isCancelled) break;
            failed++;
          }
        }
      } catch (e) {
        onLog(LogEntry('[ERROR] Failed copying $srcName: $e', level: LogLevel.error));
        failed++;
      }
    }

    final summary = OperationSummary(
      total: sourcePaths.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: failed,
    );

    onLog(LogEntry(
      '> Summary: ${summary.succeeded} succeeded, ${summary.skipped} skipped, ${summary.failed} failed.',
      level: summary.failed == 0 ? LogLevel.success : LogLevel.warning,
    ));

    return summary;
  }

  /// Moves a list of items to [destinationDir].
  static Future<OperationSummary> moveItems({
    required List<String> sourcePaths,
    required String destinationDir,
    required CancellationToken cancellationToken,
    required ConflictHandler onConflict,
    required LogCallback onLog,
    required ProgressCallback onProgress,
  }) async {
    int succeeded = 0;
    int skipped = 0;
    int failed = 0;
    ConflictResolutionResult? globalConflictResult;

    final destDir = Directory(destinationDir);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    onLog(LogEntry('\$ move ${sourcePaths.length} item(s) -> $destinationDir', level: LogLevel.command));

    final totalBytes = await calculateTotalBytes(sourcePaths);
    int totalBytesDone = 0;

    for (int i = 0; i < sourcePaths.length; i++) {
      if (cancellationToken.isCancelled) {
        onLog(LogEntry('> Operation cancelled by user.', level: LogLevel.warning));
        break;
      }

      final src = sourcePaths[i];
      final srcName = p.basename(src);

      try {
        final type = await FileSystemEntity.type(src, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          onLog(LogEntry('[ERROR] Source not found: $src', level: LogLevel.error));
          failed++;
          continue;
        }

        final isDir = type == FileSystemEntityType.directory;

        // Block moving folder into itself or its own subfolder
        if (isDir && FileService.isSubfolder(src, destinationDir)) {
          onLog(LogEntry(
            '[ERROR] Cannot move folder "$srcName" into itself or its own subfolder ($destinationDir).',
            level: LogLevel.error,
          ));
          failed++;
          continue;
        }

        String targetName = srcName;
        final targetPath = p.join(destinationDir, targetName);

        // Check if moving to exact same location
        if (FileService.isSamePath(src, targetPath)) {
          onLog(LogEntry('> Skipped: $srcName (source and destination are the same)', level: LogLevel.warning));
          skipped++;
          continue;
        }

        // Check for conflict
        final hasConflict = await FileService.checkNameConflict(destinationDir, targetName);
        if (hasConflict) {
          ConflictResolutionResult resolution;
          if (globalConflictResult != null && globalConflictResult.applyToAll) {
            resolution = globalConflictResult;
          } else {
            resolution = await onConflict(src, targetPath, isDir);
            if (resolution.applyToAll) {
              globalConflictResult = resolution;
            }
          }

          if (resolution.action == ConflictAction.skip) {
            onLog(LogEntry('> Skipped: $srcName (conflict)', level: LogLevel.warning));
            skipped++;
            continue;
          } else if (resolution.action == ConflictAction.keepBoth) {
            targetName = await FileService.generateNonConflictingName(destinationDir, srcName);
            onLog(LogEntry('> Renamed destination to: $targetName', level: LogLevel.info));
          } else if (resolution.action == ConflictAction.replace) {
            onLog(LogEntry('> Replacing existing: $targetName', level: LogLevel.warning));
            final existingTarget = p.join(destinationDir, targetName);
            await FileService.deleteEntity(existingTarget);
          }
        }

        final finalTargetPath = p.join(destinationDir, targetName);
        onLog(LogEntry('> Moving: $srcName -> $targetName', level: LogLevel.info));

        // Fast path: try atomic rename
        bool movedFast = false;
        try {
          if (isDir) {
            await Directory(src).rename(finalTargetPath);
          } else {
            await File(src).rename(finalTargetPath);
          }
          movedFast = true;
        } catch (_) {
          movedFast = false;
        }

        if (movedFast) {
          succeeded++;
          final stat = isDir ? null : await File(finalTargetPath).stat();
          final bytes = stat?.size ?? 0;
          totalBytesDone += bytes;
          final progress = totalBytes > 0 ? (totalBytesDone / totalBytes).clamp(0.0, 1.0) : 1.0;
          onProgress(progress, srcName, totalBytesDone, totalBytes);
          onLog(LogEntry('> Moved: $srcName', level: LogLevel.success));
        } else {
          // Slow path: copy then delete source
          onLog(LogEntry('> Fast move failed (cross-volume/device), copying stream...', level: LogLevel.info));
          bool copySuccess = false;
          if (isDir) {
            copySuccess = await _copyDirectoryRecursive(
              sourceDir: Directory(src),
              targetDir: Directory(finalTargetPath),
              cancellationToken: cancellationToken,
              onLog: onLog,
              onBytesCopied: (bytes) {
                totalBytesDone += bytes;
                final progress = totalBytes > 0 ? (totalBytesDone / totalBytes).clamp(0.0, 1.0) : 0.0;
                onProgress(progress, srcName, totalBytesDone, totalBytes);
              },
            );
          } else {
            final stat = await File(src).stat();
            copySuccess = await _copyFileStream(
              sourceFile: File(src),
              targetFile: File(finalTargetPath),
              fileSize: stat.size,
              cancellationToken: cancellationToken,
              onLog: onLog,
              onBytesCopied: (bytes) {
                totalBytesDone += bytes;
                final progress = totalBytes > 0 ? (totalBytesDone / totalBytes).clamp(0.0, 1.0) : 0.0;
                onProgress(progress, srcName, totalBytesDone, totalBytes);
              },
            );
          }

          if (copySuccess) {
            // Delete source only after copy succeeded
            await FileService.deleteEntity(src);
            succeeded++;
            onLog(LogEntry('> Moved (copy+delete): $srcName', level: LogLevel.success));
          } else {
            if (cancellationToken.isCancelled) break;
            failed++;
          }
        }
      } catch (e) {
        onLog(LogEntry('[ERROR] Failed moving $srcName: $e', level: LogLevel.error));
        failed++;
      }
    }

    final summary = OperationSummary(
      total: sourcePaths.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: failed,
    );

    onLog(LogEntry(
      '> Summary: ${summary.succeeded} succeeded, ${summary.skipped} skipped, ${summary.failed} failed.',
      level: summary.failed == 0 ? LogLevel.success : LogLevel.warning,
    ));

    return summary;
  }

  /// Deletes a list of items.
  static Future<OperationSummary> deleteItems({
    required List<String> paths,
    required CancellationToken cancellationToken,
    required LogCallback onLog,
    required ProgressCallback onProgress,
  }) async {
    int succeeded = 0;
    int failed = 0;

    onLog(LogEntry('\$ rm -rf ${paths.length} item(s)', level: LogLevel.command));

    for (int i = 0; i < paths.length; i++) {
      if (cancellationToken.isCancelled) {
        onLog(LogEntry('> Operation cancelled by user.', level: LogLevel.warning));
        break;
      }

      final targetPath = paths[i];
      final name = p.basename(targetPath);

      try {
        onLog(LogEntry('> Deleting: $name', level: LogLevel.info));
        await FileService.deleteEntity(targetPath);
        succeeded++;
        onLog(LogEntry('> Deleted: $name', level: LogLevel.success));
      } catch (e) {
        onLog(LogEntry('[ERROR] Failed deleting $name: $e', level: LogLevel.error));
        failed++;
      }

      final progress = paths.isNotEmpty ? ((i + 1) / paths.length).clamp(0.0, 1.0) : 1.0;
      onProgress(progress, name, i + 1, paths.length);
    }

    final summary = OperationSummary(
      total: paths.length,
      succeeded: succeeded,
      skipped: 0,
      failed: failed,
    );

    onLog(LogEntry(
      '> Summary: ${summary.succeeded} deleted, ${summary.failed} failed.',
      level: summary.failed == 0 ? LogLevel.success : LogLevel.warning,
    ));

    return summary;
  }

  /// Copies a file using chunked async streams with cancellation support.
  static Future<bool> _copyFileStream({
    required File sourceFile,
    required File targetFile,
    required int fileSize,
    required CancellationToken cancellationToken,
    required LogCallback onLog,
    required void Function(int bytes) onBytesCopied,
  }) async {
    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    int bytesCopiedForFile = 0;
    final completer = Completer<bool>();

    try {
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      sink = targetFile.openWrite(mode: FileMode.write);
      final readStream = sourceFile.openRead();

      DateTime lastProgressLog = DateTime.now();

      subscription = readStream.listen(
        (chunk) {
          if (cancellationToken.isCancelled) {
            subscription?.cancel();
            sink?.close();
            // Clean up partial target
            try {
              if (targetFile.existsSync()) targetFile.deleteSync();
            } catch (_) {}
            if (!completer.isCompleted) completer.complete(false);
            return;
          }

          sink?.add(chunk);
          bytesCopiedForFile += chunk.length;
          onBytesCopied(chunk.length);

          // Emit throttled progress log (every 600ms for large files)
          final now = DateTime.now();
          if (fileSize > 1024 * 1024 && now.difference(lastProgressLog).inMilliseconds > 600) {
            lastProgressLog = now;
            final pct = ((bytesCopiedForFile / fileSize) * 100).toStringAsFixed(0);
            onLog(LogEntry(
              '> Progress: $pct% (${(bytesCopiedForFile / (1024 * 1024)).toStringAsFixed(1)} MB / ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB)',
              level: LogLevel.progress,
            ));
          }
        },
        onDone: () async {
          await sink?.flush();
          await sink?.close();
          if (!completer.isCompleted) completer.complete(true);
        },
        onError: (err) async {
          await sink?.close();
          try {
            if (await targetFile.exists()) await targetFile.delete();
          } catch (_) {}
          onLog(LogEntry('[ERROR] File stream error: $err', level: LogLevel.error));
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: true,
      );

      return await completer.future;
    } catch (e) {
      try {
        await sink?.close();
        if (await targetFile.exists()) await targetFile.delete();
      } catch (_) {}
      onLog(LogEntry('[ERROR] Copy failed: $e', level: LogLevel.error));
      return false;
    }
  }

  /// Copies a directory recursively.
  static Future<bool> _copyDirectoryRecursive({
    required Directory sourceDir,
    required Directory targetDir,
    required CancellationToken cancellationToken,
    required LogCallback onLog,
    required void Function(int bytes) onBytesCopied,
  }) async {
    try {
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      await for (final entity in sourceDir.list(followLinks: false)) {
        if (cancellationToken.isCancelled) return false;

        final relative = p.relative(entity.path, from: sourceDir.path);
        final newTargetPath = p.join(targetDir.path, relative);

        if (entity is Directory) {
          final res = await _copyDirectoryRecursive(
            sourceDir: entity,
            targetDir: Directory(newTargetPath),
            cancellationToken: cancellationToken,
            onLog: onLog,
            onBytesCopied: onBytesCopied,
          );
          if (!res) return false;
        } else if (entity is File) {
          final stat = await entity.stat();
          final res = await _copyFileStream(
            sourceFile: entity,
            targetFile: File(newTargetPath),
            fileSize: stat.size,
            cancellationToken: cancellationToken,
            onLog: onLog,
            onBytesCopied: onBytesCopied,
          );
          if (!res) return false;
        }
      }

      return true;
    } catch (e) {
      onLog(LogEntry('[ERROR] Recursive folder copy error: $e', level: LogLevel.error));
      return false;
    }
  }
}
