import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../models/operation_models.dart';
import 'file_service.dart';
import 'operation_service.dart';

class ZipInspectionResult {
  final bool isValid;
  final String? errorMessage;
  final List<String> conflictingFileEntries;
  final int totalEntries;
  final int totalBytes;

  const ZipInspectionResult({
    required this.isValid,
    this.errorMessage,
    this.conflictingFileEntries = const [],
    this.totalEntries = 0,
    this.totalBytes = 0,
  });
}

class ZipService {
  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Inspects a ZIP archive before extraction to validate format and detect conflicting files.
  static Future<ZipInspectionResult> inspectArchive(
    String zipPath,
    String destinationDir,
  ) async {
    final file = File(zipPath);
    if (!file.existsSync() || file.lengthSync() < 22) {
      return const ZipInspectionResult(
        isValid: false,
        errorMessage: 'Error: not a valid ZIP file or the archive is corrupted',
      );
    }

    InputFileStream? input;
    try {
      input = InputFileStream(zipPath);
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);

      if (archive.numberOfFiles() == 0 || archive.files.isEmpty) {
        return const ZipInspectionResult(
          isValid: false,
          errorMessage: 'Error: not a valid ZIP file or the archive is corrupted',
        );
      }

      final destCanonical = p.canonicalize(destinationDir);
      final conflicts = <String>[];
      int totalBytes = 0;

      for (final entry in archive.files) {
        totalBytes += entry.size;

        // Check conflicts only for regular files (folders are merged silently, symlinks are skipped)
        if (entry.isFile && !entry.isSymbolicLink) {
          final normRel = p.normalize(entry.name);
          final targetPath = p.normalize(p.join(destCanonical, normRel));
          final targetCanonical = p.canonicalize(targetPath);

          // Zip-slip entries will be blocked during extraction
          if (p.isWithin(destCanonical, targetCanonical) || targetCanonical == destCanonical) {
            if (File(targetPath).existsSync()) {
              conflicts.add(entry.name);
            }
          }
        }
      }

      return ZipInspectionResult(
        isValid: true,
        conflictingFileEntries: conflicts,
        totalEntries: archive.numberOfFiles(),
        totalBytes: totalBytes,
      );
    } catch (e) {
      return const ZipInspectionResult(
        isValid: false,
        errorMessage: 'Error: not a valid ZIP file or the archive is corrupted',
      );
    } finally {
      try {
        await input?.close();
      } catch (_) {}
    }
  }

  /// Extracts a ZIP archive to [destinationDir] using an Isolate and streaming I/O.
  static Future<OperationSummary> extractZip({
    required String zipPath,
    required String destinationDir,
    required Map<String, ConflictAction> conflictMap,
    required CancellationToken cancellationToken,
    required LogCallback onLog,
    required ProgressCallback onProgress,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<OperationSummary>();
    SendPort? workerSendPort;
    Isolate? isolate;

    cancellationToken.addListener(() {
      workerSendPort?.send({'type': 'cancel'});
    });

    receivePort.listen((message) async {
      if (message is Map) {
        final type = message['type'];
        if (type == 'init') {
          workerSendPort = message['sendPort'] as SendPort;
          if (cancellationToken.isCancelled) {
            workerSendPort?.send({'type': 'cancel'});
          } else {
            workerSendPort?.send({
              'type': 'start',
              'zipPath': zipPath,
              'destinationDir': destinationDir,
              'conflictMap': conflictMap.map((k, v) => MapEntry(k, v.index)),
            });
          }
        } else if (type == 'log') {
          final text = message['text'] as String;
          final level = LogLevel.values[message['level'] as int];
          onLog(LogEntry(text, level: level));
        } else if (type == 'progress') {
          final progress = (message['progress'] as num).toDouble();
          final currentItem = message['currentItem'] as String;
          final bytesDone = message['bytesDone'] as int;
          final totalBytes = message['totalBytes'] as int;
          onProgress(progress, currentItem, bytesDone, totalBytes);
        } else if (type == 'done') {
          final summary = OperationSummary(
            total: message['total'] as int,
            succeeded: message['succeeded'] as int,
            skipped: message['skipped'] as int,
            failed: message['failed'] as int,
          );
          if (!completer.isCompleted) {
            completer.complete(summary);
          }
          receivePort.close();
          isolate?.kill(priority: Isolate.immediate);
        }
      }
    });

    isolate = await Isolate.spawn(_zipWorker, receivePort.sendPort);

    return completer.future;
  }

  /// Compresses files/folders into a ZIP archive using an Isolate and streaming I/O.
  static Future<OperationSummary> compressToZip({
    required List<String> sourcePaths,
    required String outputZipPath,
    required CancellationToken cancellationToken,
    required LogCallback onLog,
    required ProgressCallback onProgress,
    int compressionLevel = 6,
    bool deleteSourceFiles = false,
    List<({List<String> sourcePaths, String outputZipPath})>? batchTasks,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<OperationSummary>();
    SendPort? workerSendPort;
    Isolate? isolate;

    cancellationToken.addListener(() {
      workerSendPort?.send({'type': 'cancel'});
    });

    receivePort.listen((message) async {
      if (message is Map) {
        final type = message['type'];
        if (type == 'init') {
          workerSendPort = message['sendPort'] as SendPort;
          if (cancellationToken.isCancelled) {
            workerSendPort?.send({'type': 'cancel'});
          } else {
            final tasksPayload = batchTasks?.map((t) => {
              'sourcePaths': t.sourcePaths,
              'outputZipPath': t.outputZipPath,
            }).toList();

            workerSendPort?.send({
              'type': 'start',
              'sourcePaths': sourcePaths,
              'outputZipPath': outputZipPath,
              'tasks': tasksPayload,
              'compressionLevel': compressionLevel,
              'deleteSourceFiles': deleteSourceFiles,
            });
          }
        } else if (type == 'log') {
          final text = message['text'] as String;
          final level = LogLevel.values[message['level'] as int];
          onLog(LogEntry(text, level: level));
        } else if (type == 'progress') {
          final progress = (message['progress'] as num).toDouble();
          final currentItem = message['currentItem'] as String;
          final bytesDone = message['bytesDone'] as int;
          final totalBytes = message['totalBytes'] as int;
          onProgress(progress, currentItem, bytesDone, totalBytes);
        } else if (type == 'done') {
          final summary = OperationSummary(
            total: message['total'] as int,
            succeeded: message['succeeded'] as int,
            skipped: message['skipped'] as int,
            failed: message['failed'] as int,
          );
          if (!completer.isCompleted) {
            completer.complete(summary);
          }
          receivePort.close();
          isolate?.kill(priority: Isolate.immediate);
        }
      }
    });

    isolate = await Isolate.spawn(_compressWorker, receivePort.sendPort);

    return completer.future;
  }
}


/// Helper to estimate available free disk space where the platform allows.
Future<int?> _checkFreeDiskSpace(String targetPath) async {
  try {
    if (Platform.isWindows) {
      final driveLetter = targetPath.length >= 2 && targetPath[1] == ':'
          ? targetPath[0]
          : 'C';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(Get-PSDrive '$driveLetter').Free",
      ]);
      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim();
        return int.tryParse(out);
      }
    } else if (Platform.isLinux || Platform.isAndroid) {
      final result = await Process.run('stat', ['-f', '-c', '%a %s', targetPath]);
      if (result.exitCode == 0) {
        final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final avail = int.tryParse(parts[0]);
          final bsize = int.tryParse(parts[1]);
          if (avail != null && bsize != null) {
            return avail * bsize;
          }
        }
      }
    }
  } catch (_) {}
  return null;
}

