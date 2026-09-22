import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Supabase Auth, REST, Storage and diagnostics share the same platform stack.
/// Android packages embedded Cronet, so ColorOS does not need Play Services.
http.Client createSyncHttpClient() {
  if (Platform.isAndroid) {
    return CronetClient.fromCronetEngine(
      CronetEngine.build(cacheMode: CacheMode.disabled, enableHttp2: true),
      closeEngine: true,
    );
  }
  return IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 15),
  );
}
