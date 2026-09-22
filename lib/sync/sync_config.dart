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
  bool get enabled {
    try {
      return normalizeUrl(url).isNotEmpty && anonKey.trim().isNotEmpty;
    } on FormatException {
      return false;
    }
  }

  static String normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入完整的 HTTPS 项目地址');
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isNotEmpty && path != '/auth/v1/health') {
      throw const FormatException('请填写项目根地址，不要附加 API 路径');
    }
    return uri.origin;
  }

  static Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    var url = prefs.getString('sync.supabase.url') ?? '';
    if (url.isNotEmpty) {
      try {
        url = normalizeUrl(url);
      } on FormatException {
        // Keep invalid values editable in Settings without enabling sync.
      }
    }
    return SyncConfig(
      url: url,
      anonKey: prefs.getString('sync.supabase.anonKey') ?? '',
      autoSyncDelaySeconds: prefs.getInt('sync.autoSyncDelaySeconds') ?? 10,
    );
  }

  Future<void> save() async {
    final normalized = url.trim().isEmpty ? '' : normalizeUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync.supabase.url', normalized);
    await prefs.setString('sync.supabase.anonKey', anonKey.trim());
    await prefs.setInt(
      'sync.autoSyncDelaySeconds',
      autoSyncDelaySeconds.clamp(1, 3600),
    );
  }
}
