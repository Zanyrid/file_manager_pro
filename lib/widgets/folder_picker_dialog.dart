import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../services/file_service.dart';

class FolderPickerDialog extends StatefulWidget {
  final String initialPath;

  const FolderPickerDialog({
    super.key,
    required this.initialPath,
  });

  static Future<String?> show(BuildContext context, {required String initialPath}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => FolderPickerDialog(initialPath: initialPath),
    );
  }

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  late String _currentPath;
  List<FileItem> _subfolders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await FileService.listDirectory(_currentPath);
      final folders = items.where((item) => item.isDirectory).toList();
      if (mounted) {
        setState(() {
          _subfolders = folders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('FileSystemException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _navigateUp() {
    final parent = FileService.getParentPath(_currentPath);
    if (parent != null && parent != _currentPath) {
      setState(() {
        _currentPath = parent;
      });
      _loadFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoUp = FileService.getParentPath(_currentPath) != null &&
        FileService.getParentPath(_currentPath) != _currentPath;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.folder_open_rounded, color: Color(0xFF3B82F6), size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Select Destination Folder',
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
        width: 440,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Path and navigation bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    color: canGoUp ? const Color(0xFFEDEDED) : const Color(0xFF52525B),
                    tooltip: 'Parent directory',
                    visualDensity: VisualDensity.compact,
                    onPressed: canGoUp ? _navigateUp : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _currentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD4D4D8),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    color: const Color(0xFFA1A1AA),
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    onPressed: _loadFolders,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Folder list area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: _isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                          ),
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size: 32, color: Color(0xFFEF4444)),
                                  const SizedBox(height: 8),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFA1A1AA),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _loadFolders,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _subfolders.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_open_rounded,
                                      size: 36,
                                      color: Color(0xFF3F3F46),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'No subfolders here',
                                      style: TextStyle(
                                        color: Color(0xFF71717A),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _subfolders.length,
                                separatorBuilder: (context, index) => const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Color(0xFF1E1E24),
                                ),
                                itemBuilder: (context, index) {
                                  final folder = _subfolders[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      dense: true,
                                      visualDensity: const VisualDensity(vertical: -2),
                                      leading: const Icon(
                                        Icons.folder_rounded,
                                        color: Color(0xFFFFCA28),
                                        size: 20,
                                      ),
                                      title: Text(
                                        folder.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFEDEDED),
                                          fontSize: 13,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Color(0xFF71717A),
                                        size: 18,
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _currentPath = folder.path;
                                        });
                                        _loadFolders();
                                      },
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: () => Navigator.of(context).pop(_currentPath),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Select this folder'),
        ),
      ],
    );
  }
}
