import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../models/file_item.dart';

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
}
