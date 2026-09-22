import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Never include raw errors: URLs, headers or response bodies may contain secrets.
String describeSyncError(Object error) {
  if (error is TimeoutException) return '请求超时';
  if (error is HandshakeException) return 'TLS 证书或握手失败';
  if (error is SocketException) {
    if (error.osError?.errorCode == 104 || error.osError?.errorCode == 10054) {
      return '网络连接被重置（${error.osError!.errorCode}），尚不能判断密钥或登录是否有效';
    }
    return 'DNS 或网络连接失败（${error.osError?.errorCode ?? '未知'}）';
  }
  if (error is AuthRetryableFetchException) {
    return '认证服务暂时不可达或网络失败；请稍后重试，当前错误不代表需要重新登录';
  }
  if (error is AuthUnknownException) {
    return describeSyncError(error.originalError);
  }
  if (error is AuthSessionMissingException ||
      error is AuthInvalidJwtException ||
      error is AuthException &&
          const {
            'refresh_token_not_found',
            'refresh_token_already_used',
            'session_not_found',
            'session_expired',
            'bad_jwt',
          }.contains(error.code)) {
    return '登录凭证已失效，请重新登录；本地数据仍保留';
  }
  if (error is AuthException) {
    return '认证请求失败（HTTP ${error.statusCode ?? '未收到响应'}）';
  }
  if (error is http.ClientException) {
    final code = RegExp(r'net::ERR_[A-Z_]+')
        .firstMatch(error.message)
        ?.group(0);
    return '网络请求失败${code == null ? '' : '（$code）'}';
  }
  if (error is PostgrestException) return '数据接口错误（${error.code ?? '未知'}）';
  return '失败（${error.runtimeType}）';
}
