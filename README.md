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

## 修改存储位置

在“设置 → 存储位置”中选择目录后，应用会在该目录创建 `ItsData/`，安全迁移数据库与附件，并立即从新位置重新加载。迁移过程包含数据库关闭、临时目录复制、SQLite 完整性检查、附件逐项校验、附件路径重写、设置原子更新和失败回退。

存储位置配置固定保存在 `%APPDATA%\com.localfirst\its_app\settings.json`，因此数据库移动后及应用重启时仍能正确定位数据。
