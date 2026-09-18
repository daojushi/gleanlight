# 拾光 — Idea / Task / Schedule

基于 Flutter + SQLite 的 Windows-first、Local-first 个人记录与规划应用，实现 `spec/idea-task-schedule-app-spec-v0.1.md` 的 P0、P1 与 P2 客户端能力。

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

## Android 与跨设备同步

- Android 使用同一套 Domain/Application 层与原生 `sqflite` 本地数据库。
- 手机端采用底部导航和快速记录 FAB；离线、未登录时核心功能仍完整可用。
- Android 已注册文本分享入口；从浏览器、阅读器等应用“分享”文本到拾光后，会直接打开快速记录并预填内容。
- 同步位于可替换的 `SyncProvider` 边界后，当前提供 Supabase 实现。
- 同步按 `updated_at` 合并记录、保留 soft-delete tombstone、同步附件对象；等时异值冲突会写入本地冲突表，可在“设置 → 查看同步冲突”中选择保留本机或采用其他设备版本。
- Android 使用 WorkManager 每 30 分钟安排一次仅联网时执行的后台同步。

启用云同步：

1. 创建 Supabase 项目。
2. 在 SQL Editor 执行 [`supabase/schema.sql`](supabase/schema.sql)。
3. 在应用“设置”中填写 Project URL 与 publishable/anon key，保存后重启。
4. Windows 和 Android 使用同一账号注册或登录。

未填写配置时应用使用 `NoSyncProvider`，保持纯离线模式。Android 调试包可通过 `flutter build apk --debug` 构建。

当前同步实现是 `SyncProvider` 后的自定义 Supabase 记录级同步，而不是把业务层绑定到 PowerSync。若后续采用 PowerSync，只需增加新的 Provider，并为其配置 PowerSync 服务端 endpoint；不应让两个客户端直接共享同一个 SQLite 文件。

本机已配置 `Its_API_36` AVD。运行模拟器还要求 Windows Hypervisor Platform/Android Emulator Hypervisor Driver 可用；可先执行 `emulator -accel-check`，确认加速可用后再执行 `flutter run -d emulator-5554`。
