import 'package:shared_preferences/shared_preferences.dart';

class SyncConfig {
  const SyncConfig({
    required this.url,
    required this.anonKey,
    this.autoSyncDelaySeconds = 10,
  });
  final String url;
  final String anonKey;
  final int autoSyncDelaySeconds;
  bool get enabled => url.startsWith('https://') && anonKey.isNotEmpty;

  static Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncConfig(
      url: prefs.getString('sync.supabase.url') ?? '',
      anonKey: prefs.getString('sync.supabase.anonKey') ?? '',
      autoSyncDelaySeconds: prefs.getInt('sync.autoSyncDelaySeconds') ?? 10,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync.supabase.url', url.trim());
    await prefs.setString('sync.supabase.anonKey', anonKey.trim());
    await prefs.setInt(
      'sync.autoSyncDelaySeconds',
      autoSyncDelaySeconds.clamp(1, 3600),
    );
  }
}
