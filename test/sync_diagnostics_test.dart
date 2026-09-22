import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/sync/sync_diagnostics.dart';

void main() {
  test(
    'HTTP probe sends requested credentials and reports actual status',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<String?>();
      server.listen((request) async {
        received.complete(request.headers.value('apikey'));
        request.response.statusCode = 401;
        await request.response.close();
      });
      final status = await probeSyncHttp(
        Uri.parse('http://127.0.0.1:${server.port}/auth/v1/health'),
        headers: {'apikey': 'test-only'},
      );
      expect(status, 401);
      expect(await received.future, 'test-only');
    },
  );

  test('HTTP probe does not forward credentials through redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 302;
      request.response.headers.set('location', '/redirected');
      await request.response.close();
    });
    expect(
      await probeSyncHttp(Uri.parse('http://127.0.0.1:${server.port}')),
      302,
    );
    expect(requests, 1);
  });

  test('HTTP probe terminates when server never responds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((_) {});
    await expectLater(
      probeSyncHttp(
        Uri.parse('http://127.0.0.1:${server.port}'),
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