/// Top-level worker function running inside an Isolate.
void _zipWorker(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  mainSendPort.send({'type': 'init', 'sendPort': workerReceivePort.sendPort});

  bool isCancelled = false;
  String? currentWritingPath;
  OutputFileStream? currentOutputFileStream;

  void sendLog(String text, LogLevel level) {
    mainSendPort.send({
      'type': 'log',
      'text': text,
      'level': level.index,
    });
  }

  void sendProgress(double progress, String currentItem, int bytesDone, int totalBytes) {
    mainSendPort.send({
      'type': 'progress',
      'progress': progress,
      'currentItem': currentItem,
      'bytesDone': bytesDone,
      'totalBytes': totalBytes,
    });
  }

  workerReceivePort.listen((message) async {
    if (message is Map) {
      final type = message['type'];
      if (type == 'cancel') {
        isCancelled = true;
        if (currentOutputFileStream != null) {
          try {
            await currentOutputFileStream!.close();
          } catch (_) {}
          currentOutputFileStream = null;
        }
        if (currentWritingPath != null) {
          try {
            final f = File(currentWritingPath!);
            if (f.existsSync()) {
              f.deleteSync();
            }
          } catch (_) {}
          currentWritingPath = null;
        }
      } else if (type == 'start') {
        final zipPath = message['zipPath'] as String;
        final destinationDir = message['destinationDir'] as String;
        final rawConflictMap = message['conflictMap'] as Map?;
        final conflictMap = <String, ConflictAction>{};
        if (rawConflictMap != null) {
          for (final entry in rawConflictMap.entries) {
            conflictMap[entry.key as String] = ConflictAction.values[entry.value as int];
          }
        }

        final zipName = p.basename(zipPath);
        sendLog('\$ extract $zipName -> $destinationDir', LogLevel.command);
        sendLog('> Reading archive...', LogLevel.info);

        final zipFile = File(zipPath);
        if (!zipFile.existsSync() || zipFile.lengthSync() < 22) {
          sendLog('Error: not a valid ZIP file or the archive is corrupted', LogLevel.error);
          mainSendPort.send({
            'type': 'done',
            'total': 0,
            'succeeded': 0,
            'skipped': 0,
            'failed': 1,
          });
          return;
        }

        InputFileStream? inputStream;
        ZipDecoder? decoder;
        Archive? archive;

        try {
          inputStream = InputFileStream(zipPath);
          decoder = ZipDecoder();
          archive = decoder.decodeStream(inputStream);
        } catch (e) {
          sendLog('Error: not a valid ZIP file or the archive is corrupted', LogLevel.error);
          if (inputStream != null) {
            try {
              await inputStream.close();
            } catch (_) {}
          }
          mainSendPort.send({
            'type': 'done',
            'total': 0,
            'succeeded': 0,
            'skipped': 0,
            'failed': 1,
          });
          return;
        }

        if (archive.numberOfFiles() == 0 || archive.files.isEmpty) {
          sendLog('Error: not a valid ZIP file or the archive is corrupted', LogLevel.error);
          try {
            await inputStream.close();
          } catch (_) {}
          mainSendPort.send({
            'type': 'done',
            'total': 0,
            'succeeded': 0,
            'skipped': 0,
            'failed': 1,
          });
          return;
        }

        final destDir = Directory(destinationDir);
        if (!destDir.existsSync()) {
          try {
            destDir.createSync(recursive: true);
          } catch (e) {
            sendLog('[ERROR] Failed to create destination directory: $e', LogLevel.error);
            try {
              await inputStream.close();
            } catch (_) {}
            mainSendPort.send({
              'type': 'done',
              'total': 0,
              'succeeded': 0,
              'skipped': 0,
              'failed': 1,
            });
            return;
          }
        }
        final destCanonical = p.canonicalize(destinationDir);

        final totalEntries = archive.numberOfFiles();
        int totalUncompressedBytes = 0;
        for (final f in archive.files) {
          totalUncompressedBytes += f.size;
        }

        // Check storage space where detectable
        final freeSpace = await _checkFreeDiskSpace(destinationDir);
        if (freeSpace != null && freeSpace < totalUncompressedBytes) {
          sendLog(
            '[ERROR] Insufficient storage: required ${ZipService._formatBytes(totalUncompressedBytes)}, available ${ZipService._formatBytes(freeSpace)}.',
            LogLevel.error,
          );
          try {
            await inputStream.close();
          } catch (_) {}
          mainSendPort.send({
            'type': 'done',
            'total': totalEntries,
            'succeeded': 0,
            'skipped': 0,
            'failed': totalEntries,
          });
          return;
        }

        // Map encrypted entries from headers
        final encryptedNames = <String>{};
        try {
          for (final zfh in decoder.directory.fileHeaders) {
            if ((zfh.generalPurposeBitFlag & 0x1) != 0 || zfh.compressionMethod == 99) {
              encryptedNames.add(zfh.filename);
            }
          }
        } catch (_) {}

        int succeeded = 0;
        int skipped = 0;
        int failed = 0;
        int entriesDone = 0;
        int bytesDone = 0;

        for (final entry in archive.files) {
          if (isCancelled) {
            sendLog('> Cancelled', LogLevel.warning);
            break;
          }

          entriesDone++;
          final entryName = entry.name;
          final entrySize = entry.size;
          final entrySizeFormatted = ZipService._formatBytes(entrySize);

          // 1. Skip symlinks
          if (entry.isSymbolicLink) {
            sendLog('> Skipped: $entryName (symbolic link)', LogLevel.warning);
            skipped++;
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
            continue;
          }

          // 2. Zip-Slip Protection
          final normalizedRelative = p.normalize(entryName);
          final resolvedPath = p.normalize(p.join(destCanonical, normalizedRelative));
          final resolvedCanonical = p.canonicalize(resolvedPath);

          if (!p.isWithin(destCanonical, resolvedCanonical) && resolvedCanonical != destCanonical) {
            sendLog('[ERROR] Zip-slip detected for "$entryName". Extraction blocked for security.', LogLevel.error);
            skipped++;
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
            continue;
          }

          // 3. Create empty folders (existing folders merged silently)
          if (entry.isDirectory || !entry.isFile) {
            try {
              final dir = Directory(resolvedPath);
              if (!dir.existsSync()) {
                dir.createSync(recursive: true);
              }
              succeeded++;
              sendLog('> Created folder: $entryName', LogLevel.info);
            } catch (e) {
              sendLog('[ERROR] Failed creating directory "$entryName": $e', LogLevel.error);
              failed++;
            }
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
            continue;
          }

          // 4. Encrypted entry check
          if (encryptedNames.contains(entryName)) {
            sendLog('> Skipped: $entryName - Encrypted entry not supported', LogLevel.warning);
            skipped++;
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
            continue;
          }

          // 5. Handle pre-resolved conflict decisions
          String targetPath = resolvedPath;
          final targetFile = File(targetPath);

          if (conflictMap.containsKey(entryName)) {
            final action = conflictMap[entryName]!;
            if (action == ConflictAction.skip) {
              sendLog('> Skipped (already exists): $entryName', LogLevel.warning);
              skipped++;
              sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
              continue;
            } else if (action == ConflictAction.keepBoth) {
              targetPath = await FileService.generateNonConflictingName(
                p.dirname(targetPath),
                p.basename(targetPath),
              );
              sendLog('> Renamed entry to: ${p.basename(targetPath)}', LogLevel.info);
            } else if (action == ConflictAction.replace) {
              try {
                if (targetFile.existsSync()) {
                  targetFile.deleteSync();
                }
              } catch (e) {
                sendLog('[ERROR] Failed to replace existing file: $e', LogLevel.error);
                failed++;
                sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
                continue;
              }
            }
          } else if (targetFile.existsSync()) {
            // Overwrite cleanly if replacement wasn't explicitly mapped
            try {
              targetFile.deleteSync();
            } catch (_) {}
          }

          // Check cancellation before file stream
          if (isCancelled) {
            sendLog('> Cancelled', LogLevel.warning);
            break;
          }

          // 6. Ensure parent directory exists
          try {
            final parentDir = Directory(p.dirname(targetPath));
            if (!parentDir.existsSync()) {
              parentDir.createSync(recursive: true);
            }
          } catch (e) {
            sendLog('[ERROR] Failed creating parent folder for "$entryName": $e', LogLevel.error);
            failed++;
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
            continue;
          }

          // Safety check: never extract over the source archive
          if (FileService.isSamePath(zipPath, targetPath)) {
            sendLog('> [ABORT] Cannot extract entry over source archive ($targetPath).', LogLevel.warning);
            skipped++;
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
            continue;
          }

          // 7. Stream file extraction using OutputFileStream
          sendLog('> Extracting: $entryName ($entrySizeFormatted)', LogLevel.info);
          currentWritingPath = targetPath;
          bool writeSuccess = false;

          try {
            final outStream = OutputFileStream(targetPath);
            currentOutputFileStream = outStream;

            try {
              entry.writeContent(outStream, freeMemory: true);
              writeSuccess = true;
            } finally {
              await outStream.close();
              currentOutputFileStream = null;
            }
          } catch (e) {
            writeSuccess = false;
            // Remove partial file being written
            try {
              final f = File(targetPath);
              if (f.existsSync()) {
                f.deleteSync();
              }
            } catch (_) {}

            if (isCancelled) {
              sendLog('> Cancelled', LogLevel.warning);
              break;
            }

            final errStr = e.toString().toLowerCase();
            if (errStr.contains('password') || errStr.contains('encrypt') || errStr.contains('null check')) {
              sendLog('> Skipped: $entryName - Encrypted entry not supported', LogLevel.warning);
              skipped++;
            } else {
              sendLog('[ERROR] Failed extracting "$entryName": $e', LogLevel.error);
              failed++;
            }
          }

          currentWritingPath = null;

          if (writeSuccess) {
            succeeded++;
            bytesDone += entrySize;
            final pct = totalEntries > 0 ? ((entriesDone / totalEntries) * 100).toInt() : 100;
            sendLog('> Progress: $pct% (entry $entriesDone/$totalEntries)', LogLevel.progress);
            sendProgress(entriesDone / totalEntries, entryName, bytesDone, totalUncompressedBytes);
          }
        }

        try {
          await inputStream.close();
        } catch (_) {}

        if (!isCancelled && succeeded > 0) {
          sendLog('> Extraction completed successfully', LogLevel.success);
        }

        final summary = OperationSummary(
          total: totalEntries,
          succeeded: succeeded,
          skipped: skipped,
          failed: failed,
        );

        sendLog(
          '> Summary: ${summary.succeeded} processed / ${summary.skipped} skipped / ${summary.failed} failed.',
          (summary.failed == 0 && summary.succeeded > 0) ? LogLevel.success : LogLevel.warning,
        );

        mainSendPort.send({
          'type': 'done',
          'total': summary.total,
          'succeeded': summary.succeeded,
          'skipped': summary.skipped,
          'failed': summary.failed,
        });
      }
    }
  });
}

