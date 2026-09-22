import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_item.dart';
import 'app_state.dart';

enum ViewType {
  detailed,
  compact,
  grid,
}

enum SortField {
  name,
  size,
  date,
  type,
}

enum SortDirection {
  ascending,
  descending,
}

class ViewOptionsState {
  final ViewType viewType;
  final SortField sortField;
  final SortDirection sortDirection;
  final bool showHiddenFiles;

  const ViewOptionsState({
    this.viewType = ViewType.detailed,
    this.sortField = SortField.name,
    this.sortDirection = SortDirection.ascending,
    this.showHiddenFiles = false,
  });

  ViewOptionsState copyWith({
    ViewType? viewType,
    SortField? sortField,
    SortDirection? sortDirection,
    bool? showHiddenFiles,
  }) {
    return ViewOptionsState(
      viewType: viewType ?? this.viewType,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
    );
  }
}

final viewOptionsProvider =
    StateNotifierProvider<ViewOptionsNotifier, ViewOptionsState>((ref) {
  return ViewOptionsNotifier();
});

class ViewOptionsNotifier extends StateNotifier<ViewOptionsState> {
  static const String _keyViewType = 'pref_view_type';
  static const String _keySortField = 'pref_sort_field';
  static const String _keySortDirection = 'pref_sort_direction';
  static const String _keyShowHidden = 'pref_show_hidden_files';

  ViewOptionsNotifier() : super(const ViewOptionsState()) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final viewTypeStr = prefs.getString(_keyViewType);
      final sortFieldStr = prefs.getString(_keySortField);
      final sortDirStr = prefs.getString(_keySortDirection);
      final showHidden = prefs.getBool(_keyShowHidden);

      ViewType viewType = state.viewType;
      if (viewTypeStr != null) {
        viewType = ViewType.values.firstWhere(
          (e) => e.name == viewTypeStr,
          orElse: () => ViewType.detailed,
        );
      }

      SortField sortField = state.sortField;
      if (sortFieldStr != null) {
        sortField = SortField.values.firstWhere(
          (e) => e.name == sortFieldStr,
          orElse: () => SortField.name,
        );
      }

      SortDirection sortDir = state.sortDirection;
      if (sortDirStr != null) {
        sortDir = SortDirection.values.firstWhere(
          (e) => e.name == sortDirStr,
          orElse: () => SortDirection.ascending,
        );
      }

      state = ViewOptionsState(
        viewType: viewType,
        sortField: sortField,
        sortDirection: sortDir,
        showHiddenFiles: showHidden ?? false,
      );
    } catch (_) {}
  }

  Future<void> setViewType(ViewType type) async {
    state = state.copyWith(viewType: type);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyViewType, type.name);
    } catch (_) {}
  }

  Future<void> setSortField(SortField field) async {
    state = state.copyWith(sortField: field);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySortField, field.name);
    } catch (_) {}
  }

  Future<void> toggleSortDirection() async {
    final nextDir = state.sortDirection == SortDirection.ascending
        ? SortDirection.descending
        : SortDirection.ascending;
    state = state.copyWith(sortDirection: nextDir);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySortDirection, nextDir.name);
    } catch (_) {}
  }

  Future<void> toggleHiddenFiles() async {
    final nextVal = !state.showHiddenFiles;
    state = state.copyWith(showHiddenFiles: nextVal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowHidden, nextVal);
    } catch (_) {}
  }
}

/// Provider that returns the sorted and filtered list of files according to current ViewOptions
final sortedFilteredFilesProvider = Provider<List<FileItem>>((ref) {
  final fileListState = ref.watch(fileListNotifierProvider);
  final viewOptions = ref.watch(viewOptionsProvider);

  var items = fileListState.files;
  if (!viewOptions.showHiddenFiles) {
    items = items.where((f) => !f.name.startsWith('.')).toList();
  }

  final isAsc = viewOptions.sortDirection == SortDirection.ascending;

  final sorted = List<FileItem>.from(items);
  sorted.sort((a, b) {
    // Folders always sorted first
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    int cmp = 0;
    switch (viewOptions.sortField) {
      case SortField.name:
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        break;
      case SortField.size:
        cmp = a.sizeBytes.compareTo(b.sizeBytes);
        break;
      case SortField.date:
        cmp = a.modifiedTime.compareTo(b.modifiedTime);
        break;
      case SortField.type:
        if (a.isDirectory && b.isDirectory) {
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        } else {
          final extA = p.extension(a.name).toLowerCase();
          final extB = p.extension(b.name).toLowerCase();
          cmp = extA.compareTo(extB);
          if (cmp == 0) {
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
        }
        break;
    }

    return isAsc ? cmp : -cmp;
  });

  return sorted;
});
