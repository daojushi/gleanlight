import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';

import '../app/app_controller.dart';
import '../domain/models.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.captureRequests,
  });
  final AppController controller;
  final ValueNotifier<int> captureRequests;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    widget.captureRequests.addListener(_openCapture);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    widget.captureRequests.removeListener(_openCapture);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _openCapture() {
    if (mounted) setState(() => index = 0);
  }

  Future<void> _export() async {
    final directory = await FilePicker.getDirectoryPath(dialogTitle: '选择备份目录');
    if (directory == null) return;
    final path =
        '$directory\\its-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.zip';
    try {
      final output = await c.exportBackup(
        path.toLowerCase().endsWith('.zip') ? path : '$path.zip',
      );
      message('备份已导出：$output');
    } catch (e) {
      message(e);
    }
  }

  void message(Object value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value.toString().replaceFirst('Invalid argument(s): ', ''),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (c.error != null && !c.loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text('数据库启动失败：${c.error}'),
              const SizedBox(height: 12),
              FilledButton(onPressed: c.initialize, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 220,
            color: const Color(0xff1f3029),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 28, 16, 26),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(0xffdbeadd),
                        foregroundColor: Color(0xff204a39),
                        child: Text(
                          '拾',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '拾光',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'CAPTURE & PLAN',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ...List.generate(
                  _nav.length,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ListTile(
                      selected: index == i,
                      selectedTileColor: const Color(0xff344b40),
                      selectedColor: Colors.white,
                      textColor: const Color(0xffb8c4bd),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      leading: Icon(_nav[i].$2),
                      title: Text(_nav[i].$1),
                      onTap: () => setState(() => index = i),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListTile(
                    textColor: Colors.white60,
                    iconColor: Colors.white60,
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('导出备份'),
                    onTap: _export,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 9, color: Color(0xff7cc596)),
                      SizedBox(width: 9),
                      Text(
                        '本地存储 · 离线可用',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: c.loading
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: index,
                    children: [
                      CapturePage(controller: c, onMessage: message),
                      IdeasPage(controller: c, onMessage: message),
                      TasksPage(controller: c, onMessage: message),
                      SchedulesPage(controller: c, onMessage: message),
                      TopicsPage(controller: c, onMessage: message),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

const _nav = [
  ('记录', Icons.add_rounded),
  ('灵感', Icons.auto_awesome_outlined),
  ('Todo', Icons.check_rounded),
  ('日程', Icons.calendar_today_outlined),
  ('Topic', Icons.tag_rounded),
];

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });
  final String kicker, title, subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(64, 44, 64, 60),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kicker,
                        style: const TextStyle(
                          color: Color(0xff27634d),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontFamily: 'Georgia',
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    ),
  );
}

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.controller,
    required this.onMessage,
  });
  final AppController controller;
  final void Function(Object) onMessage;
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final text = TextEditingController();
  bool saving = false;
  bool preview = false;
  final attachments = <PendingAttachment>[];
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (text.text.trim().isEmpty) {
      widget.onMessage('先写下一点内容吧');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.controller.captureIdea(text.text, attachments: attachments);
      text.clear();
      attachments.clear();
      widget.onMessage('Idea 已保存');
    } catch (e) {
      widget.onMessage(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickImages() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    for (final file in result) {
      final bytes = await file.readAsBytes();
      attachments.add(PendingAttachment(file.name, _mime(file.name), bytes));
    }
    if (mounted) setState(() {});
  }

  Future<void> pasteImage() async {
    final bytes = await Pasteboard.image;
    if (bytes == null) {
      widget.onMessage('剪贴板中没有图片');
      return;
    }
    attachments.add(
      PendingAttachment(
        'clipboard-${DateTime.now().millisecondsSinceEpoch}.png',
        'image/png',
        bytes,
      ),
    );
    setState(() {});
  }

  Future<void> addDropped(List<DropItem> files) async {
    for (final file in files) {
      if (_isImage(file.name)) {
        attachments.add(
          PendingAttachment(
            file.name,
            _mime(file.name),
            await file.readAsBytes(),
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    kicker: 'QUICK CAPTURE',
    title: '刚刚想到了什么？',
    subtitle: '先记下来，整理可以留给以后。',
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: DropTarget(
        onDragDone: (detail) => addDropped(detail.files),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                if (preview)
                  SizedBox(
                    height: 260,
                    child: Markdown(
                      data: text.text.isEmpty ? '*暂无内容*' : text.text,
                    ),
                  )
                else
                  Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.enter, control: true):
                          ActivateIntent(),
                    },
                    child: Actions(
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (_) {
                            save();
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        controller: text,
                        autofocus: true,
                        minLines: 8,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: '写下你的想法……\n\n支持多段文字和换行。',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                if (attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: attachments
                          .asMap()
                          .entries
                          .map(
                            (entry) => Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    entry.value.bytes,
                                    width: 90,
                                    height: 70,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(
                                      () => attachments.removeAt(entry.key),
                                    ),
                                    icon: const Icon(Icons.close, size: 14),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                const Divider(height: 32),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: pickImages,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('添加图片'),
                    ),
                    TextButton.icon(
                      onPressed: pasteImage,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴截图'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => preview = !preview),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(preview ? '继续编辑' : 'Markdown 预览'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: saving ? null : save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(saving ? '保存中…' : '保存 Idea'),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '也可以把图片直接拖到这里 · Ctrl+Shift+Space 全局唤起',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

bool _isImage(String name) => [
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
].any((e) => name.toLowerCase().endsWith(e));
String _mime(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  return 'image/png';
}

class IdeasPage extends StatelessWidget {
  const IdeasPage({
    super.key,
    required this.controller,
    required this.onMessage,
  });
  final AppController controller;
  final void Function(Object) onMessage;
  @override
  Widget build(BuildContext context) => PageFrame(
    kicker: 'IDEAS',
    title: '灵感',
    subtitle: '${controller.ideas.length} 条想法',
    action: FilledButton.icon(
      onPressed: () => showIdeaDialog(context, controller, null, onMessage),
      icon: const Icon(Icons.add),
      label: const Text('新建 Idea'),
    ),
    child: SearchFilter(
      topics: controller.topics,
      statuses: IdeaStatus.values.map((e) => e.label).toList(),
      builder: (query, topic, status) {
        final items = controller.ideas
            .where(
              (i) =>
                  (query.isEmpty || i.content.toLowerCase().contains(query)) &&
                  (topic == null || i.topics.any((t) => t.id == topic)) &&
                  (status == null || i.status.label == status),
            )
            .toList();
        return items.isEmpty
            ? const EmptyCard(title: '没有匹配的灵感', subtitle: '尝试调整搜索或筛选条件。')
            : Column(
                children: items
                    .map(
                      (idea) => EntityCard(
                        title: idea.content,
                        markdown: true,
                        attachments: idea.attachments,
                        status: idea.status.label,
                        topics: idea.topics,
                        trailing:
                            '创建于 ${DateFormat('MM/dd HH:mm').format(idea.createdAt.toLocal())}',
                        onEdit: () => showIdeaDialog(
                          context,
                          controller,
                          idea,
                          onMessage,
                        ),
                        onDelete: () => confirmDelete(
                          context,
                          controller,
                          'idea',
                          idea.id,
                          onMessage,
                        ),
                      ),
                    )
                    .toList(),
              );
      },
    ),
  );
}

class TasksPage extends StatelessWidget {
  const TasksPage({
    super.key,
    required this.controller,
    required this.onMessage,
  });
  final AppController controller;
  final void Function(Object) onMessage;
  @override
  Widget build(BuildContext context) {
    final active = controller.tasks
        .where((e) => e.status != TaskStatus.done)
        .length;
    return PageFrame(
      kicker: 'TODO',
      title: '待办事项',
      subtitle: '$active 项未完成',
      action: FilledButton.icon(
        onPressed: () => showTaskDialog(context, controller, null, onMessage),
        icon: const Icon(Icons.add),
        label: const Text('新建 Task'),
      ),
      child: SearchFilter(
        topics: controller.topics,
        statuses: TaskStatus.values.map((e) => e.label).toList(),
        builder: (query, topic, status) {
          final items = controller.tasks
              .where(
                (t) =>
                    (query.isEmpty ||
                        ('${t.title} ${t.description}').toLowerCase().contains(
                          query,
                        )) &&
                    (topic == null || t.topics.any((x) => x.id == topic)) &&
                    (status == null || t.status.label == status),
              )
              .toList();
          return items.isEmpty
              ? const EmptyCard(title: '没有匹配的任务', subtitle: '尝试调整搜索或筛选条件。')
              : Column(
                  children: items
                      .map(
                        (task) => EntityCard(
                          title: task.title,
                          description: task.description,
                          status: task.status.label,
                          topics: task.topics,
                          prefix: Checkbox(
                            value: task.status == TaskStatus.done,
                            onChanged: (_) async {
                              try {
                                await controller.saveTask(
                                  original: task,
                                  title: task.title,
                                  description: task.description,
                                  status: task.status == TaskStatus.done
                                      ? TaskStatus.todo
                                      : TaskStatus.done,
                                  deadline: task.deadline,
                                  topicIds: task.topics
                                      .map((e) => e.id)
                                      .toList(),
                                );
                              } catch (e) {
                                onMessage(e);
                              }
                            },
                          ),
                          trailing: task.deadline == null
                              ? 'No Deadline'
                              : 'DDL ${DateFormat('yyyy-MM-dd').format(task.deadline!)}',
                          done: task.status == TaskStatus.done,
                          onEdit: () => showTaskDialog(
                            context,
                            controller,
                            task,
                            onMessage,
                          ),
                          onDelete: () => confirmDelete(
                            context,
                            controller,
                            'task',
                            task.id,
                            onMessage,
                          ),
                        ),
                      )
                      .toList(),
                );
        },
      ),
    );
  }
}

class SchedulesPage extends StatelessWidget {
  const SchedulesPage({
    super.key,
    required this.controller,
    required this.onMessage,
  });
  final AppController controller;
  final void Function(Object) onMessage;
  @override
  Widget build(BuildContext context) {
    final day = DateTime.now(), today = DateTime(day.year, day.month, day.day);
    final future = controller.schedules
        .where((s) => !s.date.isBefore(today))
        .toList();
    return PageFrame(
      kicker: 'SCHEDULE',
      title: '日程',
      subtitle: '今日与未来共 ${future.length} 项',
      action: FilledButton.icon(
        onPressed: () =>
            showScheduleDialog(context, controller, null, onMessage),
        icon: const Icon(Icons.add),
        label: const Text('新建 Schedule'),
      ),
      child: SearchFilter(
        topics: controller.topics,
        statuses: const ['今日', '未来', '全部'],
        builder: (query, topic, status) {
          final items = controller.schedules
              .where(
                (s) =>
                    (status == '全部' || status == null
                        ? !s.date.isBefore(today)
                        : status == '今日'
                        ? DateUtils.isSameDay(s.date, today)
                        : s.date.isAfter(today)) &&
                    (query.isEmpty ||
                        ('${s.title} ${s.description}').toLowerCase().contains(
                          query,
                        )) &&
                    (topic == null || s.topics.any((x) => x.id == topic)),
              )
              .toList();
          return items.isEmpty
              ? const EmptyCard(title: '没有匹配的日程', subtitle: '尝试调整日期、搜索或 Topic。')
              : Column(
                  children: items
                      .map(
                        (s) => EntityCard(
                          title: s.title,
                          description: s.description,
                          status: s.startTime == null
                              ? '全天'
                              : '${s.startTime}${s.endTime == null ? '' : ' – ${s.endTime}'}',
                          topics: s.topics,
                          trailing:
                              '${s.date == today ? '今天 · ' : ''}${DateFormat('yyyy-MM-dd').format(s.date)}',
                          onEdit: () => showScheduleDialog(
                            context,
                            controller,
                            s,
                            onMessage,
                          ),
                          onDelete: () => confirmDelete(
                            context,
                            controller,
                            'schedule',
                            s.id,
                            onMessage,
                          ),
                        ),
                      )
                      .toList(),
                );
        },
      ),
    );
  }
}

class TopicsPage extends StatefulWidget {
  const TopicsPage({
    super.key,
    required this.controller,
    required this.onMessage,
  });
  final AppController controller;
  final void Function(Object) onMessage;
  @override
  State<TopicsPage> createState() => _TopicsPageState();
}

class _TopicsPageState extends State<TopicsPage> {
  TopicAggregate? selected;
  Future<void> select(String id) async {
    selected = await widget.controller.topicAggregate(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    kicker: 'TOPICS',
    title: '主题',
    subtitle: '跨越灵感、任务与日程的聚合视图',
    action: FilledButton.icon(
      onPressed: () =>
          showTopicDialog(context, widget.controller, widget.onMessage),
      icon: const Icon(Icons.add),
      label: const Text('新建 Topic'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.controller.topics.isEmpty)
          const EmptyCard(title: '还没有 Topic', subtitle: '创建主题，把相关内容聚在一起。')
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.controller.topics
                .map(
                  (t) => SizedBox(
                    width: 245,
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => select(t.id),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '# ${t.name}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                t.description.isEmpty ? '暂无描述' : t.description,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 14),
                              Chip(label: Text('${t.itemCount} 项内容')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        if (selected != null) ...[
          const SizedBox(height: 32),
          Text(
            '# ${selected!.topic.name}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            selected!.topic.description,
            style: const TextStyle(color: Colors.black54),
          ),
          AggregateSection(
            title: 'Ideas',
            items: selected!.ideas.map((e) => e.content).toList(),
          ),
          AggregateSection(
            title: 'Tasks',
            items: selected!.tasks.map((e) => e.title).toList(),
          ),
          AggregateSection(
            title: 'Schedules',
            items: selected!.schedules.map((e) => e.title).toList(),
          ),
        ],
      ],
    ),
  );
}

class AggregateSection extends StatelessWidget {
  const AggregateSection({super.key, required this.title, required this.items});
  final String title;
  final List<String> items;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title · ${items.length}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Divider(),
        if (items.isEmpty)
          const Text('暂无内容', style: TextStyle(color: Colors.black45))
        else
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(e),
            ),
          ),
      ],
    ),
  );
}

class SearchFilter extends StatefulWidget {
  const SearchFilter({
    super.key,
    required this.topics,
    required this.statuses,
    required this.builder,
  });
  final List<Topic> topics;
  final List<String> statuses;
  final Widget Function(String, String?, String?) builder;
  @override
  State<SearchFilter> createState() => _SearchFilterState();
}

class _SearchFilterState extends State<SearchFilter> {
  String query = '';
  String? topic, status;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String?>(
            value: status,
            hint: const Text('状态/日期'),
            items: [
              const DropdownMenuItem(value: null, child: Text('全部状态')),
              ...widget.statuses.map(
                (s) => DropdownMenuItem(value: s, child: Text(s)),
              ),
            ],
            onChanged: (v) => setState(() => status = v),
          ),
          const SizedBox(width: 10),
          DropdownButton<String?>(
            value: topic,
            hint: const Text('Topic'),
            items: [
              const DropdownMenuItem(value: null, child: Text('全部 Topic')),
              ...widget.topics.map(
                (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
              ),
            ],
            onChanged: (v) => setState(() => topic = v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      widget.builder(query, topic, status),
    ],
  );
}

class EntityCard extends StatelessWidget {
  const EntityCard({
    super.key,
    required this.title,
    required this.status,
    required this.topics,
    required this.trailing,
    required this.onEdit,
    required this.onDelete,
    this.description = '',
    this.prefix,
    this.done = false,
    this.markdown = false,
    this.attachments = const [],
  });
  final String title, description, status, trailing;
  final List<Topic> topics;
  final Widget? prefix;
  final bool done;
  final bool markdown;
  final List<Attachment> attachments;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (prefix != null) ...[prefix!, const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (markdown)
                    MarkdownBody(data: title)
                  else
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? Colors.black45 : null,
                      ),
                    ),
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: attachments
                          .map(
                            (a) => Tooltip(
                              message: a.fileName,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(a.localPath),
                                  width: 110,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      const SizedBox(
                                        width: 110,
                                        height: 80,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(status),
                        visualDensity: VisualDensity.compact,
                      ),
                      ...topics.map(
                        (t) => Chip(
                          label: Text('# ${t.name}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      Text(
                        trailing,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: '删除',
              color: Colors.red.shade400,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(58),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ),
  );
}

Future<void> confirmDelete(
  BuildContext context,
  AppController c,
  String type,
  String id,
  void Function(Object) message,
) async {
  final ok =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除？'),
          content: const Text('数据会以 soft delete 方式保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
  if (ok) {
    try {
      await c.delete(type, id);
      message('已删除');
    } catch (e) {
      message(e);
    }
  }
}

class TopicPicker extends StatefulWidget {
  const TopicPicker({super.key, required this.topics, required this.selected});
  final List<Topic> topics;
  final Set<String> selected;
  @override
  State<TopicPicker> createState() => _TopicPickerState();
}

class _TopicPickerState extends State<TopicPicker> {
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 6,
    children: widget.topics
        .map(
          (t) => FilterChip(
            label: Text('# ${t.name}'),
            selected: widget.selected.contains(t.id),
            onSelected: (v) => setState(
              () =>
                  v ? widget.selected.add(t.id) : widget.selected.remove(t.id),
            ),
          ),
        )
        .toList(),
  );
}

Future<void> showIdeaDialog(
  BuildContext context,
  AppController c,
  Idea? idea,
  void Function(Object) message,
) async {
  final content = TextEditingController(text: idea?.content);
  var status = idea?.status ?? IdeaStatus.newIdea;
  final selected = idea?.topics.map((e) => e.id).toSet() ?? <String>{};
  final pending = <PendingAttachment>[];
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(idea == null ? '新建 Idea' : '编辑 Idea'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: content,
                  minLines: 6,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: '内容'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: IdeaStatus.values
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) => set(() => status = v!),
                ),
                const SizedBox(height: 14),
                TopicPicker(topics: c.topics, selected: selected),
                const SizedBox(height: 14),
                if (idea?.attachments.isNotEmpty == true)
                  Wrap(
                    spacing: 8,
                    children: idea!.attachments
                        .map(
                          (a) => InputChip(
                            label: Text(a.fileName),
                            onDeleted: () async {
                              await c.removeAttachment(a.id);
                              if (ctx.mounted) Navigator.pop(ctx);
                              message('附件已移除，请重新打开编辑');
                            },
                          ),
                        )
                        .toList(),
                  ),
                if (pending.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: pending
                        .map((a) => Chip(label: Text(a.fileName)))
                        .toList(),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.image,
                        );
                        for (final f in result) {
                          final bytes = await f.readAsBytes();
                          pending.add(
                            PendingAttachment(f.name, _mime(f.name), bytes),
                          );
                        }
                        set(() {});
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('添加图片'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final bytes = await Pasteboard.image;
                        if (bytes != null) {
                          pending.add(
                            PendingAttachment(
                              'clipboard-${DateTime.now().millisecondsSinceEpoch}.png',
                              'image/png',
                              bytes,
                            ),
                          );
                          set(() {});
                        } else {
                          message('剪贴板中没有图片');
                        }
                      },
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴截图'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final id = await c.saveIdea(
                  original: idea,
                  content: content.text,
                  status: status,
                  topicIds: selected.toList(),
                );
                for (final attachment in pending) {
                  await c.addAttachmentToIdea(id, attachment);
                }
                if (pending.isNotEmpty) await c.reload();
                if (ctx.mounted) Navigator.pop(ctx);
                message('已保存');
              } catch (e) {
                message(e);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  content.dispose();
}

Future<void> showTaskDialog(
  BuildContext context,
  AppController c,
  AppTask? task,
  void Function(Object) message,
) async {
  final title = TextEditingController(text: task?.title),
      desc = TextEditingController(text: task?.description);
  var status = task?.status ?? TaskStatus.todo;
  DateTime? deadline = task?.deadline;
  final selected = task?.topics.map((e) => e.id).toSet() ?? <String>{};
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(task == null ? '新建 Task' : '编辑 Task'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: desc,
                  minLines: 3,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: '描述'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: TaskStatus.values
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) => set(() => status = v!),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        deadline == null
                            ? 'DDL：未设置'
                            : 'DDL：${DateFormat('yyyy-MM-dd').format(deadline!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: deadline ?? DateTime.now(),
                        );
                        if (d != null) set(() => deadline = d);
                      },
                      child: const Text('选择日期'),
                    ),
                    if (deadline != null)
                      IconButton(
                        onPressed: () => set(() => deadline = null),
                        icon: const Icon(Icons.clear),
                      ),
                  ],
                ),
                TopicPicker(topics: c.topics, selected: selected),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await c.saveTask(
                  original: task,
                  title: title.text,
                  description: desc.text,
                  status: status,
                  deadline: deadline,
                  topicIds: selected.toList(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                message('已保存');
              } catch (e) {
                message(e);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  desc.dispose();
}

Future<void> showScheduleDialog(
  BuildContext context,
  AppController c,
  Schedule? item,
  void Function(Object) message,
) async {
  final title = TextEditingController(text: item?.title),
      desc = TextEditingController(text: item?.description);
  var date = item?.date ?? DateTime.now();
  TimeOfDay? start = item?.startTime == null
      ? null
      : _parseTime(item!.startTime!);
  TimeOfDay? end = item?.endTime == null ? null : _parseTime(item!.endTime!);
  final selected = item?.topics.map((e) => e.id).toSet() ?? <String>{};
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(item == null ? '新建 Schedule' : '编辑 Schedule'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: desc,
                  minLines: 3,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: '描述'),
                ),
                const SizedBox(height: 14),
                ListTile(
                  title: Text('日期：${DateFormat('yyyy-MM-dd').format(date)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: date,
                    );
                    if (d != null) set(() => date = d);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: start ?? TimeOfDay.now(),
                          );
                          if (t != null) set(() => start = t);
                        },
                        child: Text(
                          start == null ? '选择开始时间' : '开始 ${_time(start!)}',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: end ?? TimeOfDay.now(),
                          );
                          if (t != null) set(() => end = t);
                        },
                        child: Text(
                          end == null ? '选择结束时间' : '结束 ${_time(end!)}',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => set(() {
                        start = null;
                        end = null;
                      }),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
                TopicPicker(topics: c.topics, selected: selected),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await c.saveSchedule(
                  original: item,
                  title: title.text,
                  description: desc.text,
                  date: date,
                  startTime: start == null ? null : _time(start!),
                  endTime: end == null ? null : _time(end!),
                  topicIds: selected.toList(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                message('已保存');
              } catch (e) {
                message(e);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  desc.dispose();
}

TimeOfDay _parseTime(String value) {
  final p = value.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

String _time(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

Future<void> showTopicDialog(
  BuildContext context,
  AppController c,
  void Function(Object) message,
) async {
  final name = TextEditingController(), desc = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建 Topic'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: desc,
              minLines: 3,
              maxLines: null,
              decoration: const InputDecoration(labelText: '描述'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await c.saveTopic(name.text, desc.text);
              if (ctx.mounted) Navigator.pop(ctx);
              message('Topic 已创建');
            } catch (e) {
              message(e);
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  name.dispose();
  desc.dispose();
}
