import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/app/app_controller.dart';
import 'package:its_app/data/sqlite_app_repository.dart';
import 'package:its_app/data/storage_manager.dart';
import 'package:its_app/domain/idea_history.dart';
import 'package:its_app/domain/models.dart';
import 'package:its_app/sync/sync_provider.dart';
import 'package:its_app/ui/app_shell.dart';
import 'package:its_app/ui/idea_activity_calendar.dart';

Idea idea(
  String id,
  DateTime created, {
  DateTime? implemented,
  IdeaStatus status = IdeaStatus.implemented,
  List<Topic> topics = const [],
}) => Idea(
  id: id,
  content: id,
  status: status,
  createdAt: created,
  updatedAt: implemented ?? created,
  implementedAt: implemented,
  topics: topics,
);

AppController controllerWith(
  List<Idea> ideas, {
  List<Topic> topics = const [],
}) =>
    AppController(
        SqliteAppRepository(databasePath: ':memory:'),
        StorageManager.forTesting(File('unused-test-settings.json'), '.'),
        const NoSyncProvider(),
        null,
      )
      ..ideas = ideas
      ..topics = topics;

Future<void> showHistory(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HistoryIdeasPage(controller: controller, onMessage: (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Iterable<String> displayedIds(WidgetTester tester) => tester
    .widgetList<EntityCard>(find.byType(EntityCard))
    .map((card) => card.title);

Future<void> chooseSort(WidgetTester tester, IdeaHistorySort order) async {
  await tester.tap(find.byKey(const ValueKey('history-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(order.label).last);
  await tester.pumpAndSettle();
}

void setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('history switches among all four date sorting options', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final controller = controllerWith([
      idea('older', DateTime(2026, 9, 1), implemented: DateTime(2026, 10, 3)),
      idea('newer', DateTime(2026, 9, 30), implemented: DateTime(2026, 10, 2)),
      idea('legacy', DateTime(2026, 9, 10)),
      idea('active', DateTime(2026, 10, 4), status: IdeaStatus.newIdea),
    ]);
    addTearDown(controller.dispose);
    await showHistory(tester, controller);
    expect(displayedIds(tester), ['older', 'newer', 'legacy']);
    for (final entry in {
      IdeaHistorySort.createdNewest: ['newer', 'legacy', 'older'],
      IdeaHistorySort.createdOldest: ['older', 'legacy', 'newer'],
      IdeaHistorySort.implementedOldest: ['newer', 'older', 'legacy'],
      IdeaHistorySort.implementedNewest: ['older', 'newer', 'legacy'],
    }.entries) {
      await chooseSort(tester, entry.key);
      expect(displayedIds(tester), entry.value);
      expect(find.text('3 条已实现想法 · ${entry.key.description}'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar and history both follow search and Topic filters', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final today = DateTime.now();
    final topic = Topic(
      id: 'study',
      name: '学习',
      description: '',
      createdAt: today,
      updatedAt: today,
    );
    final controller = controllerWith(
      [
        idea('匹配历史', today, implemented: today, topics: [topic]),
        idea('匹配未实现', today, status: IdeaStatus.thinking, topics: [topic]),
        idea('其他历史', today, implemented: today),
      ],
      topics: [topic],
    );
    addTearDown(controller.dispose);
    await showHistory(tester, controller);
    expect(find.text('本月创建 3'), findsOneWidget);
    expect(find.text('本月实现 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '匹配');
    await tester.pumpAndSettle();
    expect(displayedIds(tester), ['匹配历史']);
    expect(find.text('本月创建 2'), findsOneWidget);
    expect(find.text('本月实现 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习').last);
    await tester.pumpAndSettle();
    expect(displayedIds(tester), ['匹配历史']);
    expect(find.text('本月创建 2'), findsOneWidget);
    expect(find.text('本月实现 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no-match state and calendar collapse keep sorting usable', (
    tester,
  ) async {
    final controller = controllerWith([
      idea('test', DateTime.now(), implemented: DateTime.now()),
    ]);
    addTearDown(controller.dispose);
    await showHistory(tester, controller);
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的历史灵感'), findsOneWidget);
    expect(find.text('本月创建 0'), findsOneWidget);
    await tester.tap(find.text('收起日历'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeaActivityCalendar), findsNothing);
    await chooseSort(tester, IdeaHistorySort.createdOldest);
    await tester.tap(find.text('显示日历'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeaActivityCalendar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar selects days, switches across years, and returns to today',
    (tester) async {
      setViewport(tester, const Size(420, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: IdeaActivityCalendar(
                initialDate: DateTime(2026, 1, 1),
                ideas: [
                  idea(
                    'new-year',
                    DateTime(2025, 12, 31),
                    implemented: DateTime(2026, 1, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('idea-day-2026-01-02')));
      await tester.pumpAndSettle();
      expect(find.text('2026/01/02 · 创建 0 条 · 实现 1 条'), findsOneWidget);
      await tester.tap(find.byTooltip('灵感日历：上个月'));
      await tester.pumpAndSettle();
      expect(find.text('2025 年 12 月'), findsOneWidget);
      expect(find.text('本月创建 1'), findsOneWidget);
      expect(find.text('本月实现 0'), findsOneWidget);
      await tester.tap(find.byTooltip('灵感日历：下个月'));
      await tester.pumpAndSettle();
      expect(find.text('2026 年 1 月'), findsOneWidget);
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      expect(find.text('${now.year} 年 ${now.month} 月'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leap February includes the 29th and counts refresh with new data',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 336,
                child: IdeaActivityCalendar(initialDate: null, ideas: []),
              ),
            ),
          ),
        ),
      );
      final leapIdea = idea(
        'leap',
        DateTime(2028, 2, 29),
        implemented: DateTime(2028, 2, 29),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 336,
                child: IdeaActivityCalendar(
                  key: const ValueKey('leap-calendar'),
                  initialDate: DateTime(2028, 2, 1),
                  ideas: [leapIdea],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('idea-day-2028-02-29')), findsOneWidget);
      expect(find.byKey(const ValueKey('idea-day-2028-02-30')), findsNothing);
      expect(find.text('本月创建 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('idea-day-2028-02-29')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 336,
                child: IdeaActivityCalendar(
                  key: const ValueKey('leap-calendar'),
                  initialDate: DateTime(2028, 2, 1),
                  ideas: [
                    leapIdea,
                    idea(
                      'second',
                      DateTime(2028, 2, 29),
                      status: IdeaStatus.newIdea,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2028/02/29 · 创建 2 条 · 实现 1 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets('history fits a 360px phone at text scale $scale', (
      tester,
    ) async {
      setViewport(tester, const Size(360, 900));
      final today = DateTime.now();
      final controller = controllerWith([
        idea('手机上的灵感', today, implemented: today),
      ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: HistoryIdeasPage(controller: controller, onMessage: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IdeaActivityCalendar), findsOneWidget);
      expect(find.byKey(const ValueKey('history-sort')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await chooseSort(tester, IdeaHistorySort.createdNewest);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('收起日历'));
      await tester.pumpAndSettle();
      expect(find.byType(IdeaActivityCalendar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
