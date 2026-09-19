import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/data/sqlite_app_repository.dart';
import 'package:its_app/data/storage_manager.dart';
import 'package:its_app/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<SqliteAppRepository> repository() async {
  sqfliteFfiInit();
  final repo = SqliteAppRepository(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  await repo.initialize();
  return repo;
}

void main() {
  test('Idea supports long content and soft deletion', () async {
    final repo = await repository();
    await repo.saveIdea(
      content: '第一段\n\n第二段',
      status: IdeaStatus.newIdea,
      topicIds: const [],
    );
    final ideas = await repo.listIdeas();
    expect(ideas.single.content, '第一段\n\n第二段');
    expect(ideas.single.status, IdeaStatus.newIdea);
    await repo.softDelete('idea', ideas.single.id);
    expect(await repo.listIdeas(), isEmpty);
  });

  test('Task deadline is optional and completion is timestamped', () async {
    final repo = await repository();
    await repo.saveTask(
      title: '无 DDL',
      description: '',
      status: TaskStatus.todo,
      topicIds: const [],
    );
    var task = (await repo.listTasks()).single;
    expect(task.deadline, isNull);
    await repo.saveTask(
      id: task.id,
      title: task.title,
      description: '',
      status: TaskStatus.done,
      topicIds: const [],
    );
    task = (await repo.listTasks()).single;
    expect(task.completedAt, isNotNull);
  });

  test('Topic aggregates all three entity types', () async {
    final repo = await repository();
    await repo.saveTopic(name: 'Program Analysis', description: '程序分析');
    final topic = (await repo.listTopics()).single;
    await repo.saveIdea(
      content: 'Idea',
      status: IdeaStatus.newIdea,
      topicIds: [topic.id],
    );
    await repo.saveTask(
      title: 'Task',
      description: '',
      status: TaskStatus.todo,
      topicIds: [topic.id],
    );
    await repo.saveSchedule(
      title: 'Schedule',
      description: '',
      date: DateTime(2026, 9, 25),
      topicIds: [topic.id],
    );
    final aggregate = await repo.topicAggregate(topic.id);
    expect(aggregate!.ideas, hasLength(1));
    expect(aggregate.tasks, hasLength(1));
    expect(aggregate.schedules, hasLength(1));
  });

  test('sync snapshot merges newer records and keeps tombstones', () async {
    final directory = await Directory.systemTemp.createTemp('its-sync-test-');
    final source = SqliteAppRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}\\source.sqlite',
    );
    final target = SqliteAppRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}\\target.sqlite',
    );
    try {
      await source.initialize();
      await target.initialize();
      final id = await source.saveIdea(
        content: '跨设备内容',
        status: IdeaStatus.thinking,
        topicIds: const [],
      );
      var snapshot = await source.exportSyncSnapshot();
      expect(
        await target.mergeSyncSnapshot(snapshot, sourceDevice: 'phone'),
        1,
      );
      expect((await target.listIdeas()).single.content, '跨设备内容');

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await source.softDelete('idea', id);
      snapshot = await source.exportSyncSnapshot();
      expect(
        await target.mergeSyncSnapshot(snapshot, sourceDevice: 'phone'),
        1,
      );
      expect(await target.listIdeas(), isEmpty);
    } finally {
      await source.close();
      await target.close();
      await directory.delete(recursive: true);
    }
  });

  test('repositories own independent handles for the same database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'its-connection-test-',
    );
    final path = '${directory.path}\\shared.sqlite';
    final foreground = SqliteAppRepository(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final background = SqliteAppRepository(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    try {
      await foreground.initialize();
      await background.initialize();
      await background.close();
      await foreground.saveIdea(
        content: '前台连接仍然可用',
        status: IdeaStatus.newIdea,
        topicIds: const [],
      );
      expect((await foreground.listIdeas()).single.content, '前台连接仍然可用');
    } finally {
      await foreground.close();
      await directory.delete(recursive: true);
    }
  });

  test('equal-time sync conflict can be resolved explicitly', () async {
    final directory = await Directory.systemTemp.createTemp(
      'its-conflict-test-',
    );
    final repo = SqliteAppRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}\\conflict.sqlite',
    );
    try {
      await repo.initialize();
      final id = await repo.saveIdea(
        content: '本机版本',
        status: IdeaStatus.newIdea,
        topicIds: const [],
      );
      final snapshot = await repo.exportSyncSnapshot();
      final remote = Map<String, dynamic>.from(snapshot);
      remote['ideas'] = (snapshot['ideas'] as List)
          .map(
            (row) =>
                Map<String, Object?>.from(row as Map)..['content'] = '远程版本',
          )
          .toList();
      await repo.mergeSyncSnapshot(remote, sourceDevice: 'phone');
      final conflicts = await repo.listSyncConflicts();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.entityId, id);
      await repo.resolveSyncConflict(conflicts.single.id, useRemote: true);
      expect((await repo.listIdeas()).single.content, '远程版本');
      expect(await repo.listSyncConflicts(), isEmpty);
    } finally {
      await repo.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'sync comparison ignores JSON object key order and deduplicates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'its-sync-order-test-',
      );
      final repo = SqliteAppRepository(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}\\order.sqlite',
      );
      try {
        await repo.initialize();
        await repo.saveIdea(
          content: '相同内容',
          status: IdeaStatus.thinking,
          topicIds: const [],
        );
        final snapshot = await repo.exportSyncSnapshot();
        final original = Map<String, Object?>.from(
          (snapshot['ideas'] as List).single as Map,
        );
        final reordered = Map<String, Object?>.fromEntries(
          original.entries.toList().reversed,
        );
        await repo.mergeSyncSnapshot({
          ...snapshot,
          'ideas': [reordered],
        }, sourceDevice: 'phone');
        expect(await repo.listSyncConflicts(), isEmpty);

        reordered['content'] = '真正不同的内容';
        final changed = {
          ...snapshot,
          'ideas': [reordered],
        };
        await repo.mergeSyncSnapshot(changed, sourceDevice: 'phone');
        await repo.mergeSyncSnapshot(changed, sourceDevice: 'phone');
        expect(await repo.listSyncConflicts(), hasLength(1));
      } finally {
        await repo.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('all sync conflicts can be ignored or resolved in one action', () async {
    final directory = await Directory.systemTemp.createTemp(
      'its-sync-bulk-test-',
    );
    final repo = SqliteAppRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}\\bulk.sqlite',
    );
    try {
      await repo.initialize();
      await repo.saveIdea(
        content: '本机批量版本',
        status: IdeaStatus.newIdea,
        topicIds: const [],
      );
      final snapshot = await repo.exportSyncSnapshot();
      final remoteIdea = Map<String, Object?>.from(
        (snapshot['ideas'] as List).single as Map,
      )..['content'] = '远程批量版本';
      final changed = {
        ...snapshot,
        'ideas': [remoteIdea],
      };

      await repo.mergeSyncSnapshot(changed, sourceDevice: 'phone');
      await repo.ignoreAllSyncConflicts();
      expect(await repo.listSyncConflicts(), isEmpty);
      expect((await repo.listIdeas()).single.content, '本机批量版本');

      await repo.mergeSyncSnapshot(changed, sourceDevice: 'phone');
      await repo.resolveAllSyncConflicts(useRemote: true);
      expect(await repo.listSyncConflicts(), isEmpty);
      expect((await repo.listIdeas()).single.content, '远程批量版本');
    } finally {
      await repo.close();
      await directory.delete(recursive: true);
    }
  });

  test('stores image attachment and exports backup zip', () async {
    final directory = await Directory.systemTemp.createTemp('its-p1-test-');
    SqliteAppRepository? repo;
    try {
      repo = SqliteAppRepository(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}\\test.sqlite',
      );
      await repo.initialize();
      final ideaId = await repo.saveIdea(
        content: '# Markdown',
        status: IdeaStatus.newIdea,
        topicIds: const [],
      );
      final attachment = await repo.addIdeaAttachment(
        ideaId,
        'capture.png',
        'image/png',
        Uint8List.fromList([137, 80, 78, 71]),
      );
      expect(File(attachment.localPath).existsSync(), isTrue);
      expect((await repo.listIdeas()).single.attachments, hasLength(1));
      final backup = await repo.exportBackup('${directory.path}\\backup.zip');
      expect(File(backup).lengthSync(), greaterThan(0));
    } finally {
      await repo?.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'moves database and attachments then reloads from persisted location',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('its-move-test-');
      SqliteAppRepository? migrated;
      try {
        final originalRoot = Directory('${sandbox.path}\\original')
          ..createSync();
        final destination = Directory('${sandbox.path}\\destination')
          ..createSync();
        final preferences = File('${sandbox.path}\\config\\settings.json');
        await preferences.parent.create(recursive: true);
        final manager = StorageManager.forTesting(
          preferences,
          originalRoot.path,
        );
        final source = SqliteAppRepository(
          factory: databaseFactoryFfi,
          databasePath: '${originalRoot.path}\\its.sqlite',
        );
        await source.initialize();
        final id = await source.saveIdea(
          content: '需要迁移',
          status: IdeaStatus.newIdea,
          topicIds: const [],
        );
        await source.addIdeaAttachment(
          id,
          'image.png',
          'image/png',
          Uint8List.fromList([1, 2, 3]),
        );

        migrated = await manager.move(source, destination.path);
        final ideas = await migrated.listIdeas();
        expect(ideas.single.content, '需要迁移');
        expect(
          ideas.single.attachments.single.localPath,
          startsWith('${destination.path}\\ItsData'),
        );
        expect(
          File(ideas.single.attachments.single.localPath).existsSync(),
          isTrue,
        );
        expect(File('${originalRoot.path}\\its.sqlite').existsSync(), isFalse);
        expect(await preferences.readAsString(), contains('ItsData'));
      } finally {
        await migrated?.close();
        await sandbox.delete(recursive: true);
      }
    },
  );
}
