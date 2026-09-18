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
