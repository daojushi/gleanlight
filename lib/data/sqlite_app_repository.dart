import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import 'app_repository.dart';

class SqliteAppRepository implements AppRepository {
  SqliteAppRepository({this.factory, this.databasePath});
  final DatabaseFactory? factory;
  final String? databasePath;
  final _uuid = const Uuid();
  late Database _db;
  late String _openedPath;

  Future<void> close() => _db.close();

  @override
  Future<void> initialize() async {
    sqfliteFfiInit();
    final selectedFactory = factory ?? databaseFactoryFfi;
    final path = databasePath ?? await _defaultDatabasePath();
    _openedPath = path;
    _db = await selectedFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE ideas (id TEXT PRIMARY KEY, content TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT)',
          );
          await db.execute(
            "CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, deadline TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, completed_at TEXT, deleted_at TEXT)",
          );
          await db.execute(
            "CREATE TABLE schedules (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', date TEXT NOT NULL, start_time TEXT, end_time TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT)",
          );
          await db.execute(
            "CREATE TABLE topics (id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, description TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT)",
          );
          await db.execute(
            'CREATE TABLE entity_topics (entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, topic_id TEXT NOT NULL, PRIMARY KEY(entity_type, entity_id, topic_id), FOREIGN KEY(topic_id) REFERENCES topics(id))',
          );
          await db.execute(
            'CREATE INDEX idx_ideas_created ON ideas(created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX idx_tasks_deadline ON tasks(deadline)',
          );
          await db.execute(
            'CREATE INDEX idx_schedules_date ON schedules(date, start_time)',
          );
          await _createAttachments(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createAttachments(db);
        },
      ),
    );
  }

  Future<void> _createAttachments(DatabaseExecutor db) => db.execute(
    'CREATE TABLE IF NOT EXISTS attachments (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, mime_type TEXT NOT NULL, file_name TEXT NOT NULL, size INTEGER NOT NULL, hash TEXT NOT NULL, local_path TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT)',
  );

  Future<String> _defaultDatabasePath() async {
    final root =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    final directory = Directory(p.join(root, 'com.localfirst', 'its_app'));
    await directory.create(recursive: true);
    return p.join(directory.path, 'its.sqlite');
  }

  DateTime _date(Object? value) => DateTime.parse(value! as String);
  DateTime? _nullableDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  Future<List<Topic>> _topicsFor(String type, String id) async {
    final rows = await _db.rawQuery(
      'SELECT t.* FROM topics t JOIN entity_topics et ON et.topic_id=t.id WHERE et.entity_type=? AND et.entity_id=? AND t.deleted_at IS NULL ORDER BY t.name',
      [type, id],
    );
    return rows.map(_topicFromRow).toList();
  }

  Future<List<Attachment>> _attachmentsFor(String ideaId) async {
    final rows = await _db.query(
      'attachments',
      where: "owner_type='idea' AND owner_id=? AND deleted_at IS NULL",
      whereArgs: [ideaId],
      orderBy: 'created_at',
    );
    return rows
        .map(
          (row) => Attachment(
            id: row['id']! as String,
            ownerId: row['owner_id']! as String,
            mimeType: row['mime_type']! as String,
            fileName: row['file_name']! as String,
            size: row['size']! as int,
            hash: row['hash']! as String,
            localPath: row['local_path']! as String,
            createdAt: _date(row['created_at']),
          ),
        )
        .toList();
  }

  Topic _topicFromRow(Map<String, Object?> row) => Topic(
    id: row['id']! as String,
    name: row['name']! as String,
    description: row['description']! as String,
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
    itemCount: (row['item_count'] as int?) ?? 0,
  );
  Future<Idea> _ideaFromRow(Map<String, Object?> row) async => Idea(
    id: row['id']! as String,
    content: row['content']! as String,
    status: IdeaStatusX.fromDb(row['status']! as String),
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
    topics: await _topicsFor('idea', row['id']! as String),
    attachments: await _attachmentsFor(row['id']! as String),
  );
  Future<AppTask> _taskFromRow(Map<String, Object?> row) async => AppTask(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    status: TaskStatusX.fromDb(row['status']! as String),
    deadline: _nullableDate(row['deadline']),
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
    completedAt: _nullableDate(row['completed_at']),
    topics: await _topicsFor('task', row['id']! as String),
  );
  Future<Schedule> _scheduleFromRow(Map<String, Object?> row) async => Schedule(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    date: _date(row['date']),
    startTime: row['start_time'] as String?,
    endTime: row['end_time'] as String?,
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
    topics: await _topicsFor('schedule', row['id']! as String),
  );

  @override
  Future<List<Idea>> listIdeas() async {
    final rows = await _db.query(
      'ideas',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map(_ideaFromRow));
  }

  @override
  Future<List<AppTask>> listTasks() async {
    final rows = await _db.rawQuery(
      "SELECT * FROM tasks WHERE deleted_at IS NULL ORDER BY CASE status WHEN 'Doing' THEN 0 WHEN 'Todo' THEN 1 ELSE 2 END, deadline IS NULL, deadline, created_at DESC",
    );
    return Future.wait(rows.map(_taskFromRow));
  }

  @override
  Future<List<Schedule>> listSchedules() async {
    final rows = await _db.query(
      'schedules',
      where: 'deleted_at IS NULL',
      orderBy: 'date, start_time IS NULL, start_time',
    );
    return Future.wait(rows.map(_scheduleFromRow));
  }

  @override
  Future<List<Topic>> listTopics() async {
    final rows = await _db.rawQuery(
      'SELECT t.*, COUNT(et.entity_id) item_count FROM topics t LEFT JOIN entity_topics et ON et.topic_id=t.id WHERE t.deleted_at IS NULL GROUP BY t.id ORDER BY t.name',
    );
    return rows.map(_topicFromRow).toList();
  }

  Future<void> _setTopics(
    Transaction txn,
    String type,
    String id,
    List<String> topicIds,
  ) async {
    await txn.delete(
      'entity_topics',
      where: 'entity_type=? AND entity_id=?',
      whereArgs: [type, id],
    );
    for (final topicId in topicIds.toSet()) {
      await txn.insert('entity_topics', {
        'entity_type': type,
        'entity_id': id,
        'topic_id': topicId,
      });
    }
  }

  Future<Map<String, Object?>> _base(String table, String? id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    if (id != null) {
      final rows = await _db.query(
        table,
        columns: ['created_at'],
        where: 'id=?',
        whereArgs: [id],
      );
      return {
        'id': id,
        'created_at': rows.isEmpty ? now : rows.first['created_at'],
        'updated_at': now,
        'deleted_at': null,
      };
    }
    return {
      'id': _uuid.v4(),
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    };
  }

  @override
  Future<String> saveIdea({
    String? id,
    required String content,
    required IdeaStatus status,
    required List<String> topicIds,
  }) async {
    if (content.trim().isEmpty) throw ArgumentError('Idea 内容不能为空');
    final data = await _base('ideas', id)
      ..addAll({'content': content.trim(), 'status': status.dbValue});
    await _db.transaction((txn) async {
      await txn.insert(
        'ideas',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _setTopics(txn, 'idea', data['id']! as String, topicIds);
    });
    return data['id']! as String;
  }

  @override
  Future<void> saveTask({
    String? id,
    required String title,
    required String description,
    required TaskStatus status,
    DateTime? deadline,
    required List<String> topicIds,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('标题不能为空');
    final data = await _base('tasks', id);
    DateTime? completedAt;
    if (status == TaskStatus.done) {
      final old = id == null
          ? const <Map<String, Object?>>[]
          : await _db.query(
              'tasks',
              columns: ['completed_at'],
              where: 'id=?',
              whereArgs: [id],
            );
      completedAt = old.isEmpty
          ? DateTime.now().toUtc()
          : _nullableDate(old.first['completed_at']) ?? DateTime.now().toUtc();
    }
    data.addAll({
      'title': title.trim(),
      'description': description.trim(),
      'status': status.dbValue,
      'deadline': deadline?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    });
    await _db.transaction((txn) async {
      await txn.insert(
        'tasks',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _setTopics(txn, 'task', data['id']! as String, topicIds);
    });
  }

  @override
  Future<void> saveSchedule({
    String? id,
    required String title,
    required String description,
    required DateTime date,
    String? startTime,
    String? endTime,
    required List<String> topicIds,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('标题不能为空');
    if (startTime != null &&
        endTime != null &&
        endTime.compareTo(startTime) <= 0) {
      throw ArgumentError('结束时间必须晚于开始时间');
    }
    final data = await _base('schedules', id)
      ..addAll({
        'title': title.trim(),
        'description': description.trim(),
        'date': DateTime(date.year, date.month, date.day).toIso8601String(),
        'start_time': startTime,
        'end_time': endTime,
      });
    await _db.transaction((txn) async {
      await txn.insert(
        'schedules',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _setTopics(txn, 'schedule', data['id']! as String, topicIds);
    });
  }

  @override
  Future<void> saveTopic({
    String? id,
    required String name,
    required String description,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Topic 名称不能为空');
    final data = await _base('topics', id)
      ..addAll({'name': name.trim(), 'description': description.trim()});
    await _db.insert(
      'topics',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> softDelete(String entityType, String id) async {
    const tables = {'idea': 'ideas', 'task': 'tasks', 'schedule': 'schedules'};
    final table = tables[entityType];
    if (table == null) throw ArgumentError('未知实体类型');
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update(
        table,
        {'deleted_at': now, 'updated_at': now},
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.delete(
        'entity_topics',
        where: 'entity_type=? AND entity_id=?',
        whereArgs: [entityType, id],
      );
    });
  }

  @override
  Future<TopicAggregate?> topicAggregate(String topicId) async {
    final rows = await _db.query(
      'topics',
      where: 'id=? AND deleted_at IS NULL',
      whereArgs: [topicId],
    );
    if (rows.isEmpty) return null;
    Future<List<Map<String, Object?>>> related(
      String table,
      String type,
    ) => _db.rawQuery(
      'SELECT e.* FROM $table e JOIN entity_topics et ON et.entity_id=e.id AND et.entity_type=? WHERE et.topic_id=? AND e.deleted_at IS NULL ORDER BY e.created_at DESC',
      [type, topicId],
    );
    final ideaRows = await related('ideas', 'idea');
    final taskRows = await related('tasks', 'task');
    final scheduleRows = await related('schedules', 'schedule');
    return TopicAggregate(
      topic: _topicFromRow(rows.first),
      ideas: await Future.wait(ideaRows.map(_ideaFromRow)),
      tasks: await Future.wait(taskRows.map(_taskFromRow)),
      schedules: await Future.wait(scheduleRows.map(_scheduleFromRow)),
    );
  }

  @override
  Future<Attachment> addIdeaAttachment(
    String ideaId,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    final id = _uuid.v4();
    final digest = sha256.convert(bytes).toString();
    final directory = Directory(p.join(p.dirname(_openedPath), 'attachments'));
    await directory.create(recursive: true);
    final extension = p.extension(fileName).isEmpty
        ? '.png'
        : p.extension(fileName);
    final localPath = p.join(directory.path, '$id$extension');
    await File(localPath).writeAsBytes(bytes, flush: true);
    final now = DateTime.now().toUtc();
    await _db.insert('attachments', {
      'id': id,
      'owner_type': 'idea',
      'owner_id': ideaId,
      'mime_type': mimeType,
      'file_name': fileName,
      'size': bytes.length,
      'hash': digest,
      'local_path': localPath,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
    });
    return Attachment(
      id: id,
      ownerId: ideaId,
      mimeType: mimeType,
      fileName: fileName,
      size: bytes.length,
      hash: digest,
      localPath: localPath,
      createdAt: now,
    );
  }

  @override
  Future<void> removeAttachment(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.update(
      'attachments',
      {'deleted_at': now, 'updated_at': now},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  @override
  Future<String> exportBackup(String destinationPath) async {
    final ideas = await listIdeas();
    final tasks = await listTasks();
    final schedules = await listSchedules();
    final topics = await listTopics();
    final temp = await Directory.systemTemp.createTemp('its-export-');
    try {
      final jsonFile = File(p.join(temp.path, 'data.json'));
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'ideas': ideas
              .map(
                (e) => {
                  'id': e.id,
                  'content': e.content,
                  'status': e.status.dbValue,
                  'topics': e.topics.map((t) => t.id).toList(),
                  'attachments': e.attachments.map((a) => a.fileName).toList(),
                  'createdAt': e.createdAt.toIso8601String(),
                  'updatedAt': e.updatedAt.toIso8601String(),
                },
              )
              .toList(),
          'tasks': tasks
              .map(
                (e) => {
                  'id': e.id,
                  'title': e.title,
                  'description': e.description,
                  'status': e.status.dbValue,
                  'deadline': e.deadline?.toIso8601String(),
                  'topics': e.topics.map((t) => t.id).toList(),
                },
              )
              .toList(),
          'schedules': schedules
              .map(
                (e) => {
                  'id': e.id,
                  'title': e.title,
                  'description': e.description,
                  'date': e.date.toIso8601String(),
                  'startTime': e.startTime,
                  'endTime': e.endTime,
                  'topics': e.topics.map((t) => t.id).toList(),
                },
              )
              .toList(),
          'topics': topics
              .map(
                (e) => {
                  'id': e.id,
                  'name': e.name,
                  'description': e.description,
                },
              )
              .toList(),
        }),
      );
      final encoder = ZipFileEncoder()..create(destinationPath);
      encoder.addFile(File(_openedPath), 'database.sqlite');
      encoder.addFile(jsonFile, 'data.json');
      for (final idea in ideas) {
        for (final attachment in idea.attachments) {
          final file = File(attachment.localPath);
          if (await file.exists()) {
            encoder.addFile(
              file,
              'attachments/${attachment.id}${p.extension(attachment.localPath)}',
            );
          }
        }
      }
      await encoder.close();
      return destinationPath;
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
