import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/domain/idea_history.dart';
import 'package:its_app/domain/models.dart';

Idea idea(
  String id,
  DateTime created, {
  DateTime? implemented,
  DateTime? updated,
  IdeaStatus status = IdeaStatus.implemented,
}) => Idea(
  id: id,
  content: id,
  status: status,
  createdAt: created,
  updatedAt: updated ?? implemented ?? created,
  implementedAt: implemented,
);

void main() {
  final older = idea(
    'older',
    DateTime(2026, 9, 1),
    implemented: DateTime(2026, 10, 3),
  );
  final newer = idea(
    'newer',
    DateTime(2026, 9, 30),
    implemented: DateTime(2026, 10, 2),
  );
  final legacy = idea('legacy', DateTime(2026, 9, 10), updated: DateTime(2027));
  final active = idea(
    'active',
    DateTime(2026, 10, 4),
    status: IdeaStatus.newIdea,
  );
  final ideas = [legacy, older, active, newer];

  for (final entry in {
    IdeaHistorySort.implementedNewest: ['older', 'newer', 'legacy'],
    IdeaHistorySort.implementedOldest: ['newer', 'older', 'legacy'],
    IdeaHistorySort.createdNewest: ['newer', 'legacy', 'older'],
    IdeaHistorySort.createdOldest: ['older', 'legacy', 'newer'],
  }.entries) {
    test(
      '${entry.key.name} sorts only history without changing source data',
      () {
        expect(
          sortIdeaHistory(ideas, entry.key).map((item) => item.id),
          entry.value,
        );
        expect(ideas.map((item) => item.id), [
          'legacy',
          'older',
          'active',
          'newer',
        ]);
      },
    );
  }

  test(
    'equal timestamps and unknown times have deterministic tie breaking',
    () {
      final sameDay = DateTime(2026, 10, 2);
      final first = idea('a', sameDay, implemented: sameDay);
      final second = idea('b', sameDay, implemented: sameDay);
      final missingA = idea('missing-a', sameDay);
      final missingB = idea('missing-b', sameDay);
      for (final order in IdeaHistorySort.values) {
        expect(
          sortIdeaHistory([
            second,
            missingB,
            first,
            missingA,
          ], order).map((item) => item.id),
          ['a', 'b', 'missing-a', 'missing-b'],
        );
      }
    },
  );

  test(
    'daily counts include creation of active ideas and real implementations',
    () {
      final summary = IdeaActivitySummary.fromIdeas([
        idea(
          'done',
          DateTime(2026, 10, 2, 9),
          implemented: DateTime(2026, 10, 3, 17),
        ),
        idea('new', DateTime(2026, 10, 2, 14), status: IdeaStatus.newIdea),
        idea(
          'same-day',
          DateTime(2026, 10, 3, 8),
          implemented: DateTime(2026, 10, 3, 16),
        ),
        idea('shelved', DateTime(2026, 10, 3, 10), status: IdeaStatus.shelved),
        idea(
          'legacy',
          DateTime(2026, 10, 3, 11),
          updated: DateTime(2026, 10, 4),
        ),
        idea(
          'reopened',
          DateTime(2026, 10, 3, 12),
          implemented: DateTime(2026, 10, 4),
          status: IdeaStatus.thinking,
        ),
      ]);
      expect(summary.onDay(DateTime(2026, 10, 2, 23)).created, 2);
      expect(summary.onDay(DateTime(2026, 10, 2)).implemented, 0);
      expect(summary.onDay(DateTime(2026, 10, 3)).created, 4);
      expect(summary.onDay(DateTime(2026, 10, 3)).implemented, 2);
      expect(summary.onDay(DateTime(2026, 10, 4)).implemented, 0);
      expect(summary.unrecordedImplementations, 1);
      expect(summary.inMonth(DateTime(2026, 10)).created, 6);
      expect(summary.inMonth(DateTime(2026, 10)).implemented, 2);
    },
  );

  test('UTC events are grouped by local calendar date, not the UTC date', () {
    final time = DateTime.utc(2026, 10, 2, 20, 30);
    final local = time.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final summary = IdeaActivitySummary.fromIdeas([
      idea('utc', time, implemented: time),
    ]);
    expect(summary.days.keys, [day]);
    expect(summary.onDay(day).created, 1);
    expect(summary.onDay(day).implemented, 1);
    expect(localIdeaDay(time).isUtc, isFalse);
  });

  test('month totals separate year boundaries and handle empty months', () {
    final summary = IdeaActivitySummary.fromIdeas([
      idea(
        'year-end',
        DateTime(2025, 12, 31, 23),
        implemented: DateTime(2026, 1, 1, 1),
      ),
      idea('year-start', DateTime(2026, 1, 1, 9), status: IdeaStatus.ready),
    ]);
    expect(summary.inMonth(DateTime(2025, 12)).created, 1);
    expect(summary.inMonth(DateTime(2025, 12)).implemented, 0);
    expect(summary.inMonth(DateTime(2026, 1)).created, 1);
    expect(summary.inMonth(DateTime(2026, 1)).implemented, 1);
    expect(summary.inMonth(DateTime(2026, 12)).created, 0);
    expect(summary.inMonth(DateTime(2026, 12)).implemented, 0);
    expect(IdeaActivitySummary.fromIdeas([]).days, isEmpty);
  });
}
