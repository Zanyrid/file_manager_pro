import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_item.dart';
import '../services/file_service.dart';

// Bubble index to BubbleType mapping
final bubbleTypes = [
  BubbleType.root,
  BubbleType.internalStorage,
  BubbleType.androidData,
  BubbleType.androidObb,
  BubbleType.downloads,
];

/// Active bubble index (0: Root, 1: Internal Storage, 2: Android/data, 3: Android/obb, 4: Downloads)
final selectedBubbleIndexProvider = StateProvider<int>((ref) => 1);

/// Permission status provider
final permissionGrantedProvider = StateNotifierProvider<PermissionNotifier, bool?>((ref) {
  return PermissionNotifier();
});

class PermissionNotifier extends StateNotifier<bool?> {
  PermissionNotifier() : super(null) {
    checkPermission();
  }

  Future<void> checkPermission() async {
    final granted = await FileService.hasStoragePermission();
    state = granted;
  }

  Future<bool> requestPermission() async {
    final granted = await FileService.requestStoragePermission();
    state = granted;
    return granted;
  }
}

/// Current directory path provider
final currentPathProvider = StateNotifierProvider<CurrentPathNotifier, String?>((ref) {
  final bubbleIndex = ref.watch(selectedBubbleIndexProvider);
  final bubbleType = bubbleTypes[bubbleIndex];
  final rootPath = FileService.getRootPathForBubble(bubbleType);
  return CurrentPathNotifier(rootPath);
});

class CurrentPathNotifier extends StateNotifier<String?> {
  CurrentPathNotifier(super.initialPath);

  void setPath(String path) {
    state = path;
  }

  bool navigateUp() {
    if (state == null) return false;
    final parent = FileService.getParentPath(state!);
    if (parent != null && parent != state) {
      state = parent;
      return true;
    }
    return false;
  }
}

/// File list state holder
class FileListState {
  final bool isLoading;
  final String? errorMessage;
  final bool requiresShizuku;
  final List<FileItem> files;

  const FileListState({
    this.isLoading = false,
    this.errorMessage,
    this.requiresShizuku = false,
    this.files = const [],
  });

  FileListState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? requiresShizuku,
    List<FileItem>? files,
  }) {
    return FileListState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      requiresShizuku: requiresShizuku ?? this.requiresShizuku,
      files: files ?? this.files,
    );
  }
}

/// Directory file listing notifier
final fileListNotifierProvider =
    StateNotifierProvider<FileListNotifier, FileListState>((ref) {
  final bubbleIndex = ref.watch(selectedBubbleIndexProvider);
  final bubbleType = bubbleTypes[bubbleIndex];
  final currentPath = ref.watch(currentPathProvider);
  final permission = ref.watch(permissionGrantedProvider);

  return FileListNotifier(
    ref: ref,
    bubbleType: bubbleType,
    currentPath: currentPath,
    hasPermission: permission ?? false,
  );
});

class FileListNotifier extends StateNotifier<FileListState> {
  final Ref ref;
  final BubbleType bubbleType;
  final String? currentPath;
  final bool hasPermission;

  FileListNotifier({
    required this.ref,
    required this.bubbleType,
    required this.currentPath,
    required this.hasPermission,
  }) : super(const FileListState(isLoading: true)) {
    loadFiles();
  }

  Future<void> loadFiles() async {
    if (FileService.requiresShizuku(bubbleType)) {
      state = const FileListState(
        isLoading: false,
        requiresShizuku: true,
      );
      return;
    }

    if (currentPath == null) {
      state = const FileListState(
        isLoading: false,
        errorMessage: 'Invalid directory path',
      );
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await FileService.ensureWindowsDevDir();
      final items = await FileService.listDirectory(currentPath!);
      state = FileListState(
        isLoading: false,
        files: items,
      );
    } catch (e) {
      state = FileListState(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('FileSystemException: ', ''),
      );
    }
  }

  Future<String?> renameItem(String oldPath, String newName) async {
    try {
      await FileService.renameEntity(oldPath, newName);
      await loadFiles();
      return null;
    } on NameConflictException catch (e) {
      return e.message;
    } on InvalidNameException catch (e) {
      return e.message;
    } on FileSystemException catch (e) {
      return e.message.isNotEmpty ? e.message : e.toString();
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> deleteItems(List<String> paths) async {
    try {
      await FileService.deleteMultiple(paths);
      // Clear selection after deletion
      ref.read(selectedFilesProvider.notifier).clear();
      await loadFiles();
      return null;
    } on FileSystemException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString().replaceFirst('FileSystemException: ', '');
    }
  }
}

/// Multi-selection state
final selectedFilesProvider =
    StateNotifierProvider<SelectedFilesNotifier, Set<String>>((ref) {
  return SelectedFilesNotifier();
});

class SelectedFilesNotifier extends StateNotifier<Set<String>> {
  SelectedFilesNotifier() : super({});

  void toggle(String path) {
    if (state.contains(path)) {
      state = Set.from(state)..remove(path);
    } else {
      state = Set.from(state)..add(path);
    }
  }

  void selectAll(List<String> allPaths) {
    state = Set.from(allPaths);
  }

  void invertSelection(List<String> allPaths) {
    final inverted = <String>{};
    for (final path in allPaths) {
      if (!state.contains(path)) {
        inverted.add(path);
      }
    }
    state = inverted;
  }

  void clear() {
    state = {};
  }
}
