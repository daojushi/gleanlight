import 'dart:typed_data';

import '../domain/models.dart';

abstract interface class AppRepository {
  Future<void> initialize();
  Future<List<Idea>> listIdeas();
  Future<List<AppTask>> listTasks();
  Future<List<Schedule>> listSchedules();
  Future<List<Topic>> listTopics();
  Future<TopicAggregate?> topicAggregate(String topicId);

  Future<String> saveIdea({
    String? id,
    required String content,
    required IdeaStatus status,
    required List<String> topicIds,
  });
  Future<void> saveTask({
    String? id,
    required String title,
    required String description,
    required TaskStatus status,
    DateTime? deadline,
    required List<String> topicIds,
  });
  Future<void> saveSchedule({
    String? id,
    required String title,
    required String description,
    required DateTime date,
    String? startTime,
    String? endTime,
    required List<String> topicIds,
  });
  Future<void> saveTopic({
    String? id,
    required String name,
    required String description,
  });
  Future<void> softDelete(String entityType, String id);
  Future<Attachment> addIdeaAttachment(
    String ideaId,
    String fileName,
    String mimeType,
    Uint8List bytes,
  );
  Future<void> removeAttachment(String id);
  Future<String> exportBackup(String destinationPath);
}
