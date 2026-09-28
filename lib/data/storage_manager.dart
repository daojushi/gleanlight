import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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

  Future<SqliteAppRepository> restoreBackup(
    SqliteAppRepository source,
    String backupPath,
  ) async {
    final backup = File(p.normalize(backupPath));
    if (!await backup.exists()) throw StateError('备份文件不存在');

    final parent = Directory(p.dirname(currentRoot));
    final staging = Directory(
      p.join(parent.path, '.its-restore-${_uuid.v4()}'),
    );
    final rollback = Directory(
      p.join(parent.path, '.its-rollback-${_uuid.v4()}'),
    );
    await staging.create(recursive: true);
    SqliteAppRepository? restored;
    var sourceClosed = false;
    var switched = false;
    try {
      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      final databaseEntry = archive.findFile('database.sqlite');
      if (databaseEntry == null || !databaseEntry.isFile) {
        throw StateError('不是有效的拾光备份：缺少 database.sqlite');
      }
      var extractedBytes = 0;
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        final valid =
            name == 'database.sqlite' ||
            name == 'data.json' ||
            name.startsWith('attachments/');
        final segments = p.posix.split(name);
        if (!valid ||
            p.posix.isAbsolute(name) ||
            segments.contains('..') ||
            segments.contains('.')) {
          throw StateError('备份包含不安全或未知的文件：${entry.name}');
        }
        extractedBytes += entry.size;
        if (extractedBytes > 2 * 1024 * 1024 * 1024) {
          throw StateError('备份解压后超过 2 GB，已停止导入');
        }
        final relative = name == 'database.sqlite' ? 'its.sqlite' : name;
        final destination = File(
          p.joinAll([staging.path, ...p.posix.split(relative)]),
        );
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(entry.content as List<int>, flush: true);
      }

      final validation = SqliteAppRepository(
        databasePath: p.join(staging.path, 'its.sqlite'),
      );
      await validation.initialize();
      await validation.rewriteAttachmentPaths(staging.path);
      await validation.validateStorage();
      await validation.close();

      await source.close();
      sourceClosed = true;
      await rollback.create(recursive: true);
      final currentDatabase = File(databasePath);
      final currentAttachments = Directory(p.join(currentRoot, 'attachments'));
      if (await currentDatabase.exists()) {
        await currentDatabase.rename(p.join(rollback.path, 'its.sqlite'));
      }
      if (await currentAttachments.exists()) {
        await currentAttachments.rename(p.join(rollback.path, 'attachments'));
      }

      switched = true;
      await File(p.join(staging.path, 'its.sqlite')).rename(databasePath);
      final stagedAttachments = Directory(p.join(staging.path, 'attachments'));
      if (await stagedAttachments.exists()) {
        await stagedAttachments.rename(p.join(currentRoot, 'attachments'));
      }
      restored = SqliteAppRepository(databasePath: databasePath);
      await restored.initialize();
      await restored.rewriteAttachmentPaths(currentRoot);
      await restored.validateStorage();
      await rollback.delete(recursive: true);
      return restored;
    } catch (_) {
      try {
        await restored?.close();
      } catch (_) {}
      if (switched) {
        final currentDatabase = File(databasePath);
        final currentAttachments = Directory(
          p.join(currentRoot, 'attachments'),
        );
        if (await currentDatabase.exists()) await currentDatabase.delete();
        if (await currentAttachments.exists()) {
          await currentAttachments.delete(recursive: true);
        }
      }
      if (await rollback.exists()) {
        final oldDatabase = File(p.join(rollback.path, 'its.sqlite'));
        final oldAttachments = Directory(p.join(rollback.path, 'attachments'));
        if (await oldDatabase.exists()) await oldDatabase.rename(databasePath);
        if (await oldAttachments.exists()) {
          await oldAttachments.rename(p.join(currentRoot, 'attachments'));
        }
        await rollback.delete(recursive: true);
      }
      if (sourceClosed) {
        try {
          await source.initialize();
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

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
