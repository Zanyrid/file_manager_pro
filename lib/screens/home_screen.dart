import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/operation_models.dart';
import '../services/file_service.dart';
import '../state/app_state.dart';
import '../state/operation_state.dart';
import '../widgets/bubble_menu.dart';
import '../widgets/conflict_dialog.dart';
import '../widgets/extract_destination_dialog.dart';
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
    final messenger = ScaffoldMessenger.of(context);

    if (currentPath == null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot paste: invalid destination directory.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final bubbleIndex = ref.read(selectedBubbleIndexProvider);
    final bubbleType = bubbleTypes[bubbleIndex];
    if (FileService.requiresShizuku(bubbleType)) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot paste: Android/data and obb require Shizuku (Phase 4).'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (clipboard.isCut) {
      final allInSameFolder = clipboard.paths.every(
        (src) => FileService.isSamePath(p.dirname(src), currentPath),
      );
      if (allInSameFolder) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Already in this folder. Nothing to move.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

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

  void _showCompressDialog(BuildContext context, WidgetRef ref, List<String> paths, String currentDir) {
    // Default name: first item's name + ".zip"
    final firstName = p.basenameWithoutExtension(paths.first);
    final defaultName = paths.length == 1 ? '$firstName.zip' : '$firstName.zip';
    final controller = TextEditingController(text: defaultName);
    String? inlineError;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.archive_rounded, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Compress to ZIP',
                      style: TextStyle(color: Color(0xFFEDEDED), fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${paths.length} item(s) selected',
                    style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onChanged: (_) {
                      if (inlineError != null) {
                        setDialogState(() {
                          inlineError = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Output file name',
                      labelStyle: const TextStyle(color: Color(0xFF71717A)),
                      hintText: 'archive.zip',
                      hintStyle: const TextStyle(color: Color(0xFF3F3F46)),
                      errorText: inlineError,
                      errorMaxLines: 2,
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF3F3F46)),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF3B82F6)),
                      ),
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          String outputName = controller.text.trim();
                          if (outputName.isEmpty) {
                            setDialogState(() {
                              inlineError = 'Name cannot be empty.';
                            });
                            return;
                          }

                          // Ensure .zip extension
                          if (!outputName.toLowerCase().endsWith('.zip')) {
                            outputName = '$outputName.zip';
                          }

                          // Validate file name
                          final valErr = FileService.validateFileName(outputName);
                          if (valErr != null) {
                            setDialogState(() {
                              inlineError = valErr;
                            });
                            return;
                          }

                          setDialogState(() {
                            isProcessing = true;
                            inlineError = null;
                          });

                          // Check for name conflict
                          String outputZipPath = p.join(currentDir, outputName);
                          final hasConflict = await FileService.checkNameConflict(currentDir, outputName);

                          if (hasConflict && dialogCtx.mounted) {
                            final res = await ConflictDialog.show(
                              dialogCtx,
                              sourcePath: outputName,
                              targetPath: outputZipPath,
                              isDirectory: false,
                            );

                            if (res == null) {
                              // User cancelled
                              if (dialogCtx.mounted) {
                                setDialogState(() {
                                  isProcessing = false;
                                });
                              }
                              return;
                            }

                            if (res.action == ConflictAction.skip) {
                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop();
                              }
                              return;
                            } else if (res.action == ConflictAction.keepBoth) {
                              outputName = await FileService.generateNonConflictingName(currentDir, outputName);
                              outputZipPath = p.join(currentDir, outputName);
                            } else if (res.action == ConflictAction.replace) {
                              // Delete existing file before creating new one
                              try {
                                final existing = File(outputZipPath);
                                if (existing.existsSync()) {
                                  existing.deleteSync();
                                }
                              } catch (_) {}
                            }
                          }

                          if (dialogCtx.mounted) {
                            Navigator.of(dialogCtx).pop();
                          }

                          // Start compression
                          ref.read(operationNotifierProvider.notifier).startCompressZip(
                            sourcePaths: paths,
                            outputZipPath: outputZipPath,
                          );
                        },
                  child: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Compress'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleBatchExtract(BuildContext context, WidgetRef ref, List<String> zipPaths, String currentDir) {
    if (zipPaths.length == 1) {
      // Single zip: show extract destination dialog
      ExtractDestinationDialog.show(
        context,
        ref,
        zipPath: zipPaths.first,
        currentDirectory: currentDir,
      );
    } else {
      // Multiple zips: extract each to named folder
      showDialog(
        context: context,
        builder: (dialogCtx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.folder_zip_rounded, color: Color(0xFFFFA726), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Extract ZIPs',
                    style: TextStyle(color: Color(0xFFEDEDED), fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Extract ${zipPaths.length} ZIP files, each into its own named folder in the current directory?',
                  style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: zipPaths.map((zp) {
                        final name = p.basename(zp);
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
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA726),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  // Extract the first one; user can queue others after
                  final firstZip = zipPaths.first;
                  final zipBaseName = p.basenameWithoutExtension(firstZip);
                  final destDir = p.join(currentDir, zipBaseName);
                  ref.read(operationNotifierProvider.notifier).startExtractZip(
                    zipPath: firstZip,
                    destinationDir: destDir,
                    conflictMap: const {},
                  );
                },
                child: const Text('Extract All'),
              ),
            ],
          );
        },
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

    // Check if all selected are zips
    final allZips = selectedFiles.isNotEmpty &&
        selectedFiles.every((f) => f.toLowerCase().endsWith('.zip'));

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          // Ctrl+A: Select all
          if (event.logicalKey == LogicalKeyboardKey.keyA &&
              HardwareKeyboard.instance.isControlPressed) {
            final allPaths = fileListState.files.map((f) => f.path).toList();
            ref.read(selectedFilesProvider.notifier).selectAll(allPaths);
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121214),
        appBar: isSelectionMode
            ? AppBar(
                backgroundColor: const Color(0xFF1E1E24),
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: const Color(0xFFEDEDED),
                  tooltip: 'Clear selection',
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
                  // Compress to ZIP
                  IconButton(
                    icon: const Icon(Icons.archive_rounded, size: 20),
                    color: const Color(0xFF38BDF8),
                    tooltip: 'Compress to ZIP',
                    onPressed: () {
                      final currentDir = currentPath ?? '';
                      if (currentDir.isEmpty) return;
                      _showCompressDialog(context, ref, selectedFiles.toList(), currentDir);
                    },
                  ),
                  // Extract ZIP (only if all selected are zips)
                  if (allZips)
                    IconButton(
                      icon: const Icon(Icons.folder_zip_rounded, size: 20),
                      color: const Color(0xFFFFA726),
                      tooltip: 'Extract ZIP${selectedFiles.length > 1 ? 's' : ''}',
                      onPressed: () {
                        final currentDir = currentPath ?? '';
                        if (currentDir.isEmpty) return;
                        _handleBatchExtract(context, ref, selectedFiles.toList(), currentDir);
                      },
                    ),
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
                  // More options menu: Select All, Invert Selection
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFFA1A1AA)),
                    color: const Color(0xFF1E1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onSelected: (action) {
                      final allPaths = fileListState.files.map((f) => f.path).toList();
                      if (action == 'selectAll') {
                        ref.read(selectedFilesProvider.notifier).selectAll(allPaths);
                      } else if (action == 'invertSelection') {
                        ref.read(selectedFilesProvider.notifier).invertSelection(allPaths);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'selectAll',
                        height: 36,
                        child: Row(
                          children: [
                            Icon(Icons.select_all_rounded, size: 16, color: Color(0xFFA1A1AA)),
                            SizedBox(width: 8),
                            Text('Select all', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'invertSelection',
                        height: 36,
                        child: Row(
                          children: [
                            Icon(Icons.flip_rounded, size: 16, color: Color(0xFFA1A1AA)),
                            SizedBox(width: 8),
                            Text('Invert selection', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
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
