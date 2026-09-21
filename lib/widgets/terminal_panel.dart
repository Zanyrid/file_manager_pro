import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/operation_models.dart';
import '../state/operation_state.dart';

class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({super.key});

  @override
  ConsumerState<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends ConsumerState<TerminalPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getLogColor(LogLevel level) {
    switch (level) {
      case LogLevel.command:
        return const Color(0xFF38BDF8); // Light blue / cyan
      case LogLevel.success:
        return const Color(0xFF4ADE80); // Green
      case LogLevel.warning:
        return const Color(0xFFFBBF24); // Amber
      case LogLevel.error:
        return const Color(0xFFF87171); // Red
      case LogLevel.progress:
        return const Color(0xFFA78BFA); // Purple
      case LogLevel.info:
        return const Color(0xFFD4D4D8); // Light gray / white
    }
  }

  String _getOperationTitle(OperationType? type) {
    switch (type) {
      case OperationType.copy:
        return 'Copy Operation';
      case OperationType.move:
        return 'Move Operation';
      case OperationType.delete:
        return 'Delete Operation';
      case OperationType.extract:
        return 'ZIP Extraction';
      case OperationType.compress:
        return 'ZIP Compression';
      case null:
        return 'Terminal Logs';
    }
  }

  String _getStatusPillText(OperationState opState) {
    if (opState.isRunning) return 'RUNNING';
    if (opState.status == OperationStatus.cancelled) return 'CANCELLED';
    final summary = opState.summary;
    if (summary != null) {
      if (summary.failed > 0) return 'COMPLETED WITH ERRORS';
      if (summary.succeeded > 0) return 'DONE';
      return 'NOTHING DONE';
    }
    return opState.status == OperationStatus.done ? 'DONE' : opState.status.name.toUpperCase();
  }

  Color _getStatusColor(OperationState opState) {
    if (opState.isRunning) return const Color(0xFF3B82F6);
    if (opState.status == OperationStatus.cancelled) return const Color(0xFFF59E0B);
    final summary = opState.summary;
    if (summary != null) {
      if (summary.failed > 0) return const Color(0xFFEF4444);
      if (summary.succeeded > 0) return const Color(0xFF22C55E);
      return const Color(0xFFF59E0B);
    }
    if (opState.status == OperationStatus.done) return const Color(0xFF22C55E);
    if (opState.status == OperationStatus.error) return const Color(0xFFEF4444);
    return const Color(0xFF71717A);
  }

  String _getFooterStatusText(OperationState opState) {
    if (opState.status == OperationStatus.cancelled) {
      return 'Operation cancelled by user.';
    }
    final summary = opState.summary;
    if (summary == null) {
      return opState.status == OperationStatus.done
          ? 'Done.'
          : 'Operation finished.';
    }

    if (summary.failed > 0) {
      return 'Completed with errors: ${summary.failed} failed, ${summary.succeeded} processed.';
    }

    if (summary.succeeded > 0) {
      return 'Done: ${summary.succeeded} item(s) processed.';
    }

    if (summary.skipped > 0) {
      return 'Nothing done: all ${summary.skipped} item(s) skipped.';
    }
    if (opState.type == OperationType.extract) {
      return 'Nothing done: invalid or empty archive.';
    }
    if (opState.type == OperationType.compress) {
      return 'Nothing done: no files found to compress.';
    }
    return 'Nothing done: no items processed.';
  }

  @override
  Widget build(BuildContext context) {
    final opState = ref.watch(operationNotifierProvider);

    // Auto-scroll when logs change
    ref.listen<OperationState>(operationNotifierProvider, (previous, next) {
      if (previous?.logs.length != next.logs.length) {
        _scrollToBottom();
      }
    });

    final isRunning = opState.isRunning;

    return Material(
      color: const Color(0xFF09090B),
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              border: Border(
                bottom: BorderSide(color: Color(0xFF27272A), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal_rounded, size: 18, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    Text(
                      _getOperationTitle(opState.type),
                      style: const TextStyle(
                        color: Color(0xFFEDEDED),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _getStatusColor(opState).withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _getStatusColor(opState),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _getStatusPillText(opState),
                        style: TextStyle(
                          color: _getStatusColor(opState),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isRunning)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          ref.read(operationNotifierProvider.notifier).cancel();
                        },
                        icon: const Icon(Icons.stop_rounded, size: 14),
                        label: const Text('Cancel', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
                if (isRunning || opState.progress > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: opState.progress > 0 ? opState.progress : null,
                      minHeight: 4,
                      backgroundColor: const Color(0xFF27272A),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isRunning ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          opState.currentItem != null ? 'Current: ${opState.currentItem}' : 'Processing...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        '${(opState.progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Log View Area
          Expanded(
            child: SelectionArea(
              child: opState.logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs to display.',
                        style: TextStyle(
                          color: Color(0xFF52525B),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: opState.logs.length,
                      itemBuilder: (context, index) {
                        final log = opState.logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            log.text,
                            style: TextStyle(
                              color: _getLogColor(log.level),
                              fontSize: 12,
                              fontFamily: 'monospace',
                              height: 1.35,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Footer Action Bar (When finished)
          if (!isRunning)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF141418),
                border: Border(
                  top: BorderSide(color: Color(0xFF27272A), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _getFooterStatusText(opState),
                      style: TextStyle(
                        color: _getStatusColor(opState),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      ref.read(operationNotifierProvider.notifier).closeTerminal();
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back to files', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
