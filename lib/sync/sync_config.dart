import 'package:shared_preferences/shared_preferences.dart';

class SyncConfig {
  const SyncConfig({required this.url, required this.anonKey});
  final String url;
  final String anonKey;
  bool get enabled => url.startsWith('https://') && anonKey.isNotEmpty;

  static Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncConfig(
      url: prefs.getString('sync.supabase.url') ?? '',
      anonKey: prefs.getString('sync.supabase.anonKey') ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync.supabase.url', url.trim());
    await prefs.setString('sync.supabase.anonKey', anonKey.trim());
  }
}
