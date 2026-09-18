import 'dart:convert';

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.local,
    required this.remote,
    required this.sourceDevice,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> local;
  final Map<String, dynamic> remote;
  final String sourceDevice;
  final DateTime createdAt;

  String get localSummary => _summary(local);
  String get remoteSummary => _summary(remote);

  static String _summary(Map<String, dynamic> value) =>
      (value['content'] ?? value['title'] ?? value['name'] ?? jsonEncode(value))
          .toString();
}
