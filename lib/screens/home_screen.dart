import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/operation_models.dart';
import '../services/file_service.dart';
import '../state/app_state.dart';
import '../state/operation_state.dart';
import '../widgets/bubble_menu.dart';
import '../widgets/file_list_panel.dart';
import '../widgets/terminal_panel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _showMultiDeleteDialog(BuildContext context, WidgetRef ref, List<String> paths) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          title: const Text(
            'Confirm Delete',
            style: TextStyle(color: Color(0xFFEDEDED), fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete ${paths.length} selected item(s)?',
                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: paths.map((p) {
                      final name = p.split(RegExp(r'[/\\]')).last;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFE4E4E7), fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                ref.read(operationNotifierProvider.notifier).startDelete(paths: paths);
              },
              child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
            ),
          ],
        );
      },
    );
  }

  void _handlePaste(BuildContext context, WidgetRef ref, ClipboardState clipboard, String? currentPath) {
    if (currentPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot paste: invalid destination directory.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final bubbleIndex = ref.read(selectedBubbleIndexProvider);
    final bubbleType = bubbleTypes[bubbleIndex];
    if (FileService.requiresShizuku(bubbleType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot paste: Android/data and obb require Shizuku (Phase 4).'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (clipboard.isCut) {
      ref.read(operationNotifierProvider.notifier).startMove(
            sourcePaths: clipboard.paths,
            destinationDir: currentPath,
            context: context,
          );
    } else {
      ref.read(operationNotifierProvider.notifier).startCopy(
            sourcePaths: clipboard.paths,
            destinationDir: currentPath,
            context: context,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFiles = ref.watch(selectedFilesProvider);
    final isSelectionMode = selectedFiles.isNotEmpty;
    final currentPath = ref.watch(currentPathProvider);
    final fileListState = ref.watch(fileListNotifierProvider);
    final permissionGranted = ref.watch(permissionGrantedProvider);
    final clipboard = ref.watch(clipboardProvider);
    final operationState = ref.watch(operationNotifierProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: isSelectionMode
          ? AppBar(
              backgroundColor: const Color(0xFF1E1E24),
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: const Color(0xFFEDEDED),
                tooltip: 'Cancel selection',
                onPressed: () {
                  ref.read(selectedFilesProvider.notifier).clear();
                },
              ),
              titleSpacing: 0,
              title: Text(
                '${selectedFiles.length} selected',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEDEDED),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  color: const Color(0xFFA1A1AA),
                  tooltip: 'Copy',
                  onPressed: () {
                    final paths = selectedFiles.toList();
                    ref.read(clipboardProvider.notifier).copy(paths);
                    ref.read(selectedFilesProvider.notifier).clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${paths.length} item(s) copied to clipboard'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.content_cut_rounded, size: 20),
                  color: const Color(0xFFA1A1AA),
                  tooltip: 'Cut',
                  onPressed: () {
                    final paths = selectedFiles.toList();
                    ref.read(clipboardProvider.notifier).cut(paths);
                    ref.read(selectedFilesProvider.notifier).clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${paths.length} item(s) cut to clipboard'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.select_all_rounded, size: 20),
                  color: const Color(0xFFA1A1AA),
                  tooltip: 'Select all',
                  onPressed: () {
                    final allPaths = fileListState.files.map((f) => f.path).toList();
                    ref.read(selectedFilesProvider.notifier).selectAll(allPaths);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: const Color(0xFFEF4444),
                  tooltip: 'Delete selected',
                  onPressed: () {
                    _showMultiDeleteDialog(context, ref, selectedFiles.toList());
                  },
                ),
                const SizedBox(width: 4),
              ],
            )
          : AppBar(
              backgroundColor: const Color(0xFF18181B),
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 16,
              title: const Text(
                'File Manager Pro',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEDEDED),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded, size: 20),
                  color: const Color(0xFFA1A1AA),
                  tooltip: 'Search',
                  onPressed: () {},
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: 'Shizuku: Disconnected',
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF222226),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.terminal_rounded,
                    size: 20,
                    color: operationState.isTerminalOpen
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFFA1A1AA),
                  ),
                  tooltip: 'Terminal Logs',
                  onPressed: () {
                    if (operationState.isTerminalOpen) {
                      ref.read(operationNotifierProvider.notifier).closeTerminal();
                    } else {
                      ref.read(operationNotifierProvider.notifier).openTerminal();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  color: const Color(0xFFA1A1AA),
                  tooltip: 'Settings',
                  onPressed: () {
                    FileService.openSettings();
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: permissionGranted == false
          ? _PermissionExplanationView(
              onRequestPermission: () async {
                final granted = await ref
                    .read(permissionGrantedProvider.notifier)
                    .requestPermission();
                if (granted) {
                  ref.read(fileListNotifierProvider.notifier).loadFiles();
                }
              },
            )
          : Column(
              children: [
                // Navigation / Path Bar
                Material(
                  color: const Color(0xFF141416),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF27272A), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                          color: const Color(0xFFA1A1AA),
                          tooltip: 'Navigate up',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(selectedFilesProvider.notifier).clear();
                            ref.read(currentPathProvider.notifier).navigateUp();
                          },
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E24),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              currentPath ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD4D4D8),
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          color: const Color(0xFFA1A1AA),
                          tooltip: 'Refresh',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(fileListNotifierProvider.notifier).loadFiles();
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Clipboard / Paste Bar (When clipboard is not empty)
                if (clipboard.isNotEmpty)
                  Material(
                    color: const Color(0xFF1E1E28),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF3B82F6), width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            clipboard.isCut ? Icons.content_cut_rounded : Icons.copy_rounded,
                            size: 16,
                            color: const Color(0xFF3B82F6),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${clipboard.paths.length} item(s) in clipboard (${clipboard.isCut ? "Cut" : "Copy"})',
                              style: const TextStyle(
                                color: Color(0xFFEDEDED),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              _handlePaste(context, ref, clipboard, currentPath);
                            },
                            icon: const Icon(Icons.paste_rounded, size: 14),
                            label: const Text('Paste here', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            color: const Color(0xFFA1A1AA),
                            tooltip: 'Clear clipboard',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              ref.read(clipboardProvider.notifier).clear();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // Main Split View (Left: Bubbles, Right: FileList or Terminal)
                Expanded(
                  child: Row(
                    children: [
                      const BubbleMenu(),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Color(0xFF27272A),
                      ),
                      Expanded(
                        child: operationState.isTerminalOpen
                            ? const TerminalPanel()
                            : const FileListPanel(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionExplanationView extends StatelessWidget {
  final VoidCallback onRequestPermission;

  const _PermissionExplanationView({required this.onRequestPermission});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF222226),
              ),
              child: const Icon(
                Icons.folder_shared_rounded,
                size: 48,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Storage Access Required',
              style: TextStyle(
                color: Color(0xFFEDEDED),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'File Manager Pro requires permission to access storage in order to browse, rename, and manage your files.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    FileService.openSettings();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEDEDED),
                    side: const BorderSide(color: Color(0xFF3F3F46)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Open Settings'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: onRequestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Grant Access'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
