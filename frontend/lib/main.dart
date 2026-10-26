import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

/// App-wide light/dark switch.
final themeMode = ValueNotifier(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const DevMateApp());
}

class DevMateApp extends StatelessWidget {
  const DevMateApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'DevMate AI',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          home: const HomeScreen(),
        ),
      );
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Toggle theme',
        icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
        onPressed: () => themeMode.value =
            Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
      );
}
