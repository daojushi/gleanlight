import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sqlite_app_repository.dart';
import 'sync_provider.dart';
import 'sync_errors.dart';

class SupabaseSyncProvider implements SyncProvider {
  SupabaseSyncProvider(this.repository, this.client, this.deviceId);
  final SqliteAppRepository repository;
  final SupabaseClient client;
  final String deviceId;
  final _states = StreamController<SyncState>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _network;
  StreamSubscription<AuthState>? _auth;
  SyncState _state = const SyncState(SyncPhase.idle);
  Future<void>? _activeSync;
  Future<void>? _attachmentWork;

  @override
  SyncState get state => _state;
  @override
  Stream<SyncState> get states => _states.stream;
  void _set(SyncState value) {
    _state = value;
    _states.add(value);
  }

  @override
  Future<void> start() async {
    _auth = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null &&
          (state.event == AuthChangeEvent.initialSession ||
              state.event == AuthChangeEvent.signedIn)) {
        _syncInBackground();
      }
    });
    _network = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none) &&
          client.auth.currentUser != null) {
        _syncInBackground();
      }
    });
  }

  Future<void> _syncInBackground() async {
    try {
      await sync();
    } catch (_) {
      // The error is published through [states] and can be retried from any
      // page. Event-stream callbacks must not leak unhandled futures.
    }
  }

  @override
  Future<void> sync() {
    final active = _activeSync;
    if (active != null) return active;
    final operation = _performSync();
    _activeSync = operation;
    return operation.whenComplete(() {
      if (identical(_activeSync, operation)) _activeSync = null;
    });
  }

  Future<T> _cloudRequest<T>(String stage, Future<T> Function() request) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      _set(SyncState(SyncPhase.syncing, message: '$stage（$attempt/2）'));
      try {
        return await request().timeout(const Duration(seconds: 20));
      } on TimeoutException {
        if (attempt == 2) {
          throw StateError('$stage超时：两次请求均未在 20 秒内完成；本地数据仍已保留');
        }
      } on SocketException catch (error) {
        if (attempt == 2) throw StateError('$stage失败：$error');
      } on http.ClientException catch (error) {
        if (attempt == 2) {
          throw StateError('$stage失败：${describeSyncError(error)}');
        }
      } catch (error) {
        throw StateError('$stage失败：$error');
      }
    }
    throw StateError('$stage失败');
  }

  Future<void> _performSync() async {
    final user = client.auth.currentUser;
    if (user == null) {
      _set(const SyncState(SyncPhase.idle, message: '请先登录'));
      return;
    }
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      _set(const SyncState(SyncPhase.offline, message: '离线，改动保存在本机'));
      return;
    }
    _set(const SyncState(SyncPhase.syncing, message: '正在同步'));
    try {
      _set(const SyncState(SyncPhase.syncing, message: '正在验证登录凭证'));
      try {
        final session = await client.auth.getSession().timeout(
          const Duration(seconds: 15),
        );
        if (session == null) throw StateError('登录已失效，请重新登录');
      } on TimeoutException {
        throw StateError('登录凭证续期超时，尚未开始下载。请使用设置中的同步诊断检查认证服务');
      } on AuthException catch (error) {
        throw StateError(describeSyncError(error));
      }
      final remote = await _cloudRequest(
        '下载云端记录',
        () => client
            .from('device_snapshots')
            .select('device_id,payload')
            .eq('user_id', user.id)
            .neq('device_id', deviceId),
      );
      var merged = 0;
      for (final item in remote) {
        if (item['device_id'] == deviceId) continue;
        final payload = item['payload'];
        final snapshot = payload is String
            ? jsonDecode(payload) as Map<String, dynamic>
            : (payload as Map).cast<String, dynamic>();
        merged += await repository.mergeSyncSnapshot(
          snapshot,
          sourceDevice: item['device_id'] as String,
        );
      }
      final snapshot = await repository.exportSyncSnapshot();
      await _cloudRequest(
        '上传本机记录',
        () => client.from('device_snapshots').upsert({
          'user_id': user.id,
          'device_id': deviceId,
          'payload': snapshot,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      // Records (including schedules and tasks) must not wait for images.
      // A slow or missing attachment is reported separately after the snapshot
      // has reached the cloud, so it cannot block text-only synchronization.
      var attachmentWarning = false;
      try {
        await _startAttachmentSync(user.id).timeout(const Duration(seconds: 8));
      } catch (_) {
        attachmentWarning = true;
      }
      final now = DateTime.now();
      _set(
        SyncState(
          SyncPhase.idle,
          message: attachmentWarning
              ? '记录已同步，部分附件待下次重试'
              : merged == 0
              ? '已是最新'
              : '已合并 $merged 项',
          lastSyncedAt: now,
        ),
      );
    } catch (error) {
      _set(SyncState(SyncPhase.error, message: error.toString()));
      rethrow;
    }
  }

  Future<void> _syncAttachments(String userId) async {
    final rows = await repository.syncAttachments();
    for (final row in rows) {
      final id = row['id']! as String;
      final extension = row['file_name'].toString().split('.').last;
      final remotePath = '$userId/$id.$extension';
      final local = File(row['local_path']! as String);
      if (await local.exists()) {
        await client.storage
            .from('attachments')
            .uploadBinary(
              remotePath,
              await local.readAsBytes(),
              fileOptions: FileOptions(
                upsert: true,
                contentType: row['mime_type'] as String,
              ),
            );
      } else {
        try {
          final bytes = await client.storage
              .from('attachments')
              .download(remotePath);
          await repository.ensureSyncAttachment(id, Uint8List.fromList(bytes));
        } catch (_) {
          // A missing remote file must not abort record synchronization.
        }
      }
    }
  }

  Future<void> _startAttachmentSync(String userId) {
    final active = _attachmentWork;
    if (active != null) return active;
    late final Future<void> work;
    work = _syncAttachments(userId).whenComplete(() {
      if (identical(_attachmentWork, work)) _attachmentWork = null;
    });
    _attachmentWork = work;
    return work;
  }

  @override
  Future<void> stop() async {
    await _network?.cancel();
    await _auth?.cancel();
    // The UI's attachment deadline does not cancel an in-flight upload. Do
    // not close its database or native engine while it still uses them.
    try {
      await _activeSync;
    } catch (_) {}
    try {
      await _attachmentWork;
    } catch (_) {}
    await _states.close();
  }
}
