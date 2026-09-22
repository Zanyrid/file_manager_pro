import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/view_options_state.dart';

class ViewOptionsPopup extends ConsumerWidget {
  const ViewOptionsPopup({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss view options',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, anim1, anim2) {
        return const SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(top: 52.0, right: 12.0, left: 12.0),
              child: Material(
                color: Colors.transparent,
                child: ViewOptionsPopup(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.04),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(viewOptionsProvider);
    final notifier = ref.read(viewOptionsProvider.notifier);

    const greenAccent = Color(0xFF8BC34A);

    return Container(
      constraints: const BoxConstraints(maxWidth: 540),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E36), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: View type + Hidden files toggle
          Row(
            children: [
              // Radio tabs for View type
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RadioUnderlineTab(
                    label: 'Detailed',
                    isSelected: state.viewType == ViewType.detailed,
                    onTap: () => notifier.setViewType(ViewType.detailed),
                  ),
                  const SizedBox(width: 4),
                  _RadioUnderlineTab(
                    label: 'Compact',
                    isSelected: state.viewType == ViewType.compact,
                    onTap: () => notifier.setViewType(ViewType.compact),
                  ),
                  const SizedBox(width: 4),
                  _RadioUnderlineTab(
                    label: 'Grid',
                    isSelected: state.viewType == ViewType.grid,
                    onTap: () => notifier.setViewType(ViewType.grid),
                  ),
                ],
              ),
              const Spacer(),
              // Hidden files toggle
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => notifier.toggleHiddenFiles(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Hidden files',
                        style: TextStyle(
                          color: Color(0xFFD4D4D8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          value: state.showHiddenFiles,
                          activeThumbColor: greenAccent,
                          activeTrackColor: greenAccent.withValues(alpha: 0.35),
                          inactiveThumbColor: const Color(0xFF71717A),
                          inactiveTrackColor: const Color(0xFF27272A),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (_) => notifier.toggleHiddenFiles(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFF27272A),
            ),
          ),

          // Row 2: Sort + Sort direction toggle
          Row(
            children: [
              // Radio tabs for Sort field
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RadioUnderlineTab(
                    label: 'Name',
                    isSelected: state.sortField == SortField.name,
                    onTap: () => notifier.setSortField(SortField.name),
                  ),
                  const SizedBox(width: 4),
                  _RadioUnderlineTab(
                    label: 'Size',
                    isSelected: state.sortField == SortField.size,
                    onTap: () => notifier.setSortField(SortField.size),
                  ),
                  const SizedBox(width: 4),
                  _RadioUnderlineTab(
                    label: 'Date',
                    isSelected: state.sortField == SortField.date,
                    onTap: () => notifier.setSortField(SortField.date),
                  ),
                  const SizedBox(width: 4),
                  _RadioUnderlineTab(
                    label: 'Type',
                    isSelected: state.sortField == SortField.type,
                    onTap: () => notifier.setSortField(SortField.type),
                  ),
                ],
              ),
              const Spacer(),
              // Sort direction toggle button (Ascending / Descending)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => notifier.toggleSortDirection(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25252D),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: greenAccent.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.sortDirection == SortDirection.ascending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: greenAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.sortDirection == SortDirection.ascending
                            ? 'Ascending'
                            : 'Descending',
                        style: const TextStyle(
                          color: greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadioUnderlineTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RadioUnderlineTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const greenAccent = Color(0xFF8BC34A);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? greenAccent : const Color(0xFFA1A1AA),
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: isSelected ? greenAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
