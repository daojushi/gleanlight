import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import '../data/storage_manager.dart';
import 'supabase_sync_provider.dart';
import 'sync_config.dart';

const _backgroundSyncTask = 'its.background.sync';

@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _backgroundSyncTask) return true;
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final config = await SyncConfig.load();
      if (!config.enabled) return true;
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.anonKey,
      );
      if (Supabase.instance.client.auth.currentUser == null) return true;
      final storage = await StorageManager.load();
      final repository = storage.createRepository();
      await repository.initialize();
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('sync.deviceId') ?? const Uuid().v4();
      await prefs.setString('sync.deviceId', deviceId);
      final provider = SupabaseSyncProvider(
        repository,
        Supabase.instance.client,
        deviceId,
      );
      await provider.sync();
      await repository.close();
      await provider.stop();
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> configureBackgroundSync() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(syncCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _backgroundSyncTask,
    _backgroundSyncTask,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
