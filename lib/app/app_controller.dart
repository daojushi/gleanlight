import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_repository.dart';
import '../data/sqlite_app_repository.dart';
import '../data/storage_manager.dart';
import '../domain/models.dart';
import '../sync/sync_provider.dart';
import '../sync/sync_conflict.dart';
import '../sync/sync_config.dart';

class AppController extends ChangeNotifier {
  AppController(
    this.repository,
    this.storageManager,
    this.syncProvider,
    this.supabase, {
    this.activeSyncConfig,
    int autoSyncDelaySeconds = 10,
  }) : _autoSyncDelaySeconds = autoSyncDelaySeconds.clamp(1, 3600);
  AppRepository repository;
  final StorageManager storageManager;
  final SyncProvider syncProvider;
  final SupabaseClient? supabase;
  final SyncConfig? activeSyncConfig;
  SyncState syncState = const SyncState(SyncPhase.disabled);
  StreamSubscription<SyncState>? _syncSubscription;
  Timer? _autoSyncTimer;
  int _autoSyncDelaySeconds;
  bool _syncRequestedByController = false;
  bool initializing = true;
  bool loading = true;
  Object? error;
  List<Idea> ideas = const [];
  List<AppTask> tasks = const [];
  List<Schedule> schedules = const [];
  List<Topic> topics = const [];

  Future<void> initialize() async {
    initializing = true;
    loading = true;
    notifyListeners();
    try {
      await repository.initialize();
      syncState = syncProvider.state;
      _syncSubscription = syncProvider.states.listen((value) {
        final completedAutomaticSync =
            syncState.phase == SyncPhase.syncing &&
            value.phase == SyncPhase.idle &&
            !_syncRequestedByController;
        syncState = value;
        notifyListeners();
        if (completedAutomaticSync) unawaited(reload());
      });
      await syncProvider.start();
      if (currentUser != null) {
        await syncOnOpen();
      } else {
        await reload();
      }
      initializing = false;
      notifyListeners();
    } catch (e) {
      error = e;
      initializing = false;
      loading = false;
      notifyListeners();
    }
  }

  User? get currentUser => supabase?.auth.currentUser;
  Future<void> signIn(String email, String password) async {
    final client = supabase;
    if (client == null) throw StateError('请先保存 Supabase 配置并重启应用');
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await syncNow();
  }

  Future<void> signUp(String email, String password) async {
    final client = supabase;
    if (client == null) throw StateError('请先保存 Supabase 配置并重启应用');
    await client.auth.signUp(email: email.trim(), password: password);
    notifyListeners();
  }

  Future<void> signOut() async {
    await supabase?.auth.signOut();
    notifyListeners();
  }

  Future<void> syncNow() async {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _syncRequestedByController = true;
    try {
      await syncProvider.sync();
    } finally {
      _syncRequestedByController = false;
    }
    await reload();
  }

  Future<void> syncOnOpen() async {
    if (currentUser == null) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    loading = true;
    notifyListeners();
    _syncRequestedByController = true;
    try {
      // Let the user reach the local copy even if the cloud is slow. The
      // in-flight sync keeps running and the state listener reloads on success.
      await syncProvider.sync().timeout(const Duration(seconds: 15));
    } catch (_) {
      // Startup/resume must still expose the safe local copy when offline.
    } finally {
      _syncRequestedByController = false;
    }
    await reload();
  }

  int get autoSyncDelaySeconds => _autoSyncDelaySeconds;

  void setAutoSyncDelaySeconds(int seconds) {
    _autoSyncDelaySeconds = seconds.clamp(1, 3600);
    if (_autoSyncTimer?.isActive ?? false) _scheduleAutoSync();
    notifyListeners();
  }

  void _scheduleAutoSync() {
    if (currentUser == null) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(
      Duration(seconds: _autoSyncDelaySeconds),
      _runScheduledSync,
    );
  }

  Future<void> _runScheduledSync() async {
    try {
      await syncNow();
    } catch (_) {
      // The provider exposes the error through syncState; local edits stay safe.
    }
  }

  Future<List<SyncConflict>> syncConflicts() async {
    final repo = repository;
    return repo is SqliteAppRepository ? repo.listSyncConflicts() : const [];
  }

  Future<void> resolveSyncConflict(String id, {required bool useRemote}) async {
    final repo = repository;
    if (repo is! SqliteAppRepository) return;
    await repo.resolveSyncConflict(id, useRemote: useRemote);
    await reload();
    _scheduleAutoSync();
  }

  Future<void> ignoreAllSyncConflicts() async {
    final repo = repository;
    if (repo is! SqliteAppRepository) return;
    await repo.ignoreAllSyncConflicts();
    await reload();
  }

  Future<void> resolveAllSyncConflicts({required bool useRemote}) async {
    final repo = repository;
    if (repo is! SqliteAppRepository) return;
    await repo.resolveAllSyncConflicts(useRemote: useRemote);
    await reload();
    _scheduleAutoSync();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _syncSubscription?.cancel();
    syncProvider.stop();
    super.dispose();
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
    _scheduleAutoSync();
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
    _scheduleAutoSync();
    return id;
  }

  Future<void> updateIdeaStatus(Idea idea, IdeaStatus status) async {
    await repository.saveIdea(
      id: idea.id,
      content: idea.content,
      status: status,
      topicIds: idea.topics.map((topic) => topic.id).toList(),
    );
    await reload();
    _scheduleAutoSync();
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
    _scheduleAutoSync();
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
    _scheduleAutoSync();
  }

  Future<void> saveTopic(String name, String description) async {
    await repository.saveTopic(name: name, description: description);
    await reload();
    _scheduleAutoSync();
  }

  Future<void> delete(String type, String id) async {
    await repository.softDelete(type, id);
    await reload();
    _scheduleAutoSync();
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
    _scheduleAutoSync();
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
    _scheduleAutoSync();
  }

  Future<void> removeAttachment(String id) async {
    await repository.removeAttachment(id);
    await reload();
    _scheduleAutoSync();
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
