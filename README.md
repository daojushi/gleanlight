# 拾光

拾光是一个 Windows-first、Local-first 的个人记录与规划应用，用独立的 Idea、Task 和 Schedule 承接“先记下来，再决定如何行动”的工作流。

很多笔记工具会迫使用户在记录时立即分类或创建任务。拾光把快速捕捉放在首位：Idea 保留思考，Task 表示可执行事项，Schedule 表示已确定的时间安排，Topic 则在不同类型之间聚合同一主题。

## 核心体验

- **快速记录**：默认首页直接输入 Idea，Windows 可用 `Ctrl + Shift + Space` 全局唤起。
- **灵感流转**：灵感可在“新想法 / 思考中 / 实践中 / 已实现 / 搁置”之间直接切换。已实现内容会移入“历史灵感”，按最后更新时间倒序展示。
- **图片与长内容**：支持 Markdown 预览、图片选择与拖放；在灵感输入框中按 `Ctrl + V` 可直接粘贴文字或截图。图片可放大、缩放、拖动，并可通过按钮或 `Ctrl + C` 复制原图。
- **聚合与检索**：支持全文搜索、状态筛选、Topic 筛选，以及跨 Idea、Task、Schedule 的 Topic 聚合视图。
- **本地数据优先**：离线时所有核心功能仍然可用；数据库和附件存储位置可迁移，也可导出完整 ZIP 备份。
- **可选同步**：不配置云服务时保持纯本地模式；需要时可通过自己的 Supabase 项目在 Windows 和 Android 之间同步。

## 快速开始

需要 Flutter SDK，并安装 Windows 桌面开发环境。Windows 插件构建还需开启系统“开发人员模式”。

```powershell
flutter pub get
flutter run -d windows
```

上述命令在仓库根目录中执行。如果已经获得构建好的 Windows 版本，请保留 Release 目录中的 `data/`、DLL 和可执行文件，不要只单独复制 `its_app.exe`。

## 构建与验证

```powershell
flutter analyze
flutter test
flutter build windows --release
```

Windows Release 产物位于：

```text
build/windows/x64/runner/Release/
```

要准备日常使用的稳定版，请将整个 `Release/` 目录复制到开发目录之外。更新时先退出应用（包括系统托盘），再用新的完整目录覆盖旧版。

Android 调试包可通过以下命令构建：

```powershell
flutter build apk --debug
```

## 数据存储与备份

默认情况下，Windows 数据位于：

```text
%APPDATA%\com.localfirst\its_app\
```

- `its.sqlite`：Idea、Task、Schedule、Topic 及关联数据。
- `attachments/`：灵感的图片附件。
- `settings.json`：当前数据存储位置等持久化设置。

在“设置 → 存储位置”中选择新目录后，应用会创建 `ItsData/` 并迁移数据库和附件。迁移过程会先复制到临时目录，完成 SQLite 完整性和附件校验后再切换；失败时保留原数据。

“导出备份”会生成包含 SQLite 数据库、JSON 数据和附件的 ZIP 文件。

## 可选的跨设备同步

1. 创建 Supabase 项目。
2. 在 SQL Editor 执行 [`supabase/schema.sql`](supabase/schema.sql)。
3. 在应用“设置”中填写 Project URL 和 publishable/anon key，保存后重启。
4. Windows 和 Android 使用同一账号注册或登录。

同步实现位于可替换的 `SyncProvider` 边界之后，按 `updated_at` 合并记录、保留 soft-delete tombstone 并同步附件。等时异值冲突会保存到本地，可在“设置 → 查看同步冲突”中处理。未填写同步配置时，应用使用 `NoSyncProvider`，核心功能完全离线可用。

## 架构导航

- [`lib/domain`](lib/domain)：Idea、Task、Schedule、Topic 等领域模型。
- [`lib/app`](lib/app)：应用状态、用例编排及桌面/Android 集成。
- [`lib/data`](lib/data)：数据访问边界、SQLite 实现和存储迁移。
- [`lib/sync`](lib/sync)：同步抽象、Supabase 实现、冲突和后台同步。
- [`lib/ui`](lib/ui)：Windows/Android 自适应界面，通过应用控制器访问业务能力，不直接操作 SQL。

核心实体使用 UUID，保留 `created_at`、`updated_at`、`deleted_at`，删除采用 soft delete。更完整的产品语义、领域边界和验收场景见 [`spec/idea-task-schedule-app-spec-v0.1.md`](spec/idea-task-schedule-app-spec-v0.1.md)。
