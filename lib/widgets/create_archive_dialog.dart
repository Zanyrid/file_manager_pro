import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/operation_models.dart';
import '../services/file_service.dart';
import '../state/operation_state.dart';
import 'conflict_dialog.dart';
import 'folder_picker_dialog.dart';

class CreateArchiveDialog extends StatefulWidget {
  final List<String> paths;
  final String currentDirectory;

  const CreateArchiveDialog({
    super.key,
    required this.paths,
    required this.currentDirectory,
  });

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required List<String> paths,
    required String currentDirectory,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => CreateArchiveDialog(
        paths: paths,
        currentDirectory: currentDirectory,
      ),
    );
  }

  @override
  State<CreateArchiveDialog> createState() => _CreateArchiveDialogState();
}

class _CreateArchiveDialogState extends State<CreateArchiveDialog> {
  late TextEditingController _nameController;
  late String _destinationDir;
  String _selectedFormat = 'zip';
  int _compressionLevel = 6; // Normal
  final String _selectedEncryption = 'none';
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _deleteSourceFiles = false;
  bool _createSeparateArchives = false;
  String? _inlineError;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _destinationDir = widget.currentDirectory;

    final defaultBaseName = widget.paths.length == 1
        ? p.basenameWithoutExtension(widget.paths.first)
        : p.basenameWithoutExtension(widget.paths.first);
    final defaultName = '$defaultBaseName.zip';

    _nameController = TextEditingController(text: defaultName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: defaultBaseName.length,
      );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickDestinationFolder() async {
    final picked = await FolderPickerDialog.show(
      context,
      initialPath: _destinationDir,
    );
    if (picked != null && mounted) {
      setState(() {
        _destinationDir = picked;
      });
    }
  }