/// Top-level compress worker running inside an Isolate.
void _compressWorker(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  mainSendPort.send({'type': 'init', 'sendPort': workerReceivePort.sendPort});

  bool isCancelled = false;

  void sendLog(String text, LogLevel level) {
    mainSendPort.send({
      'type': 'log',
      'text': text,
      'level': level.index,
    });
  }

  void sendProgress(double progress, String currentItem, int bytesDone, int totalBytes) {
    mainSendPort.send({
      'type': 'progress',
      'progress': progress,
      'currentItem': currentItem,
      'bytesDone': bytesDone,
      'totalBytes': totalBytes,
    });
  }

  /// Recursively collects all files and empty directories from a list of source paths.
  /// Returns a list of (path, archivePath, isDirectory) records.
  List<({String path, String archivePath, bool isDirectory})> collectFiles(
    List<String> sourcePaths,
    String outputZipPath, [
    String? tempZipPath,
    void Function(String, LogLevel)? sendLog,
  ]) {
    final result = <({String path, String archivePath, bool isDirectory})>[];
    final outputCanonical = p.canonicalize(outputZipPath);
    final tempCanonical = tempZipPath != null ? p.canonicalize(tempZipPath) : null;

    void walkDirectory(Directory dir, String baseDir, String topLevelName) {
      try {
        final entities = dir.listSync(followLinks: false);
        if (entities.isEmpty) {
          // Empty directory entry
          final relative = p.relative(dir.path, from: baseDir);
          final entryPath = relative == '.'
              ? '$topLevelName/'
              : '${p.join(topLevelName, relative).replaceAll('\\', '/')}/';
          result.add((path: dir.path, archivePath: entryPath, isDirectory: true));
          return;
        }

        for (final entity in entities) {
          try {
            if (entity is File) {
              final entityCanonical = p.canonicalize(entity.path);
              if (entityCanonical == outputCanonical || entityCanonical == tempCanonical) continue;
              final relative = p.relative(entity.path, from: baseDir);
              final entryPath = p.join(topLevelName, relative).replaceAll('\\', '/');
              result.add((path: entity.path, archivePath: entryPath, isDirectory: false));
            } else if (entity is Directory) {
              walkDirectory(entity, baseDir, topLevelName);
            }
          } catch (e) {
            sendLog?.call('[WARNING] Skipping unreadable item "${entity.path}": $e', LogLevel.warning);
          }
        }
      } catch (e) {
        sendLog?.call('[WARNING] Skipping unreadable directory "${dir.path}": $e', LogLevel.warning);
      }
    }

    for (final srcPath in sourcePaths) {
      final srcCanonical = p.canonicalize(srcPath);
      final srcType = FileSystemEntity.typeSync(srcPath, followLinks: false);

      if (srcType == FileSystemEntityType.file) {
        // Skip if this is the output zip itself or temp zip file
        if (srcCanonical == outputCanonical || srcCanonical == tempCanonical) continue;
        final baseName = p.basename(srcPath);
        result.add((path: srcPath, archivePath: baseName, isDirectory: false));
      } else if (srcType == FileSystemEntityType.directory) {
        final dirName = p.basename(srcPath);
        final dir = Directory(srcPath);
        walkDirectory(dir, srcPath, dirName);
      }
    }
    return result;
  }

  workerReceivePort.listen((message) async {
    if (message is Map) {
      final type = message['type'];
      if (type == 'cancel') {
        isCancelled = true;
      } else if (type == 'start') {
        final rawTasks = message['tasks'] as List?;
        final compressionLevel = (message['compressionLevel'] as int?) ?? 6;
        final deleteSourceFiles = (message['deleteSourceFiles'] as bool?) ?? false;

        final List<({List<String> sourcePaths, String outputZipPath})> tasks;
        if (rawTasks != null && rawTasks.isNotEmpty) {
          tasks = rawTasks.map((t) {
            final map = t as Map;
            return (
              sourcePaths: List<String>.from(map['sourcePaths'] as List),
              outputZipPath: map['outputZipPath'] as String,
            );
          }).toList();
        } else {
          tasks = [(
            sourcePaths: List<String>.from(message['sourcePaths'] as List),
            outputZipPath: message['outputZipPath'] as String,
          )];
        }

        int totalSucceeded = 0;
        int totalFailed = 0;
        int totalFilesOverall = 0;
        int globalBytesDone = 0;
        int globalTotalBytes = 0;

        // First calculate total files & bytes across all tasks
        final allTaskFiles = <List<({String path, String archivePath, bool isDirectory})>>[];
        for (final task in tasks) {
          final tempZipPath = p.join(
            p.dirname(task.outputZipPath),
            '.${p.basenameWithoutExtension(task.outputZipPath)}_${DateTime.now().microsecondsSinceEpoch}.tmp.zip',
          );
          final files = collectFiles(task.sourcePaths, task.outputZipPath, tempZipPath, sendLog);
          allTaskFiles.add(files);
          totalFilesOverall += files.length;
          for (final entry in files) {
            if (!entry.isDirectory) {
              try {
                globalTotalBytes += File(entry.path).lengthSync();
              } catch (_) {}
            }
          }
        }

        if (totalFilesOverall == 0) {
          sendLog('[ERROR] No files found to compress.', LogLevel.error);
          mainSendPort.send({
            'type': 'done',
            'total': 0,
            'succeeded': 0,
            'skipped': 0,
            'failed': 0,
          });
          return;
        }

        int overallFileIndex = 0;

        for (int t = 0; t < tasks.length; t++) {
          if (isCancelled) {
            sendLog('> Cancelled', LogLevel.warning);
            break;
          }

          final task = tasks[t];
          final sourcePaths = task.sourcePaths;
          final outputZipPath = task.outputZipPath;
          final outputName = p.basename(outputZipPath);
          final parentDir = p.dirname(outputZipPath);
          final tempZipPath = p.join(
            parentDir,
            '.${p.basenameWithoutExtension(outputName)}_${DateTime.now().microsecondsSinceEpoch}.tmp.zip',
          );

          sendLog('\$ compress ${sourcePaths.length} item(s) -> $outputName', LogLevel.command);
          final filesToCompress = allTaskFiles[t];

          if (filesToCompress.isEmpty) {
            sendLog('[ERROR] No files found for $outputName', LogLevel.error);
            totalFailed++;
            continue;
          }

          int taskSucceeded = 0;
          int taskFailed = 0;
          bool writeSuccess = false;
          ZipFileEncoder? encoder;

          try {
            encoder = ZipFileEncoder();
            encoder.create(tempZipPath, level: compressionLevel);

            for (int i = 0; i < filesToCompress.length; i++) {
              if (isCancelled) {
                sendLog('> Cancelled', LogLevel.warning);
                break;
              }

              final entry = filesToCompress[i];
              if (entry.isDirectory) {
                sendLog('> Adding folder: ${entry.archivePath}', LogLevel.info);
                try {
                  final dirEntryName = entry.archivePath.endsWith('/')
                      ? entry.archivePath
                      : '${entry.archivePath}/';
                  final archiveFile = ArchiveFile(dirEntryName, 0, <int>[]);
                  archiveFile.isFile = false;
                  encoder.addArchiveFile(archiveFile);
                  taskSucceeded++;
                } catch (e) {
                  sendLog('[ERROR] Failed adding folder "${entry.archivePath}": $e', LogLevel.error);
                  taskFailed++;
                }
              } else {
                int fileSize = 0;

                try {
                  fileSize = File(entry.path).lengthSync();
                } catch (_) {}

                final fileSizeFormatted = ZipService._formatBytes(fileSize);
                sendLog('> Adding: ${entry.archivePath} ($fileSizeFormatted)', LogLevel.info);

                try {
                  encoder.addFile(File(entry.path), entry.archivePath, compressionLevel);
                  taskSucceeded++;
                  globalBytesDone += fileSize;
                } catch (e) {
                  sendLog('[ERROR] Failed adding "${entry.archivePath}": $e', LogLevel.error);
                  taskFailed++;
                }
              }

              overallFileIndex++;
              final progress = totalFilesOverall > 0
                  ? (overallFileIndex / totalFilesOverall).clamp(0.0, 1.0)
                  : 1.0;
              final pct = (progress * 100).toInt();
              sendLog('> Progress: $pct% (item $overallFileIndex/$totalFilesOverall)', LogLevel.progress);
              sendProgress(progress, p.basename(entry.path), globalBytesDone, globalTotalBytes);
            }

            encoder.close();
            encoder = null;

            if (!isCancelled && taskSucceeded > 0 && taskFailed == 0) {
              final tempFile = File(tempZipPath);
              if (tempFile.existsSync()) {
                // Verify archive integrity by confirming file exists, valid size, and entry list is readable
                bool isVerified = false;
                try {
                  final fileSize = tempFile.lengthSync();
                  if (fileSize >= 22) {
                    final bytes = tempFile.readAsBytesSync();
                    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
                    final _ = archive.files;
                    isVerified = true;
                  } else {
                    sendLog('[ERROR] Archive file size too small ($fileSize bytes).', LogLevel.error);
                  }
                } catch (e) {
                  sendLog('[ERROR] Archive verification failed for "$outputName": $e', LogLevel.error);
                  isVerified = false;
                }

                if (!isVerified) {
                  sendLog('[ERROR] Created ZIP archive "$outputName" failed integrity verification.', LogLevel.error);
                  taskFailed += taskSucceeded;
                  totalFailed += taskSucceeded;
                  taskSucceeded = 0;
                } else {
                  try {
                    final targetFile = File(outputZipPath);
                    if (targetFile.existsSync()) {
                      targetFile.deleteSync();
                    }
                    tempFile.renameSync(outputZipPath);
                    writeSuccess = true;
                    totalSucceeded += taskSucceeded;
                  } catch (e) {
                    try {
                      tempFile.copySync(outputZipPath);
                      tempFile.deleteSync();
                      writeSuccess = true;
                      totalSucceeded += taskSucceeded;
                    } catch (e2) {
                      sendLog('[ERROR] Failed to finalize ZIP archive: $e2', LogLevel.error);
                      taskFailed += taskSucceeded;
                      totalFailed += taskSucceeded;
                    }
                  }
                }
              } else {
                sendLog('[ERROR] Temporary ZIP file was not created.', LogLevel.error);
                taskFailed += taskSucceeded;
                totalFailed += taskSucceeded;
              }
            } else if (!isCancelled && taskFailed > 0) {
              totalFailed += taskFailed;
              sendLog('[ERROR] Compression of $outputName completed with errors. Original destination left untouched.', LogLevel.error);
            }
          } catch (e) {
            sendLog('[ERROR] ZIP creation error: $e', LogLevel.error);
            try {
              encoder?.close();
            } catch (_) {}
            final unhandled = filesToCompress.length - taskSucceeded - taskFailed;
            totalFailed += unhandled + taskFailed;
          } finally {
            if (!writeSuccess) {
              try {
                final tmp = File(tempZipPath);
                if (tmp.existsSync()) {
                  tmp.deleteSync();
                }
              } catch (_) {}
            }
          }

          if (writeSuccess && taskSucceeded > 0) {
            try {
              final outSize = File(outputZipPath).lengthSync();
              sendLog('> Created: $outputName (${ZipService._formatBytes(outSize)})', LogLevel.success);
            } catch (_) {
              sendLog('> Created: $outputName', LogLevel.success);
            }

            if (deleteSourceFiles) {
              sendLog('> Deleting source files for $outputName...', LogLevel.info);
              for (final srcPath in sourcePaths) {
                try {
                  final type = FileSystemEntity.typeSync(srcPath, followLinks: false);
                  if (type == FileSystemEntityType.directory) {
                    Directory(srcPath).deleteSync(recursive: true);
                    sendLog('> Deleted folder: ${p.basename(srcPath)}', LogLevel.info);
                  } else if (type == FileSystemEntityType.file) {
                    File(srcPath).deleteSync();
                    sendLog('> Deleted file: ${p.basename(srcPath)}', LogLevel.info);
                  }
                } catch (e) {
                  sendLog('[ERROR] Failed to delete source "${p.basename(srcPath)}": $e', LogLevel.error);
                }
              }
            }
          }
        }

        if (isCancelled) {
          sendLog('> Partial ZIP removed.', LogLevel.warning);
        }

        final summary = OperationSummary(
          total: totalFilesOverall,
          succeeded: totalSucceeded,
          skipped: 0,
          failed: totalFailed,
        );

        sendLog(
          '> Summary: ${summary.succeeded} processed / ${summary.skipped} skipped / ${summary.failed} failed.',
          (summary.failed == 0 && summary.succeeded > 0) ? LogLevel.success : LogLevel.warning,
        );

        mainSendPort.send({
          'type': 'done',
          'total': summary.total,
          'succeeded': summary.succeeded,
          'skipped': summary.skipped,
          'failed': summary.failed,
        });
      }
    }
  });
}

