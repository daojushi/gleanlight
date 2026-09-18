import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/desktop_integration.dart';
import 'data/storage_manager.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageManager = await StorageManager.load();
  final controller = AppController(
    storageManager.createRepository(),
    storageManager,
  );
  final captureRequests = ValueNotifier<int>(0);
  final desktop = DesktopIntegration(captureRequests);
  runApp(ItsApp(controller: controller, captureRequests: captureRequests));
  controller.initialize();
  await desktop.initialize();
}

class ItsApp extends StatelessWidget {
  const ItsApp({
    super.key,
    required this.controller,
    required this.captureRequests,
  });
  final AppController controller;
  final ValueNotifier<int> captureRequests;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '拾光',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff27634d),
        surface: const Color(0xfffffefa),
      ),
      scaffoldBackgroundColor: const Color(0xfff5f4ef),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: Color(0xffdeddd6)),
        ),
      ),
    ),
    home: AppShell(controller: controller, captureRequests: captureRequests),
  );
}