  Future<void> _submit(WidgetRef ref) async {
    setState(() {
      _isProcessing = true;
      _inlineError = null;
    });

    try {
      if (!_createSeparateArchives) {
        // Single archive flow
        var outputName = _nameController.text.trim();
        if (outputName.isEmpty) {
          setState(() {
            _inlineError = 'Archive name cannot be empty.';
            _isProcessing = false;
          });
          return;
        }

        if (!outputName.toLowerCase().endsWith('.zip')) {
          outputName = '$outputName.zip';
        }

        final valErr = FileService.validateFileName(outputName);
        if (valErr != null) {
          setState(() {
            _inlineError = valErr;
            _isProcessing = false;
          });
          return;
        }

        String outputZipPath = p.join(_destinationDir, outputName);
        final hasConflict = await FileService.checkNameConflict(_destinationDir, outputName);

        if (hasConflict && mounted) {
          final res = await ConflictDialog.show(
            context,
            sourcePath: outputName,
            targetPath: outputZipPath,
            isDirectory: false,
            hideReplace: true,
          );

          if (res == null || !mounted) {
            setState(() {
              _isProcessing = false;
            });
            return;
          }

          if (res.action == ConflictAction.skip) {
            if (mounted) Navigator.of(context).pop();
            return;
          } else if (res.action == ConflictAction.keepBoth) {
            outputName = await FileService.generateNonConflictingName(_destinationDir, outputName);
            outputZipPath = p.join(_destinationDir, outputName);
          }
        }

        if (mounted) {
          Navigator.of(context).pop();
        }

        ref.read(operationNotifierProvider.notifier).startCompressZip(
          sourcePaths: widget.paths,
          outputZipPath: outputZipPath,
          compressionLevel: _compressionLevel,
          deleteSourceFiles: _deleteSourceFiles,
        );
      } else {
        // Separate archives flow: one zip per selected item
        final tasks = <({List<String> sourcePaths, String outputZipPath})>[];
        ConflictResolutionResult? globalConflictResult;

        for (final itemPath in widget.paths) {
          final baseName = p.basenameWithoutExtension(itemPath);
          var zipName = '$baseName.zip';
          final valErr = FileService.validateFileName(zipName);
          if (valErr != null) {
            continue;
          }

          var targetPath = p.join(_destinationDir, zipName);
          final hasConflict = await FileService.checkNameConflict(_destinationDir, zipName);

          if (hasConflict) {
            if (globalConflictResult != null && globalConflictResult.applyToAll) {
              if (globalConflictResult.action == ConflictAction.skip) {
                continue;
              } else if (globalConflictResult.action == ConflictAction.keepBoth) {
                zipName = await FileService.generateNonConflictingName(_destinationDir, zipName);
                targetPath = p.join(_destinationDir, zipName);
              }
            } else if (mounted) {
              final res = await ConflictDialog.show(
                context,
                sourcePath: zipName,
                targetPath: targetPath,
                isDirectory: false,
                hideReplace: true,
              );

              if (res == null) {
                setState(() {
                  _isProcessing = false;
                });
                return;
              }

              if (res.applyToAll) {
                globalConflictResult = res;
              }

              if (res.action == ConflictAction.skip) {
                continue;
              } else if (res.action == ConflictAction.keepBoth) {
                zipName = await FileService.generateNonConflictingName(_destinationDir, zipName);
                targetPath = p.join(_destinationDir, zipName);
              }
            }
          }

          tasks.add((sourcePaths: [itemPath], outputZipPath: targetPath));
        }

        if (tasks.isEmpty) {
          if (mounted) Navigator.of(context).pop();
          return;
        }

        if (mounted) {
          Navigator.of(context).pop();
        }

        ref.read(operationNotifierProvider.notifier).startCompressZip(
          sourcePaths: widget.paths,
          outputZipPath: tasks.first.outputZipPath,
          compressionLevel: _compressionLevel,
          deleteSourceFiles: _deleteSourceFiles,
          batchTasks: tasks,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inlineError = e.toString();
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isZip = _selectedFormat == 'zip';
    final isNoneEncryption = _selectedEncryption == 'none';

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          const Icon(Icons.archive_rounded, color: Color(0xFF38BDF8), size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Create Archive',
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.paths.length} item(s) selected',
                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
              ),
              const SizedBox(height: 12),

              // Archive name input
              TextField(
                controller: _nameController,
                enabled: !_createSeparateArchives && !_isProcessing,
                style: TextStyle(
                  color: _createSeparateArchives ? const Color(0xFF71717A) : Colors.white,
                  fontSize: 14,
                ),
                onChanged: (_) {
                  if (_inlineError != null) {
                    setState(() {
                      _inlineError = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Archive name',
                  labelStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
                  hintText: _createSeparateArchives
                      ? 'Separate archives (individual names)'
                      : 'archive.zip',
                  hintStyle: const TextStyle(color: Color(0xFF52525B)),
                  errorText: _inlineError,
                  errorMaxLines: 2,
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF141416),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF8BC34A)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Destination folder row with "..." button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, color: Color(0xFFA1A1AA), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Destination folder',
                            style: TextStyle(color: Color(0xFF71717A), fontSize: 10),
                          ),
                          Text(
                            _destinationDir,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD4D4D8),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      color: const Color(0xFF8BC34A),
                      tooltip: 'Pick destination folder',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isProcessing ? null : _pickDestinationFolder,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Format dropdown
              const Text(
                'Archive format',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _selectedFormat,
                dropdownColor: const Color(0xFF1E1E24),
                style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 13),
                isDense: true,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFF141416),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'zip',
                    child: Text('zip'),
                  ),
                  DropdownMenuItem(
                    value: '7z',
                    enabled: false,
                    child: Text('7z  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: 'tar',
                    enabled: false,
                    child: Text('tar  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: 'tar.gz',
                    enabled: false,
                    child: Text('tar.gz  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: 'tar.bz2',
                    enabled: false,
                    child: Text('tar.bz2  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: 'tar.xz',
                    enabled: false,
                    child: Text('tar.xz  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: 'tar.lz4',
                    enabled: false,
                    child: Text('tar.lz4  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: 'tar.zstd',
                    enabled: false,
                    child: Text('tar.zstd  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedFormat = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Compression level dropdown
              const Text(
                'Compression level',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                initialValue: _compressionLevel,
                dropdownColor: const Color(0xFF1E1E24),
                style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 13),
                isDense: true,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFF141416),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('None (Store)')),
                  DropdownMenuItem(value: 1, child: Text('Fastest')),
                  DropdownMenuItem(value: 3, child: Text('Fast')),
                  DropdownMenuItem(value: 6, child: Text('Normal')),
                  DropdownMenuItem(value: 8, child: Text('Maximum')),
                  DropdownMenuItem(value: 9, child: Text('Ultra')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _compressionLevel = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Encryption dropdown (only visible when format = zip / 7z)
              if (isZip || _selectedFormat == '7z') ...[
                const Text(
                  'Encryption',
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: _selectedEncryption,
                  dropdownColor: const Color(0xFF1E1E24),
                  style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 13),
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFF141416),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('None')),
                    DropdownMenuItem(
                      value: 'zipcrypto',
                      enabled: false,
                      child: Text('ZipCrypto  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                    ),
                    DropdownMenuItem(
                      value: 'aes128',
                      enabled: false,
                      child: Text('AES-128  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                    ),
                    DropdownMenuItem(
                      value: 'aes192',
                      enabled: false,
                      child: Text('AES-192  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                    ),
                    DropdownMenuItem(
                      value: 'aes256',
                      enabled: false,
                      child: Text('AES-256  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                    ),
                  ],
                  onChanged: (val) {},
                ),
                const SizedBox(height: 12),

                // Password field with show/hide icon (disabled when encryption = None)
                TextField(
                  controller: _passwordController,
                  enabled: !isNoneEncryption,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
                    hintText: 'Disabled (No encryption)',
                    hintStyle: const TextStyle(color: Color(0xFF52525B)),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF141416),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 18,
                        color: const Color(0xFF71717A),
                      ),
                      onPressed: isNoneEncryption
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Split into volumes dropdown (all disabled)
              const Text(
                'Split into volumes',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: 'none',
                dropdownColor: const Color(0xFF1E1E24),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
                isDense: true,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFF141416),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    enabled: false,
                    child: Text('No splitting  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: '10mb',
                    enabled: false,
                    child: Text('10 MB  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: '100mb',
                    enabled: false,
                    child: Text('100 MB  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: '700mb',
                    enabled: false,
                    child: Text('700 MB (CD)  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: '2gb',
                    enabled: false,
                    child: Text('2 GB (FAT32)  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                  DropdownMenuItem(
                    value: '4gb',
                    enabled: false,
                    child: Text('4 GB (DVD)  (Coming soon)', style: TextStyle(color: Color(0xFF71717A))),
                  ),
                ],
                onChanged: null,
              ),
              const SizedBox(height: 12),

              // Checkboxes
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -4),
                  activeColor: const Color(0xFF8BC34A),
                  checkColor: Colors.black,
                  side: const BorderSide(color: Color(0xFF52525B)),
                  title: const Text(
                    'Delete source files after compression',
                    style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13),
                  ),
                  value: _deleteSourceFiles,
                  onChanged: _isProcessing
                      ? null
                      : (val) {
                          setState(() {
                            _deleteSourceFiles = val ?? false;
                          });
                        },
                ),
              ),
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -4),
                  activeColor: const Color(0xFF8BC34A),
                  checkColor: Colors.black,
                  side: const BorderSide(color: Color(0xFF52525B)),
                  title: const Text(
                    'Create separate archives',
                    style: TextStyle(color: Color(0xFFEDEDED), fontSize: 13),
                  ),
                  subtitle: const Text(
                    'One archive per selected item',
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 11),
                  ),
                  value: _createSeparateArchives,
                  onChanged: _isProcessing
                      ? null
                      : (val) {
                          setState(() {
                            _createSeparateArchives = val ?? false;
                          });
                        },
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA))),
        ),
        Consumer(
          builder: (context, ref, _) => ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8BC34A),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isProcessing ? null : () => _submit(ref),
            child: _isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : const Text('OK', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
