import 'models.dart';

enum IdeaHistorySort {
  implementedNewest('实现时间 · 最新在前', '最近实现的在最上方', false, true),
  implementedOldest('实现时间 · 最早在前', '最早实现的在最上方', false, false),
  createdNewest('创建时间 · 最新在前', '最近创建的在最上方', true, true),
  createdOldest('创建时间 · 最早在前', '最早创建的在最上方', true, false);

  const IdeaHistorySort(
    this.label,
    this.description,
    this.byCreation,
    this.newestFirst,
  );

  final String label;
  final String description;
  final bool byCreation;
  final bool newestFirst;
}

List<Idea> sortIdeaHistory(Iterable<Idea> ideas, IdeaHistorySort order) {
  final history = ideas
      .where((idea) => idea.status == IdeaStatus.implemented)
      .toList();
  history.sort((a, b) {
    final aTime = order.byCreation ? a.createdAt : a.implementedAt;
    final bTime = order.byCreation ? b.createdAt : b.implementedAt;
    // Unknown implementation times belong last in either direction. An edit
    // timestamp is not evidence that a legacy idea was implemented that day.
    if (aTime == null && bTime != null) return 1;
    if (aTime != null && bTime == null) return -1;
    if (aTime != null && bTime != null) {
      final comparison = order.newestFirst
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
      if (comparison != 0) return comparison;
    }
    final creationComparison = order.newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt);
    return creationComparison != 0 ? creationComparison : a.id.compareTo(b.id);
  });
  return history;
}

DateTime localIdeaDay(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

class IdeaDayActivity {
  const IdeaDayActivity({this.created = 0, this.implemented = 0});

  final int created;
  final int implemented;
}

class IdeaActivitySummary {
  IdeaActivitySummary.fromIdeas(Iterable<Idea> ideas) {
    final counts = <DateTime, IdeaDayActivity>{};
    var unknown = 0;
    for (final idea in ideas) {
      final createdDay = localIdeaDay(idea.createdAt);
      final createdCounts = counts[createdDay] ?? const IdeaDayActivity();
      counts[createdDay] = IdeaDayActivity(
        created: createdCounts.created + 1,
        implemented: createdCounts.implemented,
      );
      if (idea.status != IdeaStatus.implemented) continue;
      final implementedAt = idea.implementedAt;
      if (implementedAt == null) {
        unknown++;
        continue;
      }
      final implementedDay = localIdeaDay(implementedAt);
      final implementedCounts =
          counts[implementedDay] ?? const IdeaDayActivity();
      counts[implementedDay] = IdeaDayActivity(
        created: implementedCounts.created,
        implemented: implementedCounts.implemented + 1,
      );
    }
    days = Map.unmodifiable(counts);
    unrecordedImplementations = unknown;
  }

  late final Map<DateTime, IdeaDayActivity> days;
  late final int unrecordedImplementations;

  IdeaDayActivity onDay(DateTime day) =>
      days[localIdeaDay(day)] ?? const IdeaDayActivity();

  IdeaDayActivity inMonth(DateTime month) {
    var created = 0;
    var implemented = 0;
    for (final entry in days.entries) {
      if (entry.key.year == month.year && entry.key.month == month.month) {
        created += entry.value.created;
        implemented += entry.value.implemented;
      }
    }
    return IdeaDayActivity(created: created, implemented: implemented);
  }
}
