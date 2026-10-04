import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/idea_history.dart';
import '../domain/models.dart';

class IdeaActivityCalendar extends StatefulWidget {
  const IdeaActivityCalendar({
    super.key,
    required this.ideas,
    this.initialDate,
  });

  final List<Idea> ideas;
  final DateTime? initialDate;

  @override
  State<IdeaActivityCalendar> createState() => _IdeaActivityCalendarState();
}

class _IdeaActivityCalendarState extends State<IdeaActivityCalendar> {
  late DateTime selected = localIdeaDay(widget.initialDate ?? DateTime.now());
  late DateTime month = DateTime(selected.year, selected.month);

  void _changeMonth(int offset) {
    setState(() {
      month = DateTime(month.year, month.month + offset);
      selected = month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = IdeaActivitySummary.fromIdeas(widget.ideas);
    final totals = summary.inMonth(month);
    final selectedCounts = summary.onDay(selected);
    final firstWeekday = month.weekday - 1;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final cellCount = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
    final today = localIdeaDay(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('灵感日历', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    selected = today;
                    month = DateTime(today.year, today.month);
                  }),
                  child: const Text('今天'),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  tooltip: '灵感日历：上个月',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat('yyyy 年 M 月').format(month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: '灵感日历：下个月',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '本月创建 ${totals.created}',
                  style: TextStyle(color: colors.primary),
                ),
                Text(
                  '本月实现 ${totals.implemented}',
                  style: TextStyle(color: colors.tertiary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '日期下方：创建 / 实现',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: const ['一', '二', '三', '四', '五', '六', '日']
                  .map((day) => Expanded(child: Center(child: Text(day))))
                  .toList(),
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent:
                    48 * MediaQuery.textScalerOf(context).scale(14) / 14,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
              ),
              itemCount: cellCount,
              itemBuilder: (context, index) {
                final number = index - firstWeekday + 1;
                if (number < 1 || number > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(month.year, month.month, number);
                final count = summary.onDay(date);
                final isSelected = date == selected;
                final isToday = date == today;
                final description =
                    '${DateFormat('yyyy/MM/dd').format(date)}，创建 ${count.created} 条，实现 ${count.implemented} 条';
                return Semantics(
                  label: description,
                  button: true,
                  selected: isSelected,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: description,
                    child: Material(
                      color: isSelected
                          ? colors.primaryContainer
                          : colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected || isToday
                              ? colors.primary
                              : colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey(
                          'idea-day-${DateFormat('yyyy-MM-dd').format(date)}',
                        ),
                        onTap: () => setState(() => selected = date),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$number',
                                style: TextStyle(
                                  fontWeight: isToday ? FontWeight.bold : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (count.created > 0 || count.implemented > 0)
                                FittedBox(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${count.created}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.primary,
                                        ),
                                      ),
                                      Text(
                                        ' / ',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        '${count.implemented}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.tertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 24),
            Text(
              '${DateFormat('yyyy/MM/dd').format(selected)} · 创建 ${selectedCounts.created} 条 · 实现 ${selectedCounts.implemented} 条',
              key: const ValueKey('idea-calendar-selected-summary'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '按本地日期统计全部灵感，跟随搜索和 Topic 筛选。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (summary.unrecordedImplementations > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${summary.unrecordedImplementations} 条旧记录没有实现时间，不计入实现统计。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
