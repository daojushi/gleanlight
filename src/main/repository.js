const { randomUUID } = require('node:crypto');

const TABLES = { idea: 'ideas', task: 'tasks', schedule: 'schedules' };
const STATUSES = {
  idea: new Set(['New', 'Thinking', 'Ready', 'Implemented', 'Shelved']),
  task: new Set(['Todo', 'Doing', 'Done']),
};

class Repository {
  constructor(database) {
    this.database = database;
  }

  now() { return new Date().toISOString(); }

  topicsFor(entityType, entityId) {
    return this.database.all(`
      SELECT t.* FROM topics t JOIN entity_topics et ON et.topic_id = t.id
      WHERE et.entity_type = $type AND et.entity_id = $id AND t.deleted_at IS NULL
      ORDER BY t.name`, { $type: entityType, $id: entityId });
  }

  decorate(type, rows) {
    return rows.map(row => ({ ...row, topics: this.topicsFor(type, row.id) }));
  }

  list(type) {
    const table = TABLES[type];
    if (!table) throw new Error('Unknown entity type');
    const order = type === 'idea' ? 'created_at DESC'
      : type === 'task' ? "CASE status WHEN 'Doing' THEN 0 WHEN 'Todo' THEN 1 ELSE 2 END, deadline IS NULL, deadline, created_at DESC"
      : 'date, start_time IS NULL, start_time';
    return this.decorate(type, this.database.all(`SELECT * FROM ${table} WHERE deleted_at IS NULL ORDER BY ${order}`));
  }

  save(type, input) {
    if (!TABLES[type]) throw new Error('Unknown entity type');
    const now = this.now();
    const id = input.id || randomUUID();
    const existing = input.id ? this.database.all(`SELECT id, created_at FROM ${TABLES[type]} WHERE id = $id`, { $id: id })[0] : null;
    const createdAt = existing?.created_at || now;
    this.validate(type, input);

    return this.database.transaction(() => {
      if (type === 'idea') {
        this.database.run(`INSERT OR REPLACE INTO ideas
          (id, content, status, created_at, updated_at, deleted_at)
          VALUES ($id, $content, $status, $created, $updated, NULL)`, {
          $id: id, $content: input.content.trim(), $status: input.status || 'New', $created: createdAt, $updated: now,
        });
      } else if (type === 'task') {
        const status = input.status || 'Todo';
        const old = this.database.all('SELECT completed_at FROM tasks WHERE id = $id', { $id: id })[0];
        const completedAt = status === 'Done' ? (old?.completed_at || now) : null;
        this.database.run(`INSERT OR REPLACE INTO tasks
          (id, title, description, status, deadline, created_at, updated_at, completed_at, deleted_at)
          VALUES ($id, $title, $description, $status, $deadline, $created, $updated, $completed, NULL)`, {
          $id: id, $title: input.title.trim(), $description: (input.description || '').trim(),
          $status: status, $deadline: input.deadline || null, $created: createdAt, $updated: now, $completed: completedAt,
        });
      } else {
        this.database.run(`INSERT OR REPLACE INTO schedules
          (id, title, description, date, start_time, end_time, created_at, updated_at, deleted_at)
          VALUES ($id, $title, $description, $date, $start, $end, $created, $updated, NULL)`, {
          $id: id, $title: input.title.trim(), $description: (input.description || '').trim(),
          $date: input.date, $start: input.start_time || null, $end: input.end_time || null,
          $created: createdAt, $updated: now,
        });
      }
      this.setTopics(type, id, input.topic_ids || []);
      return id;
    });
  }

  validate(type, input) {
    if (type === 'idea' && !input.content?.trim()) throw new Error('Idea 内容不能为空');
    if ((type === 'task' || type === 'schedule') && !input.title?.trim()) throw new Error('标题不能为空');
    if (type === 'schedule' && !input.date) throw new Error('日期不能为空');
    if (STATUSES[type] && !STATUSES[type].has(input.status || (type === 'idea' ? 'New' : 'Todo'))) throw new Error('状态无效');
    if (type === 'schedule' && input.start_time && input.end_time && input.end_time <= input.start_time) {
      throw new Error('结束时间必须晚于开始时间');
    }
  }

  setTopics(type, id, topicIds) {
    this.database.run('DELETE FROM entity_topics WHERE entity_type = $type AND entity_id = $id', { $type: type, $id: id });
    [...new Set(topicIds)].forEach(topicId => this.database.run(
      'INSERT INTO entity_topics(entity_type, entity_id, topic_id) VALUES ($type, $id, $topic)',
      { $type: type, $id: id, $topic: topicId },
    ));
  }

  remove(type, id) {
    if (!TABLES[type]) throw new Error('Unknown entity type');
    this.database.transaction(() => {
      this.database.run(
        `UPDATE ${TABLES[type]} SET deleted_at = $now, updated_at = $now WHERE id = $id`,
        { $now: this.now(), $id: id },
      );
      this.database.run(
        'DELETE FROM entity_topics WHERE entity_type = $type AND entity_id = $id',
        { $type: type, $id: id },
      );
    });
  }

  saveTopic(input) {
    if (!input.name?.trim()) throw new Error('Topic 名称不能为空');
    const now = this.now();
    const id = input.id || randomUUID();
    const old = input.id ? this.database.all('SELECT created_at FROM topics WHERE id = $id', { $id: id })[0] : null;
    this.database.transaction(() => this.database.run(`INSERT OR REPLACE INTO topics
      (id, name, description, created_at, updated_at, deleted_at)
      VALUES ($id, $name, $description, $created, $updated, NULL)`, {
      $id: id, $name: input.name.trim(), $description: (input.description || '').trim(),
      $created: old?.created_at || now, $updated: now,
    }));
    return id;
  }

  listTopics() {
    return this.database.all(`SELECT t.*, COUNT(et.entity_id) AS item_count
      FROM topics t LEFT JOIN entity_topics et ON et.topic_id = t.id
      WHERE t.deleted_at IS NULL GROUP BY t.id ORDER BY t.name`);
  }

  topicDetail(id) {
    const topic = this.database.all('SELECT * FROM topics WHERE id = $id AND deleted_at IS NULL', { $id: id })[0];
    if (!topic) return null;
    const items = {};
    for (const [type, table] of Object.entries(TABLES)) {
      items[`${type}s`] = this.decorate(type, this.database.all(`SELECT e.* FROM ${table} e
        JOIN entity_topics et ON et.entity_id=e.id AND et.entity_type=$type
        WHERE et.topic_id=$id AND e.deleted_at IS NULL ORDER BY e.created_at DESC`, { $type: type, $id: id }));
    }
    return { ...topic, ...items };
  }
}

module.exports = { Repository };
