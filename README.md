# 拾光 — Idea / Task / Schedule

基于 Flutter + SQLite 的 Windows-first、Local-first 个人记录与规划应用，实现 `spec/idea-task-schedule-app-spec-v0.1.md` 的 P0 与 P1。

P1 包括图片附件、剪贴板截图与拖放、Markdown 预览、全局 `Ctrl + Shift + Space` Quick Capture、系统托盘、全文搜索、多条件筛选、日程日期视图，以及包含 SQLite、JSON 和附件的 ZIP 备份。

## 开发

```powershell
flutter pub get
flutter run -d windows
```

验证：

```powershell
flutter analyze
flutter test
flutter build windows --release
```

Windows 插件构建需要开启系统“开发人员模式”（本开发环境已开启）。Release 产物位于 `build/windows/x64/runner/Release/`，运行或分发时请保留整个目录。

## 架构

- `lib/domain`：Idea、Task、Schedule、Topic 领域模型
- `lib/data/app_repository.dart`：数据访问抽象边界
- `lib/data/sqlite_app_repository.dart`：本地 SQLite 实现
- `lib/app`：应用状态与用例编排
- `lib/ui`：Windows 桌面界面，不直接访问 SQL

所有核心实体使用 UUID，保留 `created_at`、`updated_at`、`deleted_at`，删除采用 soft delete。数据库位于 Windows 应用支持目录中的 `its.sqlite`。

图片复制到数据库旁的 `attachments/`，业务实体只保存 Attachment 关联；“导出备份”会生成包含 `database.sqlite`、`data.json` 与 `attachments/` 的 ZIP。
