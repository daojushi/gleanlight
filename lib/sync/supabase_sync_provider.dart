import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sqlite_app_repository.dart';
import 'sync_provider.dart';

class SupabaseSyncProvider implements SyncProvider {
  SupabaseSyncProvider(this.repository, this.client, this.deviceId);
  final SqliteAppRepository repository;
  final SupabaseClient client;
  final String deviceId;
  final _states = StreamController<SyncState>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _network;
  SyncState _state = const SyncState(SyncPhase.idle);
  Future<void>? _activeSync;

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
    _network = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none) &&
          client.auth.currentUser != null) {
        sync();
      }
    });
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
      final remote = await client
          .from('device_snapshots')
          .select('device_id,payload')
          .eq('user_id', user.id);
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
      await _syncAttachments(user.id);
      final snapshot = await repository.exportSyncSnapshot();
      await client.from('device_snapshots').upsert({
        'user_id': user.id,
        'device_id': deviceId,
        'payload': snapshot,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      final now = DateTime.now();
      _set(
        SyncState(
          SyncPhase.idle,
          message: merged == 0 ? '已是最新' : '已合并 $merged 项',
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

  @override
  Future<void> stop() async {
    await _network?.cancel();
    await _states.close();
  }
}
