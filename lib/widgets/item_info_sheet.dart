import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/file_service.dart';
import '../services/operation_service.dart' show CancellationToken;

class ItemInfoSheet extends StatefulWidget {
  final List<String> paths;

  const ItemInfoSheet({super.key, required this.paths});

  static Future<void> show(BuildContext context, List<String> paths) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E24),
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ItemInfoSheet(paths: paths),
    );
  }

  @override
  State<ItemInfoSheet> createState() => _ItemInfoSheetState();
}

class _ItemInfoSheetState extends State<ItemInfoSheet> {
  @override
  Widget build(BuildContext context) {
    final count = widget.paths.length;
    final title = count == 1 ? 'Item Information' : 'Information ($count items)';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E24),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF52525B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF8BC34A), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFEDEDED),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFFA1A1AA)),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2E2E36), height: 1),
              // Content list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: widget.paths.length,
                  itemBuilder: (context, index) {
                    final path = widget.paths[index];
                    return _ItemInfoCard(path: path);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ItemInfoCard extends StatefulWidget {
  final String path;

  const _ItemInfoCard({required this.path});

  @override
  State<_ItemInfoCard> createState() => _ItemInfoCardState();
}

class _ItemInfoCardState extends State<_ItemInfoCard> {
  late Future<ItemMetadata> _metaFuture;
  CancellationToken? _folderCancellationToken;
  FolderStats? _folderStats;
  bool _isLoadingFolderStats = false;
  bool _isCancelledFolderStats = false;
  bool _folderStatsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  void _loadMetadata() {
    _metaFuture = FileService.getItemMetadata(widget.path).then((meta) {
      if (meta.isDirectory && mounted) {
        _startFolderStats();
      }
      return meta;
    });
  }

  void _startFolderStats() {
    _folderCancellationToken?.cancel();
    final token = CancellationToken();
    _folderCancellationToken = token;

    setState(() {
      _isLoadingFolderStats = true;
      _isCancelledFolderStats = false;
      _folderStatsFailed = false;
      _folderStats = null;
    });

    FileService.calculateFolderStats(widget.path, cancellationToken: token).then((stats) {
      if (!mounted) return;
      if (token.isCancelled) {
        setState(() {
          _isLoadingFolderStats = false;
          _isCancelledFolderStats = true;
        });
      } else if (stats != null) {
        setState(() {
          _isLoadingFolderStats = false;
          _folderStats = stats;
        });
      } else {
        setState(() {
          _isLoadingFolderStats = false;
          _folderStatsFailed = true;
        });
      }
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _isLoadingFolderStats = false;
        _folderStatsFailed = true;
      });
    });
  }

  void _cancelFolderStats() {
    _folderCancellationToken?.cancel();
    setState(() {
      _isLoadingFolderStats = false;
      _isCancelledFolderStats = true;
    });
  }

  @override
  void dispose() {
    _folderCancellationToken?.cancel();
    super.dispose();
  }

  void _copyPath(BuildContext context, String path) {
    Clipboard.setData(ClipboardData(text: path));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Path copied: $path'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  IconData _getIconForMetadata(ItemMetadata meta) {
    if (meta.isDirectory) return Icons.folder_rounded;
    final ext = meta.extension.toLowerCase();
    switch (ext) {
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return Icons.folder_zip_rounded;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
      case '.svg':
        return Icons.image_rounded;
      case '.mp4':
      case '.mkv':
      case '.avi':
      case '.mov':
        return Icons.movie_rounded;
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        return Icons.audiotrack_rounded;
      case '.pdf':
      case '.doc':
      case '.docx':
      case '.txt':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getIconColorForMetadata(ItemMetadata meta) {
    if (meta.isDirectory) return const Color(0xFFFFA726);
    final ext = meta.extension.toLowerCase();
    switch (ext) {
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return const Color(0xFFFFA726);
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
      case '.svg':
        return const Color(0xFF8BC34A);
      case '.mp4':
      case '.mkv':
      case '.avi':
      case '.mov':
        return const Color(0xFFEC4899);
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        return const Color(0xFFA855F7);
      default:
        return const Color(0xFF38BDF8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ItemMetadata>(
      future: _metaFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF26262D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8BC34A)),
                ),
              ),
            ),
          );
        }

        final meta = snapshot.data!;
        final icon = _getIconForMetadata(meta);
        final iconColor = _getIconColorForMetadata(meta);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF26262D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF32323A)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header: Icon, Name, Copy Path Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            meta.name,
                            style: const TextStyle(
                              color: Color(0xFFEDEDED),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            meta.isDirectory ? 'Folder' : meta.mimeType,
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF8BC34A),
                        side: const BorderSide(color: Color(0xFF3F3F46)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy path', style: TextStyle(fontSize: 12)),
                      onPressed: () => _copyPath(context, meta.path),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF32323A), height: 1),
                const SizedBox(height: 10),

                // Properties
                _buildInfoRow('Full path', meta.path, isSelectable: true),
                _buildInfoRow('Parent folder', meta.parentFolder, isSelectable: true),
                _buildInfoRow(
                  'Type',
                  meta.isDirectory
                      ? 'Folder'
                      : (meta.extension.isNotEmpty
                          ? '${meta.extension.toUpperCase().replaceAll('.', '')} File (${meta.extension})'
                          : 'File'),
                ),
                _buildInfoRow('MIME type', meta.mimeType),

                // Size details
                if (!meta.isDirectory) ...[
                  _buildInfoRow('Size', '${meta.sizeFormatted} (${meta.exactBytesFormatted})'),
                ] else ...[
                  _buildFolderStatsSection(),
                ],

                // Dates
                _buildInfoRow(
                  'Modified',
                  meta.modifiedTime != null
                      ? FileService.formatDateTimeFull(meta.modifiedTime!)
                      : '--',
                ),
                _buildInfoRow(
                  'Accessed',
                  meta.accessedTime != null
                      ? FileService.formatDateTimeFull(meta.accessedTime!)
                      : '--',
                ),
                _buildInfoRow(
                  'Created / Changed',
                  meta.createdTime != null
                      ? FileService.formatDateTimeFull(meta.createdTime!)
                      : '--',
                ),

                // Flags & Permissions
                _buildInfoRow(
                  'Attributes',
                  'Read-only: ${meta.isReadOnly ? "Yes" : "No"}   |   Hidden: ${meta.isHidden ? "Yes" : "No"}',
                ),
                _buildInfoRow('Permissions', meta.permissions),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderStatsSection() {
    if (_isLoadingFolderStats) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8BC34A)),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Computing folder size & contents...',
              style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _cancelFolderStats,
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (_isCancelledFolderStats) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 15),
            const SizedBox(width: 6),
            const Text(
              'Folder size calculation cancelled',
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _startFolderStats,
              child: const Text('Recalculate', style: TextStyle(color: Color(0xFF8BC34A), fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (_folderStatsFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 15),
            const SizedBox(width: 6),
            const Text(
              'Failed to read folder contents',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _startFolderStats,
              child: const Text('Retry', style: TextStyle(color: Color(0xFF8BC34A), fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (_folderStats != null) {
      final stats = _folderStats!;
      final sizeFormatted = FileService.formatBytes(stats.totalSizeBytes);
      final exactBytesFormatted = FileService.formatExactBytes(stats.totalSizeBytes);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Total size', '$sizeFormatted ($exactBytesFormatted bytes)'),
          _buildInfoRow('Contents', '${stats.fileCount} file(s), ${stats.subfolderCount} subfolder(s)'),
          if (stats.unreadableItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${stats.unreadableItems.length} unreadable item(s)',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...stats.unreadableItems.take(5).map(
                        (err) => Padding(
                          padding: const EdgeInsets.only(left: 4, top: 2),
                          child: Text(
                            '• $err',
                            style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 11),
                          ),
                        ),
                      ),
                  if (stats.unreadableItems.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      child: Text(
                        '...and ${stats.unreadableItems.length - 5} more',
                        style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInfoRow(String label, String value, {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: isSelectable
                ? SelectableText(
                    value,
                    style: const TextStyle(
                      color: Color(0xFFEDEDED),
                      fontSize: 12,
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFFEDEDED),
                      fontSize: 12,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
