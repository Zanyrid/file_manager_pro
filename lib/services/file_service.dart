import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../models/file_item.dart';
import 'operation_service.dart' show CancellationToken;

enum BubbleType {
  root,
  internalStorage,
  androidData,
  androidObb,
  downloads,
}

class NameConflictException implements Exception {
  final String name;
  final String message;
  NameConflictException(this.name)
      : message = "A file or folder named '$name' already exists.";

  @override
  String toString() => message;
}

class InvalidNameException implements Exception {
  final String message;
  InvalidNameException(this.message);

  @override
  String toString() => message;
}

class FileService {
  static const String windowsDevRoot = r'C:\test_files';

  static bool get isAndroid => Platform.isAndroid;
  static bool get isWindows => Platform.isWindows;

  /// Ensures test directory exists on Windows for dev testing.
  static Future<void> ensureWindowsDevDir() async {
    if (isWindows) {
      try {
        final dir = Directory(windowsDevRoot);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
          final sampleDir = Directory(p.join(windowsDevRoot, 'SampleFolder'));
          await sampleDir.create(recursive: true);
          final sampleFile = File(p.join(windowsDevRoot, 'welcome.txt'));
          await sampleFile.writeAsString('Welcome to File Manager Pro!');
        }
      } catch (_) {}
    }
  }

  /// Checks if required storage permissions are granted.
  static Future<bool> hasStoragePermission() async {
    if (!isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    if (await Permission.storage.isGranted) {
      return true;
    }
    return false;
  }

  /// Requests storage permissions.
  static Future<bool> requestStoragePermission() async {
    if (!isAndroid) return true;

    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;

    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  /// Opens app settings for manually granting permissions.
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Resolves the starting path for a given bubble type.
  static String? getRootPathForBubble(BubbleType bubbleType) {
    if (isWindows) {
      switch (bubbleType) {
        case BubbleType.root:
        case BubbleType.internalStorage:
        case BubbleType.downloads:
          return windowsDevRoot;
        case BubbleType.androidData:
        case BubbleType.androidObb:
          return null; // Requires Shizuku
      }
    }

    switch (bubbleType) {
      case BubbleType.root:
        return '/';
      case BubbleType.internalStorage:
        return '/storage/emulated/0';
      case BubbleType.downloads:
        return '/storage/emulated/0/Download';
      case BubbleType.androidData:
      case BubbleType.androidObb:
        return null; // Requires Shizuku
    }
  }

  /// Checks if bubble requires Shizuku
  static bool requiresShizuku(BubbleType bubbleType) {
    return bubbleType == BubbleType.androidData || bubbleType == BubbleType.androidObb;
  }

  /// Validates a proposed file or folder name.
  /// Returns an error message string if invalid, or null if valid.
  static String? validateFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Name cannot be empty.';
    }

    if (RegExp(r'^\.+$').hasMatch(trimmed)) {
      return 'Name cannot consist only of dots.';
    }

    if (trimmed.contains('/') || trimmed.contains(r'\')) {
      return "Name cannot contain '/' or '\\'.";
    }

    if (RegExp(r'[<>:"|?*]').hasMatch(trimmed)) {
      return 'Name cannot contain invalid characters (< > : " | ? *).';
    }

    return null;
  }

  /// Checks if two paths refer to the same file/directory location.
  static bool isSamePath(String path1, String path2) {
    final norm1 = p.normalize(p.absolute(path1));
    final norm2 = p.normalize(p.absolute(path2));
    if (isWindows) {
      return norm1.toLowerCase() == norm2.toLowerCase();
    }
    return norm1 == norm2;
  }

  /// Checks whether an entity with [name] already exists in [parentDirectory].
  /// On Windows, comparison is case-insensitive.
  /// Optionally ignores [excludePath] (e.g. the entity being renamed).
  static Future<bool> checkNameConflict(
    String parentDirectory,
    String name, {
    String? excludePath,
  }) async {
    final targetFullPath = p.join(parentDirectory, name);

    if (excludePath != null && isSamePath(targetFullPath, excludePath)) {
      return false;
    }

    try {
      final parent = Directory(parentDirectory);
      if (await parent.exists()) {
        final targetLower = name.toLowerCase();
        await for (final entity in parent.list(followLinks: false)) {
          if (excludePath != null && isSamePath(entity.path, excludePath)) {
            continue;
          }
          final entityName = p.basename(entity.path);
          if (isWindows) {
            if (entityName.toLowerCase() == targetLower) {
              return true;
            }
          } else {
            if (entityName == name) {
              return true;
            }
          }
        }
      }

      final targetType = await FileSystemEntity.type(targetFullPath, followLinks: false);
      final exists = targetType != FileSystemEntityType.notFound;
      if (exists) {
        if (excludePath != null && isSamePath(targetFullPath, excludePath)) {
          return false;
        }
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lists files and directories in [dirPath], sorted with folders first and alphabetical by name.
  static Future<List<FileItem>> listDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemException('Directory does not exist', dirPath);
    }

    final List<FileItem> items = [];
    final stream = dir.list(followLinks: false);

    await for (final entity in stream) {
      try {
        final stat = await entity.stat();
        items.add(FileItem.fromFileSystemEntity(entity, stat: stat));
      } catch (_) {
        items.add(FileItem.fromFileSystemEntity(entity));
      }
    }

    // Sort: Folders first, then case-insensitive name
    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  /// Renames a file or folder safely without overwriting existing files/folders.
  static Future<void> renameEntity(String oldPath, String newName) async {
    final currentName = p.basename(oldPath);
    final trimmedName = newName.trim();

    // Renaming to exact same name is a silent no-op
    if (trimmedName == currentName) {
      return;
    }

    // Validate name rules
    final validationError = validateFileName(trimmedName);
    if (validationError != null) {
      throw InvalidNameException(validationError);
    }

    final parent = p.dirname(oldPath);
    final newPath = p.join(parent, trimmedName);

    final isCaseOnly = isWindows &&
        (p.normalize(oldPath).toLowerCase() == p.normalize(newPath).toLowerCase()) &&
        (oldPath != newPath);

    if (!isCaseOnly) {
      final hasConflict = await checkNameConflict(parent, trimmedName, excludePath: oldPath);
      if (hasConflict) {
        throw NameConflictException(trimmedName);
      }
    }

    try {
      final isDir = await FileSystemEntity.isDirectory(oldPath);
      if (isCaseOnly) {
        // Windows requires intermediate temp rename for case-only changes
        final tempName = '${trimmedName}_tmp_${DateTime.now().microsecondsSinceEpoch}';
        final tempPath = p.join(parent, tempName);

        if (isDir) {
          final d = await Directory(oldPath).rename(tempPath);
          await d.rename(newPath);
        } else {
          final f = await File(oldPath).rename(tempPath);
          await f.rename(newPath);
        }
      } else {
        if (isDir) {
          final dir = Directory(oldPath);
          await dir.rename(newPath);
        } else {
          final file = File(oldPath);
          await file.rename(newPath);
        }
      }
      invalidateFolderItemCount(parent);
      invalidateFolderItemCount(oldPath);
      invalidateFolderItemCount(newPath);
    } on FileSystemException {
      rethrow;
    } catch (e) {
      throw FileSystemException('Failed to rename: $e', oldPath);
    }
  }

  /// Deletes a file or directory.
  static Future<void> deleteEntity(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      final dir = Directory(path);
      await dir.delete(recursive: true);
    } else {
      final file = File(path);
      await file.delete();
    }
    invalidateFolderItemCount(p.dirname(path));
    invalidateFolderItemCount(path);
  }

  /// Deletes multiple files/directories.
  static Future<void> deleteMultiple(List<String> paths) async {
    for (final path in paths) {
      await deleteEntity(path);
    }
  }

  /// Returns parent directory path, or null if already at root.
  static String? getParentPath(String currentPath) {
    final parent = p.dirname(currentPath);
    if (parent == currentPath) return null;
    return parent;
  }

  /// Generates a non-conflicting filename in [parentDir] by appending (1), (2), etc.
  static Future<String> generateNonConflictingName(String parentDir, String originalName) async {
    final hasConflict = await checkNameConflict(parentDir, originalName);
    if (!hasConflict) return originalName;

    final dotIndex = originalName.lastIndexOf('.');
    final base = (dotIndex > 0) ? originalName.substring(0, dotIndex) : originalName;
    final ext = (dotIndex > 0) ? originalName.substring(dotIndex) : '';

    int counter = 1;
    while (true) {
      final candidate = '$base ($counter)$ext';
      final exists = await checkNameConflict(parentDir, candidate);
      if (!exists) {
        return candidate;
      }
      counter++;
    }
  }

  /// Checks if [childPath] is the same as or a subfolder of [parentPath].
  static bool isSubfolder(String parentPath, String childPath) {
    final normParent = p.normalize(p.absolute(parentPath));
    final normChild = p.normalize(p.absolute(childPath));
    if (isWindows) {
      final pLow = normParent.toLowerCase();
      final cLow = normChild.toLowerCase();
      return cLow == pLow || cLow.startsWith('$pLow\\') || cLow.startsWith('$pLow/');
    }
    return normChild == normParent || normChild.startsWith('$normParent/');
  }

  /// Creates a new directory in [parentDirectory].
  static Future<void> createFolder(String parentDirectory, String name) async {
    final trimmed = name.trim();
    final valErr = validateFileName(trimmed);
    if (valErr != null) {
      throw InvalidNameException(valErr);
    }

    final hasConflict = await checkNameConflict(parentDirectory, trimmed);
    if (hasConflict) {
      throw NameConflictException(trimmed);
    }

    final targetPath = p.join(parentDirectory, trimmed);
    final dir = Directory(targetPath);
    await dir.create(recursive: false);
    invalidateFolderItemCount(parentDirectory);
  }

  /// Creates a new empty file in [parentDirectory].
  static Future<void> createFile(String parentDirectory, String name) async {
    final trimmed = name.trim();
    final valErr = validateFileName(trimmed);
    if (valErr != null) {
      throw InvalidNameException(valErr);
    }

    final hasConflict = await checkNameConflict(parentDirectory, trimmed);
    if (hasConflict) {
      throw NameConflictException(trimmed);
    }

    final targetPath = p.join(parentDirectory, trimmed);
    final file = File(targetPath);
    await file.create(recursive: false);
    invalidateFolderItemCount(parentDirectory);
  }

  /// Creates a new valid empty ZIP archive in [parentDirectory].
  static Future<String> createEmptyZip(String parentDirectory, String name) async {
    var trimmed = name.trim();
    if (!trimmed.toLowerCase().endsWith('.zip')) {
      trimmed = '$trimmed.zip';
    }

    final valErr = validateFileName(trimmed);
    if (valErr != null) {
      throw InvalidNameException(valErr);
    }

    final hasConflict = await checkNameConflict(parentDirectory, trimmed);
    if (hasConflict) {
      throw NameConflictException(trimmed);
    }

    final targetPath = p.join(parentDirectory, trimmed);
    final tempPath = p.join(parentDirectory, '.${trimmed}_${DateTime.now().microsecondsSinceEpoch}.tmp');
    final tempFile = File(tempPath);
    try {
      final archive = Archive();
      final bytes = ZipEncoder().encode(archive);
      await tempFile.writeAsBytes(bytes);
      await tempFile.rename(targetPath);
      invalidateFolderItemCount(parentDirectory);
      return trimmed;
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Formats byte count to human-readable string (KB, MB, GB).
  static String formatBytes(int bytes) {
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

  /// Formats byte count with commas (e.g. 1,234,567).
  static String formatExactBytes(int bytes) {
    final str = bytes.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join('');
  }

  /// Formats DateTime to full format: yyyy-MM-dd HH:mm:ss.
  static String formatDateTimeFull(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  /// Resolves MIME type for a given path or directory.
  static String getMimeType(String path, {bool isDirectory = false}) {
    if (isDirectory) return 'inode/directory';
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    if (ext.isEmpty) return 'application/octet-stream';
    switch (ext) {
      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'ico':
        return 'image/x-icon';
      case 'heic':
        return 'image/heic';
      case 'tiff':
      case 'tif':
        return 'image/tiff';

      // Audio
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      case 'opus':
        return 'audio/opus';

      // Video
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case '3gp':
        return 'video/3gpp';
      case 'ts':
        return 'video/mp2t';

      // Archives
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case '7z':
        return 'application/x-7z-compressed';
      case 'tar':
        return 'application/x-tar';
      case 'gz':
        return 'application/gzip';
      case 'bz2':
        return 'application/x-bzip2';
      case 'xz':
        return 'application/x-xz';
      case 'apk':
        return 'application/vnd.android.package-archive';

      // Documents / Text
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'log':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'css':
        return 'text/css';
      case 'js':
        return 'text/javascript';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'csv':
        return 'text/csv';
      case 'md':
        return 'text/markdown';
      case 'dart':
        return 'text/x-dart';
      case 'c':
      case 'cpp':
      case 'h':
        return 'text/x-c';
      case 'py':
        return 'text/x-python';
      case 'sh':
        return 'application/x-sh';

      default:
        return 'application/octet-stream';
    }
  }

  /// Retrieves comprehensive metadata for an item at [path].
  static Future<ItemMetadata> getItemMetadata(String path) async {
    try {
      final stat = await FileStat.stat(path);
      final isDir = stat.type == FileSystemEntityType.directory;
      final name = p.basename(path).isEmpty ? path : p.basename(path);
      final parentFolder = p.dirname(path);
      final ext = isDir ? '' : p.extension(path);
      final mime = getMimeType(path, isDirectory: isDir);
      final isHidden = name.startsWith('.');
      final isReadOnly = (stat.mode & 0x92) == 0;
      final perm = stat.modeString();

      return ItemMetadata(
        path: path,
        name: name,
        parentFolder: parentFolder,
        isDirectory: isDir,
        extension: ext,
        mimeType: mime,
        sizeBytes: stat.size,
        sizeFormatted: isDir ? '--' : formatBytes(stat.size),
        exactBytesFormatted: isDir ? '--' : '${formatExactBytes(stat.size)} bytes',
        createdTime: stat.changed,
        modifiedTime: stat.modified,
        accessedTime: stat.accessed,
        isReadOnly: isReadOnly,
        isHidden: isHidden,
        permissions: perm,
        exists: stat.type != FileSystemEntityType.notFound,
      );
    } catch (e) {
      final name = p.basename(path).isEmpty ? path : p.basename(path);
      return ItemMetadata(
        path: path,
        name: name,
        parentFolder: p.dirname(path),
        isDirectory: false,
        extension: p.extension(path),
        mimeType: 'application/octet-stream',
        sizeBytes: 0,
        sizeFormatted: 'Error',
        exactBytesFormatted: '0 bytes',
        isReadOnly: false,
        isHidden: name.startsWith('.'),
        permissions: '---------',
        exists: false,
        error: e.toString(),
      );
    }
  }

  /// Calculates total size, file count, and subfolder count for [folderPath] recursively in an Isolate.
  static Future<FolderStats?> calculateFolderStats(
    String folderPath, {
    CancellationToken? cancellationToken,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<FolderStats?>();
    Isolate? isolate;

    void cleanup() {
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }

    cancellationToken?.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      cleanup();
    });

    receivePort.listen((message) {
      if (message is SendPort) {
        if (cancellationToken?.isCancelled == true) {
          if (!completer.isCompleted) completer.complete(null);
          cleanup();
        } else {
          message.send({'type': 'start', 'path': folderPath});
        }
      } else if (message is Map && message['type'] == 'done') {
        final stats = FolderStats(
          fileCount: message['fileCount'] as int,
          subfolderCount: message['subfolderCount'] as int,
          totalSizeBytes: message['totalSizeBytes'] as int,
          unreadableItems: List<String>.from(message['unreadableItems'] as List),
        );
        if (!completer.isCompleted) {
          completer.complete(stats);
        }
        cleanup();
      }
    });

    try {
      isolate = await Isolate.spawn(_folderStatsWorker, receivePort.sendPort);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }

  static final Map<String, int> _folderItemCountCache = {};

  /// Retrieves the cached direct child item count for [folderPath], or null if not yet cached.
  static int? getCachedFolderItemCount(String folderPath) {
    return _folderItemCountCache[folderPath];
  }

  /// Clears the folder item count cache, or removes a specific entry if [folderPath] is given.
  static void invalidateFolderItemCount([String? folderPath]) {
    if (folderPath != null) {
      _folderItemCountCache.remove(folderPath);
    } else {
      _folderItemCountCache.clear();
    }
  }

  /// Calculates direct child item count (files + subfolders) asynchronously with caching.
  static Future<int?> getFolderItemCount(String folderPath, {bool forceRefresh = false}) async {
    if (!forceRefresh && _folderItemCountCache.containsKey(folderPath)) {
      return _folderItemCountCache[folderPath];
    }

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return null;
      }
      int count = 0;
      await for (final _ in dir.list(followLinks: false)) {
        count++;
      }
      _folderItemCountCache[folderPath] = count;
      return count;
    } catch (_) {
      return null;
    }
  }
}

/// Metadata model for a file or directory.
class ItemMetadata {
  final String path;
  final String name;
  final String parentFolder;
  final bool isDirectory;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final String sizeFormatted;
  final String exactBytesFormatted;
  final DateTime? createdTime;
  final DateTime? modifiedTime;
  final DateTime? accessedTime;
  final bool isReadOnly;
  final bool isHidden;
  final String permissions;
  final bool exists;
  final String? error;

  const ItemMetadata({
    required this.path,
    required this.name,
    required this.parentFolder,
    required this.isDirectory,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.sizeFormatted,
    required this.exactBytesFormatted,
    this.createdTime,
    this.modifiedTime,
    this.accessedTime,
    required this.isReadOnly,
    required this.isHidden,
    required this.permissions,
    this.exists = true,
    this.error,
  });
}

/// Recursive statistics model for a folder.
class FolderStats {
  final int fileCount;
  final int subfolderCount;
  final int totalSizeBytes;
  final List<String> unreadableItems;

  const FolderStats({
    this.fileCount = 0,
    this.subfolderCount = 0,
    this.totalSizeBytes = 0,
    this.unreadableItems = const [],
  });
}

/// Top-level Isolate worker for recursively computing folder statistics.
void _folderStatsWorker(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is Map && message['type'] == 'start') {
      final folderPath = message['path'] as String;
      int fileCount = 0;
      int subfolderCount = 0;
      int totalBytes = 0;
      final unreadable = <String>[];

      void scanDirectory(Directory dir) {
        try {
          final entities = dir.listSync(followLinks: false);
          for (final entity in entities) {
            try {
              if (entity is Directory) {
                subfolderCount++;
                scanDirectory(entity);
              } else if (entity is File) {
                fileCount++;
                try {
                  totalBytes += entity.lengthSync();
                } catch (e) {
                  unreadable.add('${entity.path} (cannot read size: $e)');
                }
              } else if (entity is Link) {
                fileCount++;
              }
            } catch (e) {
              unreadable.add('${entity.path} ($e)');
            }
          }
        } catch (e) {
          unreadable.add('${dir.path} (cannot access folder: $e)');
        }
      }

      scanDirectory(Directory(folderPath));

      mainSendPort.send({
        'type': 'done',
        'fileCount': fileCount,
        'subfolderCount': subfolderCount,
        'totalSizeBytes': totalBytes,
        'unreadableItems': unreadable,
      });
    }
  });
}

