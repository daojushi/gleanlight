enum IdeaStatus { newIdea, thinking, ready, implemented, shelved }

enum TaskStatus { todo, doing, done }

extension IdeaStatusX on IdeaStatus {
  String get dbValue =>
      const ['New', 'Thinking', 'Ready', 'Implemented', 'Shelved'][index];
  String get label => const ['新想法', '思考中', '实践中', '已实现', '搁置'][index];
  static IdeaStatus fromDb(String value) => IdeaStatus.values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () => IdeaStatus.newIdea,
  );
}

extension TaskStatusX on TaskStatus {
  String get dbValue => const ['Todo', 'Doing', 'Done'][index];
  String get label => const ['Todo', 'Doing', 'Done'][index];
  static TaskStatus fromDb(String value) => TaskStatus.values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () => TaskStatus.todo,
  );
}

class Topic {
  const Topic({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.itemCount = 0,
  });
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int itemCount;
}

class Attachment {
  const Attachment({
    required this.id,
    required this.ownerId,
    required this.mimeType,
    required this.fileName,
    required this.size,
    required this.hash,
    required this.localPath,
    required this.createdAt,
  });
  final String id;
  final String ownerId;
  final String mimeType;
  final String fileName;
  final int size;
  final String hash;
  final String localPath;
  final DateTime createdAt;
}

class Idea {
  const Idea({
    required this.id,
    required this.content,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.topics = const [],
    this.attachments = const [],
  });
  final String id;
  final String content;
  final IdeaStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Topic> topics;
  final List<Attachment> attachments;
}

class AppTask {
  const AppTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deadline,
    this.completedAt,
    this.topics = const [],
  });
  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final DateTime? deadline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final List<Topic> topics;
}

class Schedule {
  const Schedule({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.startTime,
    this.endTime,
    this.topics = const [],
  });
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Topic> topics;
}

class TopicAggregate {
  const TopicAggregate({
    required this.topic,
    required this.ideas,
    required this.tasks,
    required this.schedules,
  });
  final Topic topic;
  final List<Idea> ideas;
  final List<AppTask> tasks;
  final List<Schedule> schedules;
}
