import 'package:flutter/foundation.dart';

enum SyncPhase { disabled, idle, syncing, offline, error }

@immutable
class SyncState {
  const SyncState(this.phase, {this.message, this.lastSyncedAt});
  final SyncPhase phase;
  final String? message;
  final DateTime? lastSyncedAt;
}

abstract interface class SyncProvider {
  SyncState get state;
  Stream<SyncState> get states;
  Future<void> start();
  Future<void> sync();
  Future<void> stop();
}

class NoSyncProvider implements SyncProvider {
  const NoSyncProvider();
  @override
  SyncState get state => const SyncState(SyncPhase.disabled, message: '未配置云同步');
  @override
  Stream<SyncState> get states => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> sync() async {}
  @override
  Future<void> stop() async {}
}
