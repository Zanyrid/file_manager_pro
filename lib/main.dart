import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: FileManagerProApp(),
    ),
  );
}

typedef MyApp = FileManagerProApp;

class FileManagerProApp extends StatelessWidget {
  const FileManagerProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Manager Pro',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121214),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF18181B),
          primary: Color(0xFF3B82F6),
          onPrimary: Colors.white,
          onSurface: Color(0xFFEDEDED),
        ),
        dividerColor: const Color(0xFF27272A),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF27272A),
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: const TextStyle(
            color: Color(0xFFEDEDED),
            fontSize: 12,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
