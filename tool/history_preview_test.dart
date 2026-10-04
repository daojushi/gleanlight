// Render the history page using synthetic data, without opening user storage.
// flutter test tool/history_preview_test.dart --dart-define=HISTORY_PREVIEW_FONT=C:/Windows/Fonts/msyh.ttc
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/app/app_controller.dart';
import 'package:its_app/data/sqlite_app_repository.dart';
import 'package:its_app/data/storage_manager.dart';
import 'package:its_app/domain/models.dart';
import 'package:its_app/sync/sync_provider.dart';
import 'package:its_app/ui/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fontPath = String.fromEnvironment('HISTORY_PREVIEW_FONT');
  const iconFontPath = String.fromEnvironment('HISTORY_PREVIEW_ICON_FONT');
  setUpAll(() async {
    if (fontPath.isNotEmpty) {
      final font = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final family in ['HistoryPreview', 'Georgia']) {
        final loader = FontLoader(family)..addFont(Future.value(font));
        await loader.load();
      }
    }
    if (iconFontPath.isNotEmpty) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
        Future.value(
          ByteData.sublistView(await File(iconFontPath).readAsBytes()),
        ),
      );
      await loader.load();
    }
  });

  for (final entry in {
    'desktop': const Size(1200, 900),
    'phone': const Size(390, 940),
  }.entries) {
    testWidgets('render ${entry.key} history preview', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = entry.value;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.now();
      DateTime date(int day) => DateTime(now.year, now.month, day, 10);
      final controller =
          AppController(
              SqliteAppRepository(databasePath: ':memory:'),
              StorageManager.forTesting(
                File('unused-preview-settings.json'),
                '.',
              ),
              const NoSyncProvider(),
              null,
            )
            ..ideas = [
              Idea(
                id: 'one',
                content: 'unordered_map 和 unordered_set 有什么区别？',
                status: IdeaStatus.implemented,
                createdAt: date(2),
                updatedAt: date(3),
                implementedAt: date(3),
              ),
              Idea(
                id: 'two',
                content: 'gitignore skill',
                status: IdeaStatus.implemented,
                createdAt: date(1),
                updatedAt: date(2),
                implementedAt: date(2),
              ),
              Idea(
                id: 'three',
                content: '本体？知识图谱？',
                status: IdeaStatus.implemented,
                createdAt: date(1),
                updatedAt: date(2),
                implementedAt: date(2),
              ),
              Idea(
                id: 'four',
                content: '训练一个自己声音的 AI',
                status: IdeaStatus.thinking,
                createdAt: date(3),
                updatedAt: date(3),
              ),
            ];
      addTearDown(controller.dispose);
      const boundaryKey = ValueKey('history-preview');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: fontPath.isEmpty ? null : 'HistoryPreview',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff27634d),
              surface: const Color(0xfffffefa),
            ),
            scaffoldBackgroundColor: const Color(0xfff5f4ef),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
            cardTheme: const CardThemeData(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                side: BorderSide(color: Color(0xffdeddd6)),
              ),
            ),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: const Color(0xfff5f4ef),
                child: HistoryIdeasPage(
                  controller: controller,
                  onMessage: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final rendered = await boundary.toImage();
        try {
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = Directory('build/history-preview');
          await directory.create(recursive: true);
          await File('${directory.path}/${entry.key}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          rendered.dispose();
        }
      });
    });
  }
}
