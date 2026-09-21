import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_item.dart';
import '../services/file_service.dart';
import '../state/app_state.dart';
import '../state/operation_state.dart';
import 'package:path/path.dart' as p;
import 'extract_destination_dialog.dart';

class FileListPanel extends ConsumerWidget {
  const FileListPanel({super.key});

  IconData _getFileIcon(FileItemType type) {
    switch (type) {
      case FileItemType.folder:
        return Icons.folder_rounded;
      case FileItemType.image:
        return Icons.image_rounded;
      case FileItemType.video:
        return Icons.videocam_rounded;
      case FileItemType.audio:
        return Icons.audio_file_rounded;
      case FileItemType.document:
        return Icons.description_rounded;
      case FileItemType.archive:
        return Icons.folder_zip_rounded;
      case FileItemType.apk:
        return Icons.android_rounded;
      case FileItemType.file:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getIconColor(FileItemType type) {
    switch (type) {
      case FileItemType.folder:
        return const Color(0xFFFFCA28);
      case FileItemType.image:
        return const Color(0xFF26C6DA);
      case FileItemType.video:
        return const Color(0xFFFF7043);
      case FileItemType.audio:
        return const Color(0xFFAB47BC);
      case FileItemType.document:
        return const Color(0xFF42A5F5);
      case FileItemType.archive:
        return const Color(0xFFFFA726);
      case FileItemType.apk:
        return const Color(0xFF66BB6A);
      case FileItemType.file:
        return const Color(0xFF9E9E9E);
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, FileItem item) {
    final controller = TextEditingController(text: item.name);
    String? inlineError;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              title: const Text(
                'Rename',
                style: TextStyle(color: Color(0xFFEDEDED), fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      hintText: 'Enter new name',
                      hintStyle: const TextStyle(color: Color(0xFF71717A)),
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
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
                ),
                TextButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          final newName = controller.text.trim();
                          if (newName == item.name) {
                            Navigator.of(dialogCtx).pop();
                            return;
                          }

                          // Validation
                          final valErr = FileService.validateFileName(newName);
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

                          try {
                            final err = await ref
                                .read(fileListNotifierProvider.notifier)
                                .renameItem(item.path, newName);

                            if (err == null) {
                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop();
                              }
                            } else {
                              if (dialogCtx.mounted) {
                                setDialogState(() {
                                  inlineError = err;
                                  isProcessing = false;
                                });
                              }
                              if (context.mounted &&
                                  (err.toLowerCase().contains('denied') ||
                                      err.toLowerCase().contains('in use') ||
                                      err.toLowerCase().contains('permission'))) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(err),
                                    backgroundColor: const Color(0xFFDC2626),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              setDialogState(() {
                                inlineError = e.toString();
                                isProcessing = false;
                              });
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Rename error: $e'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                            }
                          }
                        },
                  child: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                          ),
                        )
                      : const Text('Rename', style: TextStyle(color: Color(0xFF3B82F6))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, List<String> paths) {
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
                'Are you sure you want to delete ${paths.length} item(s)?',
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

  void _showCreateItemDialog(BuildContext context, WidgetRef ref, String createType, String currentDir) {
    final titleText = createType == 'folder'
        ? 'New folder'
        : createType == 'zip'
            ? 'New empty ZIP'
            : 'New file';

    final hintText = createType == 'folder'
        ? 'Enter folder name'
        : createType == 'zip'
            ? 'archive.zip'
            : 'file.txt';

    final labelText = createType == 'folder'
        ? 'Folder name'
        : createType == 'zip'
            ? 'Archive name'
            : 'File name';

    final iconData = createType == 'folder'
        ? Icons.create_new_folder_rounded
        : createType == 'zip'
            ? Icons.folder_zip_rounded
            : Icons.note_add_rounded;

    final iconColor = createType == 'folder'
        ? const Color(0xFFFFCA28)
        : createType == 'zip'
            ? const Color(0xFFFFA726)
            : const Color(0xFF42A5F5);

    final defaultText = createType == 'folder'
        ? 'New Folder'
        : createType == 'zip'
            ? 'archive.zip'
            : 'new_file.txt';

    final controller = TextEditingController(text: defaultText)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: defaultText.contains('.')
            ? defaultText.lastIndexOf('.')
            : defaultText.length,
      );

    String? inlineError;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              final rawName = controller.text.trim();
              if (rawName.isEmpty) {
                setDialogState(() {
                  inlineError = 'Name cannot be empty.';
                });
                return;
              }

              // Pre-validate name rules
              var targetName = rawName;
              if (createType == 'zip' && !targetName.toLowerCase().endsWith('.zip')) {
                targetName = '$targetName.zip';
              }

              final valErr = FileService.validateFileName(targetName);
              if (valErr != null) {
                setDialogState(() {
                  inlineError = valErr;
                });
                return;
              }

              // Check conflict
              final hasConflict = await FileService.checkNameConflict(currentDir, targetName);
              if (hasConflict) {
                setDialogState(() {
                  inlineError = "A file or folder named '$targetName' already exists.";
                });
                return;
              }

              setDialogState(() {
                isProcessing = true;
                inlineError = null;
              });

              try {
                String createdName = targetName;
                if (createType == 'folder') {
                  await FileService.createFolder(currentDir, targetName);
                } else if (createType == 'file') {
                  await FileService.createFile(currentDir, targetName);
                } else if (createType == 'zip') {
                  createdName = await FileService.createEmptyZip(currentDir, targetName);
                }

                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop();
                }

                // Refresh list
                ref.read(fileListNotifierProvider.notifier).loadFiles();

                if (context.mounted) {
                  final label = createType == 'folder'
                      ? 'Folder'
                      : createType == 'zip'
                          ? 'ZIP archive'
                          : 'File';
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('$label "$createdName" created'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              } on NameConflictException catch (e) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    inlineError = e.message;
                    isProcessing = false;
                  });
                }
              } on InvalidNameException catch (e) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    inlineError = e.message;
                    isProcessing = false;
                  });
                }
              } catch (e) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    inlineError = e.toString().replaceFirst('FileSystemException: ', '').replaceFirst('Exception: ', '');
                    isProcessing = false;
                  });
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Icon(iconData, color: iconColor, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titleText,
                      style: const TextStyle(
                        color: Color(0xFFEDEDED),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onSubmitted: isProcessing ? null : (_) => submit(),
                    onChanged: (_) {
                      if (inlineError != null) {
                        setDialogState(() {
                          inlineError = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: labelText,
                      labelStyle: const TextStyle(color: Color(0xFF71717A)),
                      hintText: hintText,
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: isProcessing ? null : submit,
                  child: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingActionButton(BuildContext context, WidgetRef ref, String currentDir) {
    return PopupMenuButton<String>(
      tooltip: 'Create new',
      offset: const Offset(0, -155),
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF27272A), width: 1),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'folder',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.create_new_folder_rounded, color: Color(0xFFFFCA28), size: 18),
              SizedBox(width: 10),
              Text('New folder', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'file',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.note_add_rounded, color: Color(0xFF42A5F5), size: 18),
              SizedBox(width: 10),
              Text('New file', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'zip',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.folder_zip_rounded, color: Color(0xFFFFA726), size: 18),
              SizedBox(width: 10),
              Text('New empty ZIP', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
            ],
          ),
        ),
      ],
      onSelected: (action) {
        _showCreateItemDialog(context, ref, action, currentDir);
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
    );
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileListNotifierProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);
    final isSelectionMode = selectedFiles.isNotEmpty;
    final currentPath = ref.watch(currentPathProvider);
    final showFab = !isSelectionMode && !state.requiresShizuku && currentPath != null;

    Widget mainContent;

    if (state.requiresShizuku) {
      mainContent = Material(
        color: const Color(0xFF18181B),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
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
                    Icons.shield_outlined,
                    size: 40,
                    color: Color(0xFFFFB300),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Requires Shizuku (Phase 4)',
                  style: TextStyle(
                    color: Color(0xFFEDEDED),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Accessing Android/data and Android/obb requires elevated Shizuku or SAF bindings in Phase 4.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (state.isLoading) {
      mainContent = const Material(
        color: Color(0xFF18181B),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
          ),
        ),
      );
    } else if (state.errorMessage != null) {
      mainContent = Material(
        color: const Color(0xFF18181B),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: Color(0xFFEF4444),
                ),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(fileListNotifierProvider.notifier).loadFiles();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEDEDED),
                    side: const BorderSide(color: Color(0xFF3F3F46)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (state.files.isEmpty) {
      mainContent = Material(
        color: const Color(0xFF18181B),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 40,
                color: Color(0xFF3F3F46),
              ),
              const SizedBox(height: 12),
              const Text(
                'Folder is empty',
                style: TextStyle(
                  color: Color(0xFF71717A),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              IconButton(
                onPressed: () {
                  ref.read(fileListNotifierProvider.notifier).loadFiles();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: const Color(0xFFA1A1AA),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
      );
    } else {
      mainContent = Material(
        color: const Color(0xFF18181B),
        child: RefreshIndicator(
          backgroundColor: const Color(0xFF222226),
          color: const Color(0xFF3B82F6),
          onRefresh: () async {
            await ref.read(fileListNotifierProvider.notifier).loadFiles();
          },
          child: ListView.separated(
            itemCount: state.files.length,
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFF232328),
            ),
            itemBuilder: (context, index) {
              final file = state.files[index];
              final isSelected = selectedFiles.contains(file.path);

              return Material(
                color: isSelected ? const Color(0xFF2A2D3D) : Colors.transparent,
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -1),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF71717A),
                          ),
                        ),
                      Icon(
                        _getFileIcon(file.type),
                        color: _getIconColor(file.type),
                        size: 24,
                      ),
                    ],
                  ),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEDEDED),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    file.dateModified,
                    style: const TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.size,
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 11,
                        ),
                      ),
                      if (!isSelectionMode)
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: Color(0xFF71717A),
                          ),
                          color: const Color(0xFF1E1E24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onSelected: (action) {
                            if (action == 'copy') {
                              ref.read(clipboardProvider.notifier).copy([file.path]);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied "${file.name}" to clipboard'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } else if (action == 'cut') {
                              ref.read(clipboardProvider.notifier).cut([file.path]);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Cut "${file.name}" to clipboard'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } else if (action == 'rename') {
                              _showRenameDialog(context, ref, file);
                            } else if (action == 'delete') {
                              _showDeleteDialog(context, ref, [file.path]);
                            } else if (action == 'select') {
                              ref.read(selectedFilesProvider.notifier).toggle(file.path);
                            } else if (action == 'extract') {
                              final currentDir = ref.read(currentPathProvider) ?? p.dirname(file.path);
                              ExtractDestinationDialog.show(
                                context,
                                ref,
                                zipPath: file.path,
                                currentDirectory: currentDir,
                              );
                            }
                          },
                          itemBuilder: (context) {
                            final isZip = file.name.toLowerCase().endsWith('.zip');
                            return [
                              if (isZip)
                                const PopupMenuItem(
                                  value: 'extract',
                                  height: 36,
                                  child: Row(
                                    children: [
                                      Icon(Icons.folder_zip_outlined, size: 16, color: Color(0xFFFFA726)),
                                      SizedBox(width: 8),
                                      Text('Extract ZIP', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'select',
                                height: 36,
                                child: Row(
                                  children: [
                                    Icon(Icons.check_box_outlined, size: 16, color: Color(0xFFA1A1AA)),
                                    SizedBox(width: 8),
                                    Text('Select', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'copy',
                                height: 36,
                                child: Row(
                                  children: [
                                    Icon(Icons.copy_rounded, size: 16, color: Color(0xFFA1A1AA)),
                                    SizedBox(width: 8),
                                    Text('Copy', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'cut',
                                height: 36,
                                child: Row(
                                  children: [
                                    Icon(Icons.content_cut_rounded, size: 16, color: Color(0xFFA1A1AA)),
                                    SizedBox(width: 8),
                                    Text('Cut', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                height: 36,
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 16, color: Color(0xFFA1A1AA)),
                                    SizedBox(width: 8),
                                    Text('Rename', style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                height: 36,
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                                    SizedBox(width: 8),
                                    Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                                  ],
                                ),
                              ),
                            ];
                          },
                        ),
                    ],
                  ),
                  onTap: () {
                    if (isSelectionMode) {
                      ref.read(selectedFilesProvider.notifier).toggle(file.path);
                    } else {
                      if (file.isDirectory) {
                        ref.read(currentPathProvider.notifier).setPath(file.path);
                      } else if (file.name.toLowerCase().endsWith('.zip')) {
                        final currentDir = ref.read(currentPathProvider) ?? p.dirname(file.path);
                        ExtractDestinationDialog.show(
                          context,
                          ref,
                          zipPath: file.path,
                          currentDirectory: currentDir,
                        );
                      }
                    }
                  },
                  onLongPress: () {
                    ref.read(selectedFilesProvider.notifier).toggle(file.path);
                  },
                ),
              );
            },
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: mainContent),
        if (showFab)
          Positioned(
            right: 16,
            bottom: 16,
            child: _buildFloatingActionButton(context, ref, currentPath),
          ),
      ],
    );
  }
}
