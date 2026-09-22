import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:its_app/sync/sync_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('connection reset is not mislabeled as invalid login or DNS', () {
    final message = describeSyncError(
      const SocketException('reset', osError: OSError('reset', 104)),
    );
    expect(message, contains('连接被重置'));
    expect(message, isNot(contains('DNS')));
    final auth = describeSyncError(
      AuthRetryableFetchException(message: 'private-token'),
    );
    expect(auth, contains('不代表需要重新登录'));
    expect(auth, isNot(contains('private-token')));
  });

  test('confirmed invalid refresh token asks for login', () {
    expect(
      describeSyncError(
        const AuthApiException(
          'invalid',
          code: 'refresh_token_not_found',
          statusCode: '400',
        ),
      ),
      contains('登录凭证已失效'),
    );
  });

  test('native network errors only expose safe error code', () {
    final message = describeSyncError(
      http.ClientException(
        'net::ERR_CONNECTION_RESET private-token',
        Uri.parse('https://example.test?secret=hidden'),
      ),
    );
    expect(message, contains('net::ERR_CONNECTION_RESET'));
    expect(message, isNot(contains('private-token')));
    expect(message, isNot(contains('hidden')));
  });
}
