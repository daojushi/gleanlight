const fs = require('node:fs');
const path = require('node:path');
const initSqlJs = require('sql.js');

class Database {
  constructor(filePath) {
    this.filePath = filePath;
    this.db = null;
  }

  async open() {
    const SQL = await initSqlJs({
      locateFile: file => path.join(path.dirname(require.resolve('sql.js/dist/sql-wasm.js')), file),
    });
    this.db = fs.existsSync(this.filePath)
      ? new SQL.Database(fs.readFileSync(this.filePath))
      : new SQL.Database();
    this.db.run('PRAGMA foreign_keys = ON');
    this.migrate();
    this.persist();
  }

  migrate() {
    this.db.run(`
      CREATE TABLE IF NOT EXISTS ideas (
        id TEXT PRIMARY KEY, content TEXT NOT NULL, status TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL, deadline TEXT, created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL, completed_at TEXT, deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS schedules (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL, start_time TEXT, end_time TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS topics (
        id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        description TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL, deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS entity_topics (
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, topic_id TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id, topic_id),
        FOREIGN KEY (topic_id) REFERENCES topics(id)
      );
      CREATE INDEX IF NOT EXISTS idx_ideas_created ON ideas(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_tasks_deadline ON tasks(deadline);
      CREATE INDEX IF NOT EXISTS idx_schedules_date ON schedules(date, start_time);
      CREATE INDEX IF NOT EXISTS idx_entity_topics_topic ON entity_topics(topic_id);
    `);
  }

  all(sql, params = {}) {
    const statement = this.db.prepare(sql);
    statement.bind(params);
    const rows = [];
    while (statement.step()) rows.push(statement.getAsObject());
    statement.free();
    return rows;
  }

  run(sql, params = {}) {
    this.db.run(sql, params);
  }

  transaction(work) {
    this.db.run('BEGIN');
    try {
      const result = work();
      this.db.run('COMMIT');
      this.persist();
      return result;
    } catch (error) {
      this.db.run('ROLLBACK');
      throw error;
    }
  }

  persist() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const tempPath = `${this.filePath}.tmp`;
    fs.writeFileSync(tempPath, Buffer.from(this.db.export()));
    fs.renameSync(tempPath, this.filePath);
  }
}

module.exports = { Database };
