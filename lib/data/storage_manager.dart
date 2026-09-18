import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'sqlite_app_repository.dart';

class StorageManager {
  StorageManager._(this._preferencesFile, this.currentRoot);
  factory StorageManager.forTesting(File preferencesFile, String currentRoot) =>
      StorageManager._(preferencesFile, currentRoot);
  final File _preferencesFile;
  String currentRoot;
  static const _uuid = Uuid();

  static Future<StorageManager> load() async {
    final config = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : Directory(
            p.join(
              Platform.environment['APPDATA'] ??
                  Platform.environment['LOCALAPPDATA'] ??
                  Directory.current.path,
              'com.localfirst',
              'its_app',
            ),
          );
    await config.create(recursive: true);
    final preferences = File(p.join(config.path, 'settings.json'));
    var root = config.path;
    if (await preferences.exists()) {
      try {
        final value = jsonDecode(
          await preferences.readAsString(),
        ) as Map<String, dynamic>;
        final configured = value['storageRoot'] as String?;
        if (configured != null && configured.isNotEmpty) {
          root = p.normalize(configured);
        }
      } catch (_) {
        // A malformed preference must never make the user's existing database inaccessible.
      }
    }
    return StorageManager._(preferences, root);
  }

  String get databasePath => p.join(currentRoot, 'its.sqlite');
  SqliteAppRepository createRepository() =>
      SqliteAppRepository(databasePath: databasePath);

  Future<SqliteAppRepository> move(
    SqliteAppRepository source,
    String selectedDirectory,
  ) async {
    final selected = Directory(p.normalize(selectedDirectory));
    final target = Directory(p.join(selected.path, 'ItsData'));
    if (p.equals(p.normalize(source.storageRoot), p.normalize(target.path)) ||
        p.equals(p.normalize(source.storageRoot), p.normalize(selected.path))) {
      return source;
    }
    if (await target.exists() && !(await target.list().isEmpty)) {
      throw StateError('目标位置已存在非空的 ItsData 文件夹，请选择其他位置');
    }

    final staging = Directory(
      p.join(selected.path, '.its-data-migrating-${_uuid.v4()}'),
    );
    await staging.create(recursive: true);
    final oldRoot = source.storageRoot;
    try {
      await source.close();
      final oldDb = File(p.join(oldRoot, 'its.sqlite'));
      if (!await oldDb.exists()) {
        throw StateError('原数据库不存在，无法迁移');
      }
      await oldDb.copy(p.join(staging.path, 'its.sqlite'));
      final oldAttachments = Directory(p.join(oldRoot, 'attachments'));
      if (await oldAttachments.exists()) {
        await _copyDirectory(
          oldAttachments,
          Directory(p.join(staging.path, 'attachments')),
        );
      }

      final validation = SqliteAppRepository(
        databasePath: p.join(staging.path, 'its.sqlite'),
      );
      await validation.initialize();
      await validation.rewriteAttachmentPaths(staging.path);
      await validation.validateStorage();
      await validation.close();

      if (await target.exists()) {
        await target.delete();
      }
      await staging.rename(target.path);
      final migrated = SqliteAppRepository(
        databasePath: p.join(target.path, 'its.sqlite'),
      );
      await migrated.initialize();
      await migrated.rewriteAttachmentPaths(target.path);
      await _savePreference(target.path);
      currentRoot = target.path;
      try {
        if (await oldDb.exists()) {
          await oldDb.delete();
        }
        if (await oldAttachments.exists()) {
          await oldAttachments.delete(recursive: true);
        }
      } catch (_) {
        // The new, validated copy is active; stale source cleanup can safely be retried manually.
      }
      return migrated;
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      try {
        await source.initialize();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _savePreference(String root) async {
    final temporary = File('${_preferencesFile.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'storageRoot': root,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (await _preferencesFile.exists()) {
      await _preferencesFile.delete();
    }
    await temporary.rename(_preferencesFile.path);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destinationPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(destinationPath);
      }
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destinationPath));
      }
    }
  }
}
