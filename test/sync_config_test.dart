import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/sync/sync_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'health-check URL is repaired on save and when loading old settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync.supabase.url': 'https://example.supabase.co/auth/v1/health',
        'sync.supabase.anonKey': 'key',
      });
      expect((await SyncConfig.load()).url, 'https://example.supabase.co');
      await const SyncConfig(
        url: ' https://example.supabase.co/auth/v1/health/ ',
        anonKey: 'key',
      ).save();
      expect((await SyncConfig.load()).url, 'https://example.supabase.co');
    },
  );

  test(
    'invalid API paths are rejected without replacing saved configuration',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync.supabase.url': 'https://example.supabase.co',
      });
      await expectLater(
        const SyncConfig(
          url: 'https://example.supabase.co/rest/v1',
          anonKey: 'key',
        ).save(),
        throwsFormatException,
      );
      expect((await SyncConfig.load()).url, 'https://example.supabase.co');
      expect(
        const SyncConfig(url: 'https://', anonKey: 'key').enabled,
        isFalse,
      );
    },
  );

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
