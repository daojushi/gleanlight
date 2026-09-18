# 拾光 — Idea / Task / Schedule

Windows-first、Local-first 的个人记录与规划桌面应用，实现 `spec/idea-task-schedule-app-spec-v0.1.md` 的 P0。

```powershell
npm install
npm start
```

运行测试：`npm test`。SQLite 数据保存在 Electron 的 `userData/its.sqlite`，所有删除均为 soft delete。

架构边界：`src/renderer` 只负责界面；`repository.js` 管理领域数据和校验；`database.js` 管理 SQLite；主进程与界面通过安全 IPC 通信。核心实体全部使用 UUID，并保留 `created_at`、`updated_at`、`deleted_at`。
