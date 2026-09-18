import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopIntegration with TrayListener {
  DesktopIntegration(this.captureRequests);
  final ValueNotifier<int> captureRequests;
  late final HotKey _captureHotKey;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1200, 780),
        minimumSize: Size(900, 620),
        center: true,
        title: '拾光',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    _captureHotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      _captureHotKey,
      keyDownHandler: (_) => showCapture(),
    );
    final iconBytes = await rootBundle.load(
      'windows/runner/resources/app_icon.ico',
    );
    final root = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final icon = File(
      p.join(root, 'com.localfirst', 'its_app', 'tray_icon.ico'),
    );
    await icon.parent.create(recursive: true);
    await icon.writeAsBytes(iconBytes.buffer.asUint8List());
    trayManager.addListener(this);
    await trayManager.setIcon(icon.path);
    await trayManager.setToolTip('拾光 · Ctrl+Shift+Space 快速记录');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'capture', label: '快速记录'),
          MenuItem(key: 'show', label: '显示窗口'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  Future<void> showCapture() async {
    await windowManager.show();
    await windowManager.focus();
    captureRequests.value++;
  }

  @override
  void onTrayIconMouseDown() => showCapture();
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'exit') {
      trayManager.destroy();
      hotKeyManager.unregister(_captureHotKey);
      exit(0);
    } else if (menuItem.key == 'capture') {
      showCapture();
    } else if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.focus();
    }
  }
}
