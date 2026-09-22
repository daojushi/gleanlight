import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_config.dart';
import 'sync_errors.dart';
import 'sync_http_client.dart';

/// A fresh connection bypasses the SDK's session refresh and connection pool.
/// Close it even on timeout so diagnostics cannot leave requests running.
Future<int> probeSyncHttp(
  Uri uri, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = createSyncHttpClient();
  final abort = Completer<void>();
  final operation = (() async {
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll(headers);
    final response = await client.send(request);
    await response.stream.drain<void>();
    return response.statusCode;
  })();
  try {
    return await operation.timeout(timeout);
  } finally {
    abort.complete();
    // Cronet cannot shut its engine down until cancellation has completed.
    try {
      await operation;
    } catch (_) {}
    client.close();
  }
}

Future<String> diagnoseSync(SyncConfig config, SupabaseClient? client) async {
  if (!config.enabled) return '项目地址或密钥未配置，请先保存正确配置并重启。';
  final base = Uri.parse(SyncConfig.normalizeUrl(config.url));
  final lines = <String>[
    '同步诊断 1.3.5 · ${Platform.operatingSystem}',
    '网络组件：${Platform.isAndroid ? '内置 Chromium Cronet' : 'Dart HTTP'}',
    '项目：${base.host}',
  ];
  final health = base.replace(path: '/auth/v1/health');
  Future<bool> step(String label, Future<String> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      final result = await action();
      lines.add('$label：$result（${watch.elapsedMilliseconds} ms）');
      return true;
    } catch (error) {
      lines.add('$label：${describeSyncError(error)}');
      return false;
    }
  }

  await step('APP 到网关（不带密钥）', () async {
    final status = await probeSyncHttp(health);
    return 'HTTP $status${status == 401 ? '，网关可达，符合预期' : ''}';
  });
  await step('项目密钥与认证服务', () async {
    final status = await probeSyncHttp(
      health,
      headers: {'apikey': config.anonKey},
    );
    return 'HTTP $status${status == 200 ? '，通过' : '，服务未通过健康检查'}';
  });
  if (client == null) {
    lines.add('APP 未加载云端配置，请重启后再诊断。');
    return lines.join('\n\n');
  }
  Session? session;
  final sessionOk = await step('登录凭证恢复/续期', () async {
    session = await client.auth.getSession().timeout(
      const Duration(seconds: 10),
    );
    return session == null ? '未登录' : '通过';
  });
  if (sessionOk && session != null) {
    final current = session!;
    final query = base.replace(
      path: '/rest/v1/device_snapshots',
      queryParameters: {
        'select': 'device_id',
        'user_id': 'eq.${current.user.id}',
        'limit': '1',
      },
    );
    await step('直接查询数据接口（不下载正文）', () async {
      final status = await probeSyncHttp(
        query,
        headers: {
          'apikey': config.anonKey,
          'Authorization': 'Bearer ${current.accessToken}',
        },
      );
      return 'HTTP $status${status == 200 ? '，通过' : '，请求失败'}';
    });
    await step('SDK 查询数据接口（不下载正文）', () async {
      await client
          .from('device_snapshots')
          .select('device_id')
          .eq('user_id', current.user.id)
          .limit(1)
          .timeout(const Duration(seconds: 10));
      return '通过';
    });
  }
  lines.add('诊断仅查询状态，不修改云端记录；结果不包含密钥、登录令牌或内容。');
  return lines.join('\n\n');
}
