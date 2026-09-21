import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/operation_models.dart';

class ConflictDialog extends StatefulWidget {
  final String sourcePath;
  final String targetPath;
  final bool isDirectory;
  final bool hideReplace;

  const ConflictDialog({
    super.key,
    required this.sourcePath,
    required this.targetPath,
    required this.isDirectory,
    this.hideReplace = false,
  });

  static Future<ConflictResolutionResult?> show(
    BuildContext context, {
    required String sourcePath,
    required String targetPath,
    required bool isDirectory,
    bool hideReplace = false,
  }) {
    return showDialog<ConflictResolutionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConflictDialog(
        sourcePath: sourcePath,
        targetPath: targetPath,
        isDirectory: isDirectory,
        hideReplace: hideReplace,
      ),
    );
  }

  @override
  State<ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<ConflictDialog> {
  bool _applyToAll = false;

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.sourcePath);
    final entityType = widget.isDirectory ? 'folder' : 'file';

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
          const SizedBox(width: 8),
          const Text(
            'Name Conflict',
            style: TextStyle(color: Color(0xFFEDEDED), fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hideReplace
                ? 'A $entityType named "$fileName" already exists here. Create a copy?'
                : 'A $entityType named "$fileName" already exists in the destination.',
            style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _applyToAll,
                activeColor: const Color(0xFF3B82F6),
                checkColor: Colors.white,
                side: const BorderSide(color: Color(0xFF52525B)),
                onChanged: (val) {
                  setState(() {
                    _applyToAll = val ?? false;
                  });
                },
              ),
              const SizedBox(width: 4),
              const Text(
                'Apply to all conflicts',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              ConflictResolutionResult(
                action: ConflictAction.skip,
                applyToAll: _applyToAll,
              ),
            );
          },
          child: const Text('Skip', style: TextStyle(color: Color(0xFFA1A1AA))),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              ConflictResolutionResult(
                action: ConflictAction.keepBoth,
                applyToAll: _applyToAll,
              ),
            );
          },
          child: const Text('Keep Both', style: TextStyle(color: Color(0xFF3B82F6))),
        ),
        if (!widget.hideReplace)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () {
              Navigator.of(context).pop(
                ConflictResolutionResult(
                  action: ConflictAction.replace,
                  applyToAll: _applyToAll,
                ),
              );
            },
            child: const Text('Replace'),
          ),
      ],
    );
  }
}
