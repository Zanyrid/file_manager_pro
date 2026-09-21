import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/operation_models.dart';
import '../services/zip_service.dart';
import '../state/operation_state.dart';
import 'conflict_dialog.dart';
import 'folder_picker_dialog.dart';

class ExtractDestinationDialog extends StatelessWidget {
  final String zipPath;
  final String currentDirectory;

  const ExtractDestinationDialog({
    super.key,
    required this.zipPath,
    required this.currentDirectory,
  });

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String zipPath,
    required String currentDirectory,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => ExtractDestinationDialog(
        zipPath: zipPath,
        currentDirectory: currentDirectory,
      ),
    );
  }

  Future<void> _onDestinationSelected(
    BuildContext context,
    WidgetRef ref,
    String destinationDir,
  ) async {
    // 1. Inspect archive before extracting
    final inspection = await ZipService.inspectArchive(zipPath, destinationDir);

    if (!inspection.isValid) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      ref.read(operationNotifierProvider.notifier).startExtractZip(
        zipPath: zipPath,
        destinationDir: destinationDir,
        conflictMap: const {},
      );
      return;
    }

    // 2. Resolve conflicts before extraction
    final conflictMap = <String, ConflictAction>{};
    ConflictResolutionResult? globalResult;

    if (inspection.conflictingFileEntries.isNotEmpty) {
      for (final entryName in inspection.conflictingFileEntries) {
        if (globalResult != null && globalResult.applyToAll) {
          conflictMap[entryName] = globalResult.action;
          continue;
        }

        if (!context.mounted) return;

        final targetPath = p.join(destinationDir, p.normalize(entryName));
        final res = await ConflictDialog.show(
          context,
          sourcePath: entryName,
          targetPath: targetPath,
          isDirectory: false,
        );

        if (res == null) {
          // User cancelled / dismissed dialog -> abort extraction
          return;
        }

        if (res.applyToAll) {
          globalResult = res;
        }
        conflictMap[entryName] = res.action;
      }
    }

    // 3. Close destination choice dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // 4. Start extraction with pre-resolved conflict decisions
    ref.read(operationNotifierProvider.notifier).startExtractZip(
      zipPath: zipPath,
      destinationDir: destinationDir,
      conflictMap: conflictMap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final zipFileName = p.basename(zipPath);
    final dotIndex = zipFileName.lastIndexOf('.');
    final zipBaseName = dotIndex > 0 ? zipFileName.substring(0, dotIndex) : zipFileName;
    final subfolderDestination = p.join(currentDirectory, zipBaseName);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          const Icon(Icons.folder_zip_rounded, color: Color(0xFFFFA726), size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Extract ZIP',
              style: TextStyle(
                color: Color(0xFFEDEDED),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Archive: $zipFileName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF27272A)),
            const SizedBox(height: 8),

            // Option 1: Extract here
            Consumer(
              builder: (context, ref, _) => ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: const Icon(Icons.folder_open_rounded, color: Color(0xFF38BDF8), size: 22),
                title: const Text(
                  'Extract here',
                  style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  currentDirectory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF71717A), fontSize: 11, fontFamily: 'monospace'),
                ),
                onTap: () {
                  _onDestinationSelected(context, ref, currentDirectory);
                },
              ),
            ),

            // Option 2: Extract to folder named <zipname>
            Consumer(
              builder: (context, ref, _) => ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: const Icon(Icons.create_new_folder_outlined, color: Color(0xFF4ADE80), size: 22),
                title: Text(
                  'Extract to folder named "$zipBaseName"',
                  style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  subfolderDestination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF71717A), fontSize: 11, fontFamily: 'monospace'),
                ),
                onTap: () {
                  _onDestinationSelected(context, ref, subfolderDestination);
                },
              ),
            ),

            // Option 3: Choose folder
            Consumer(
              builder: (context, ref, _) => ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: const Icon(Icons.drive_file_move_outlined, color: Color(0xFFA78BFA), size: 22),
                title: const Text(
                  'Choose folder',
                  style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  'Select a destination folder in file picker',
                  style: TextStyle(color: Color(0xFF71717A), fontSize: 11),
                ),
                onTap: () async {
                  final chosenFolder = await FolderPickerDialog.show(
                    context,
                    initialPath: currentDirectory,
                  );

                  if (chosenFolder != null && context.mounted) {
                    await _onDestinationSelected(context, ref, chosenFolder);
                  }
                },
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
        ),
      ],
    );
  }
}
