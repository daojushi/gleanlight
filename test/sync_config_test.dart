import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/sync/sync_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('auto sync delay defaults to ten seconds and persists', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await SyncConfig.load()).autoSyncDelaySeconds, 10);

    await const SyncConfig(
      url: 'https://example.supabase.co',
      anonKey: 'key',
      autoSyncDelaySeconds: 25,
    ).save();

    final saved = await SyncConfig.load();
    expect(saved.autoSyncDelaySeconds, 25);
    expect(saved.url, 'https://example.supabase.co');
  });
}
