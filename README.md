# FocusFlow 桌面版 0.10

FocusFlow 是本地日历待办与番茄时钟。打开应用会查看设备本地日期对应的待办。日历提供未来计划、历史任务、当天专注记录和番茄想法。日常使用只需要本机和一个可写的数据目录。

## 安装与开发

在 Windows x64 上从 [v0.10.0 发布页](https://github.com/LenchLyu/focusflow-desktop/releases/tag/v0.10.0) 下载 `FocusFlow-Setup-0.10.0-x64.exe`，按安装向导启动 FocusFlow。自行构建的安装包位于 `release/v0.10.0/`，同目录的 `win-unpacked/FocusFlow.exe` 可直接运行，需保留相邻的运行库和资源文件。安装包和可执行文件未经代码签名。

开发环境需要 Node.js 24 或更新版本，以及 npm。在仓库根目录执行以下命令。首次安装依赖和打包会下载 Electron 和打包工具，应用日常运行可离线。

```powershell
npm ci
npm run dev
npm test
npm run test:e2e
npm run package:win
```

`npm run build` 生成 `dist/`，`npm start` 启动已构建的开发版。`npm run test:e2e` 会启动真实 Electron 窗口，在独立的临时 SQLite 数据库中模拟阶段到期和跨日。可以在运行测试前设置 `FOCUSFLOW_E2E_SCREENSHOTS` 以保存截图，或用 `FOCUSFLOW_E2E_EXECUTABLE` 指定要验收的 Windows 可执行文件。

## 使用手册

- **今日待办**　在快速输入框按 Enter 添加任务。用「详细添加」填写描述、计划日期和番茄数。任务行支持上移、下移、编辑和删除，单击勾选框可完成或恢复任务。
- **专注**　从开启了番茄时钟的今日任务开始，或选「快速开始专注」填写事项。默认专注 25 分钟、短休息 5 分钟，每 4 轮在还有后续番茄时休息 15 分钟。阶段结束后选择下一步。满足任务计划后，在总结里确认任务是否完成。快速专注的总结可以选择将事项加入今日待办。
- **打断和恢复**　打断时填入原因。已完成轮次和写下的想法会保留。窗口可正常切换和关闭。重开后恢复当前阶段，若阶段已到期则等待确认下一步。
- **番茄想法**　从今日待办、日历或专注页面打开。当天的想法可以新增、编辑或删除。在输入框按 Ctrl+Enter 可立即保存。
- **日历**　选择日期查看任务、专注和想法。为未来日期安排的任务会在对应日期自动出现在今日待办。跨日后，未完成任务在原日期归档。跨日时应用关闭也会在下次打开补齐日结。
- **设置与备份**　时长、提示音、系统通知和主题均可调整。设置页显示数据库完整路径。导出 JSON 可备份所有业务数据。恢复会替换当前数据，应用先在数据目录保存一个 `before-restore-*.json` 回滚备份。

## 数据与实现

Windows 默认数据目录为 `%APPDATA%\FocusFlow`，数据库文件为 `focusflow.sqlite3`。可使用 `--user-data-dir=绝对路径` 指定独立配置目录，用于测试或并列启动。项目沿用早期 FocusFlow Obsidian 插件的 React、TypeScript 和 esbuild 前端技术栈，桌面版由 Electron 主进程使用 Node.js 内置 SQLite 管理独立数据。

- `src/main/migration-001.sql` 定义任务、日结、会话、番茄轮次、打断、想法与设置表。`Database` 按 `PRAGMA user_version` 依序运行迁移。
- `src/main/repository.ts` 管理 SQLite 事务与本地日期。`src/main/pomodoro.ts` 集中管理专注状态转换和完成轮次的计数。轮次的统计归入截止时刻对应的本地日期，任务保留自己的计划日期。
- `src/main/backup.ts` 管理版本化 JSON、恢复校验和事务。`src/shared/model.ts` 定义数据结构、参数校验及桌面桥接口。
- `src/renderer/` 管理界面。主题由根 CSS token 驱动。将来可在外壳层接入本地壁纸和桌宠，计时与持久化继续通过现有主进程模块维护。

## 开发记录与来源

- [开发流程、技术决策与验收方法](docs/DEVELOPMENT.md)
- [开源依赖、参考来源和个性化图标说明](docs/THIRD_PARTY.md)
- [版本记录](CHANGELOG.md)

## 开源许可

FocusFlow 桌面版源代码采用 [ISC License](LICENSE)。第三方组件的许可与素材来源见[开源依赖说明](docs/THIRD_PARTY.md)。
