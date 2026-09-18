import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidShareIntegration {
  AndroidShareIntegration(this.captureRequest);
  final ValueNotifier<String?> captureRequest;
  static const _channel = MethodChannel('com.localfirst.its_app/share');

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        captureRequest.value = call.arguments as String?;
      }
    });
    final initial = await _channel.invokeMethod<String>('getInitialSharedText');
    if (initial != null && initial.trim().isNotEmpty) {
      captureRequest.value = initial;
    }
  }
}
