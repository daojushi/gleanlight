import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../data/sqlite_app_repository.dart';
import '../data/storage_manager.dart';
import '../domain/models.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, this.storageManager);
  AppRepository repository;
  final StorageManager storageManager;
  bool loading = true;
  Object? error;
  List<Idea> ideas = const [];
  List<AppTask> tasks = const [];
  List<Schedule> schedules = const [];
  List<Topic> topics = const [];

  Future<void> initialize() async {
    try {
      await repository.initialize();
      await reload();
    } catch (e) {
      error = e;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    try {
      final values = await Future.wait([
        repository.listIdeas(),
        repository.listTasks(),
        repository.listSchedules(),
        repository.listTopics(),
      ]);
      ideas = values[0] as List<Idea>;
      tasks = values[1] as List<AppTask>;
      schedules = values[2] as List<Schedule>;
      topics = values[3] as List<Topic>;
      error = null;
    } catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> captureIdea(
    String content, {
    List<PendingAttachment> attachments = const [],
  }) async {
    final id = await repository.saveIdea(
      content: content,
      status: IdeaStatus.newIdea,
      topicIds: const [],
    );
    for (final attachment in attachments) {
      await repository.addIdeaAttachment(
        id,
        attachment.fileName,
        attachment.mimeType,
        attachment.bytes,
      );
    }
    await reload();
  }

  Future<String> saveIdea({
    Idea? original,
    required String content,
    required IdeaStatus status,
    required List<String> topicIds,
  }) async {
    final id = await repository.saveIdea(
      id: original?.id,
      content: content,
      status: status,
      topicIds: topicIds,
    );
    await reload();
    return id;
  }

  Future<void> saveTask({
    AppTask? original,
    required String title,
    required String description,
    required TaskStatus status,
    DateTime? deadline,
    required List<String> topicIds,
  }) async {
    await repository.saveTask(
      id: original?.id,
      title: title,
      description: description,
      status: status,
      deadline: deadline,
      topicIds: topicIds,
    );
    await reload();
  }

  Future<void> saveSchedule({
    Schedule? original,
    required String title,
    required String description,
    required DateTime date,
    String? startTime,
    String? endTime,
    required List<String> topicIds,
  }) async {
    await repository.saveSchedule(
      id: original?.id,
      title: title,
      description: description,
      date: date,
      startTime: startTime,
      endTime: endTime,
      topicIds: topicIds,
    );
    await reload();
  }

  Future<void> saveTopic(String name, String description) async {
    await repository.saveTopic(name: name, description: description);
    await reload();
  }

  Future<void> delete(String type, String id) async {
    await repository.softDelete(type, id);
    await reload();
  }

  Future<TopicAggregate?> topicAggregate(String id) =>
      repository.topicAggregate(id);

  Future<void> addAttachment(Idea idea, PendingAttachment attachment) async {
    await repository.addIdeaAttachment(
      idea.id,
      attachment.fileName,
      attachment.mimeType,
      attachment.bytes,
    );
    await reload();
  }

  Future<void> addAttachmentToIdea(
    String ideaId,
    PendingAttachment attachment,
  ) async {
    await repository.addIdeaAttachment(
      ideaId,
      attachment.fileName,
      attachment.mimeType,
      attachment.bytes,
    );
  }

  Future<void> removeAttachment(String id) async {
    await repository.removeAttachment(id);
    await reload();
  }

  Future<String> exportBackup(String path) => repository.exportBackup(path);

  String get storageLocation => storageManager.currentRoot;
  Future<void> moveStorage(String selectedDirectory) async {
    if (repository is! SqliteAppRepository) throw StateError('当前数据源不支持迁移');
    loading = true;
    notifyListeners();
    try {
      repository = await storageManager.move(
        repository as SqliteAppRepository,
        selectedDirectory,
      );
      await reload();
    } catch (error) {
      loading = false;
      notifyListeners();
      rethrow;
    }
  }
}

class PendingAttachment {
  const PendingAttachment(this.fileName, this.mimeType, this.bytes);
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}
