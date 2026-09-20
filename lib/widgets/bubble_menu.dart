import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';

class BubbleData {
  final String label;
  final IconData icon;
  final Color accentColor;

  const BubbleData({
    required this.label,
    required this.icon,
    required this.accentColor,
  });
}

class BubbleMenu extends ConsumerWidget {
  const BubbleMenu({super.key});

  static const List<BubbleData> bubbles = [
    BubbleData(
      label: 'Root',
      icon: Icons.shield_rounded,
      accentColor: Color(0xFFFF5722),
    ),
    BubbleData(
      label: 'Internal Storage',
      icon: Icons.smartphone_rounded,
      accentColor: Color(0xFF29B6F6),
    ),
    BubbleData(
      label: 'Android/data',
      icon: Icons.apps_rounded,
      accentColor: Color(0xFF26A69A),
    ),
    BubbleData(
      label: 'Android/obb',
      icon: Icons.extension_rounded,
      accentColor: Color(0xFFFFB300),
    ),
    BubbleData(
      label: 'Downloads',
      icon: Icons.download_rounded,
      accentColor: Color(0xFFAB47BC),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedBubbleIndexProvider);

    return Material(
      color: const Color(0xFF141416),
      child: SizedBox(
        width: 56,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: bubbles.length,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final bubble = bubbles[index];
                    final isSelected = selectedIndex == index;

                    return Tooltip(
                      message: bubble.label,
                      preferBelow: false,
                      waitDuration: const Duration(milliseconds: 400),
                      child: InkWell(
                        onTap: () {
                          if (selectedIndex != index) {
                            ref.read(selectedFilesProvider.notifier).clear();
                            ref.read(selectedBubbleIndexProvider.notifier).state = index;
                          }
                        },
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? bubble.accentColor.withAlpha(50)
                                : const Color(0xFF222226),
                            border: Border.all(
                              color: isSelected
                                  ? bubble.accentColor
                                  : const Color(0xFF2E2E34),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            bubble.icon,
                            size: 20,
                            color: isSelected
                                ? bubble.accentColor
                                : const Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
