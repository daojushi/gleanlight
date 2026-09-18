import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'app/app_controller.dart';
import 'app/desktop_integration.dart';
import 'app/android_share_integration.dart';
import 'app/appearance_settings.dart';
import 'data/storage_manager.dart';
import 'ui/app_shell.dart';
import 'sync/sync_config.dart';
import 'sync/background_sync.dart';
import 'sync/sync_provider.dart';
import 'sync/supabase_sync_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureBackgroundSync();
  final storageManager = await StorageManager.load();
  final appearance = await AppearanceSettings.load();
  final repository = storageManager.createRepository();
  final syncConfig = await SyncConfig.load();
  SupabaseClient? supabase;
  SyncProvider syncProvider = const NoSyncProvider();
  if (syncConfig.enabled) {
    await Supabase.initialize(
      url: syncConfig.url,
      publishableKey: syncConfig.anonKey,
    );
    supabase = Supabase.instance.client;
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString('sync.deviceId');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await preferences.setString('sync.deviceId', deviceId);
    }
    syncProvider = SupabaseSyncProvider(repository, supabase, deviceId);
  }
  final controller = AppController(
    repository,
    storageManager,
    syncProvider,
    supabase,
  );
  final captureRequests = ValueNotifier<String?>(null);
  final desktop = DesktopIntegration(captureRequests);
  final androidShare = AndroidShareIntegration(captureRequests);
  runApp(
    ItsApp(
      controller: controller,
      captureRequests: captureRequests,
      appearance: appearance,
    ),
  );
  controller.initialize();
  await desktop.initialize();
  await androidShare.initialize();
}

class ItsApp extends StatelessWidget {
  const ItsApp({
    super.key,
    required this.controller,
    required this.captureRequests,
    required this.appearance,
  });
  final AppController controller;
  final ValueNotifier<String?> captureRequests;
  final AppearanceSettings appearance;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appearance,
    builder: (context, _) => MaterialApp(
      title: '拾光',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff27634d),
          surface: const Color(0xfffffefa),
        ),
        scaffoldBackgroundColor: const Color(0xfff5f4ef),
        fontFamily: appearance.fontFamily,
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
      home: AppShell(
        controller: controller,
        captureRequests: captureRequests,
        appearance: appearance,
      ),
    ),
  );
}
