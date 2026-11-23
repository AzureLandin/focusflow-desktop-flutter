# Tauri 2 迁移审计

## Phase 0 基线

2026-11-23，从 `main` 的 `72608d9` 创建本地分支 `feat/tauri-v2-migration`。工作区已含未发布的 Electron 安装体积优化和 macOS 本地打包准备，迁移保留它们。测试使用独立临时目录。

| 检查 | Electron 0.10.0 |
| --- | --- |
| `npm ci --offline --no-audit` | 通过 |
| `npm test` | 8 项业务测试通过 |
| `npm run test:e2e` | 真实 Electron 窗口验收通过 |
| `npm run package:win -- --config.directories.output=release/tauri-migration-electron-baseline` | 通过。安装包 113,070,412 字节，解包目录 326,485,592 字节 |
| 已发布 Windows x64 安装包 | 125,494,399 字节 |
| 迁移前本地精简版安装包 / 解包目录 | 113,070,451 / 326,485,413 字节 |
| 精简版启动至今日待办可见 | 4,420 ms，Playwright 启动到界面可见的单次采样 |
| 空闲工作集 | 367,468 KiB，窗口可见约 1.2 秒后，Browser / GPU / Utility / Tab 的工作集求和，含共享页 |
| 数据库 | `%APPDATA%\FocusFlow\focusflow.sqlite3`，`user_version=1` |

旧版生成的演示备份和采样数据在本地 `test-output/tauri-baseline/`。文档中的性能数字属于当前设备和采样条件。

## 代码映射

| 当前文件 | 迁移职责 |
| --- | --- |
| `src/main/index.ts` | Electron app、窗口、IPC、原生菜单、主题、通知、电源和单实例调用迁入 Tauri 入口、命令与生命周期。 |
| `src/main/preload.ts` | `contextBridge` 和 `ipcRenderer` 对应 `src/platform/tauri-api.ts` 的 `invoke` 和事件订阅。 |
| `src/main/database.ts`、`migration-001.sql` | Rust SQLite 初始化、锁、事务及相同的 migration 001。 |
| `src/main/repository.ts` | 日期、任务 CRUD、排序、月历、日结、想法及设置迁入 Rust Repository。 |
| `src/main/pomodoro.ts` | 依赖绝对毫秒时间戳的番茄状态机，Rust 定时检查持久化记录。 |
| `src/main/backup.ts` | 延续备份版本、字段与顺序无关的 JSON 对象语义，恢复由后端执行。 |
| `src/shared/model.ts`、`src/renderer/` | 复用 DTO、画面、表单、计时显示和 `DesktopApi`。由 Tauri 入口在载入 React 前安装适配器。 |
| `scripts/build.mjs`、`package.json` | 独立的 `dist/frontend/` 和 Tauri 命令。迁移验收期间保留 Electron 路径。 |
| `tests/` | Rust 核心和契约验证，加上 Windows WebView2 窗口验收。 |

## 数据契约与风险

- 迁移版本 1 包含 `tasks`、`daily_records`、`pomodoro_sessions`、`pomodoro_cycles`、`pomodoro_interruptions`、`thought_notes` 和 `app_settings`，均为 SQLite STRICT 表。索引包括 `tasks_by_date`、`cycles_by_date`、`thoughts_by_date`、`thoughts_by_session` 和限制唯一活动会话的 `one_active_session`。保留主键、外键、复合唯一约束和状态检查。
- 当前库启用外键、WAL、FULL 同步和 3000 ms 等待，事务采用 `BEGIN IMMEDIATE`。迁移保留数据库版本号及历史日期。跨日和番茄到期处理以设备本地日期及持久化截止时间为准。
- 旧版 JSON 顶层字段为 `format: "focusflow-backup"`、`version: 1` 和 `data`。`data` 为七张表的完整行数组。日期为 `YYYY-MM-DD`，时间为 epoch 毫秒。SQLite 逻辑标志在数据库和备份中使用 `0` / `1`。
- 生产目录沿用 Windows Roaming 和 macOS Application Support 中的 `FocusFlow`。Tauri 首次接管版本 1 文件需一致快照并验证。测试、开发和性能采样均使用独立数据库。
- macOS Universal DMG 的构建、签名和 Dock、通知等行为需要 Mac 真机。当前开发机为 Windows，GitHub 及外部构建运行需单独授权。

## Phase 1–5 本地核对

| 阶段 | 已核对项 |
| --- | --- |
| 1 · 工程和窗口 | TypeScript 检查和独立前端构建通过。Windows WebView2 显示同一套 React 界面。 |
| 2 · IPC | 实际窗口可加载工作区和运行任务命令，越界命令返回用户可读错误。 |
| 3 · SQLite | 迁移 SQL 与 Electron 版本逐字节一致。实际窗口读取旧版生成的隔离数据库，并创建首次接管快照。 |
| 4 · 计时 | 实际窗口可开始专注、记录想法并在异常退出后恢复，完成轮次计数为 1。 |
| 5 · 系统集成 | Windows 原生文件选择已验证导出和恢复，成功恢复演示任务，并生成恢复前的 JSON。已安装版本的通知及 macOS 生命周期需分别实测。 |

Windows 窗口首次核对使用本机 GNU 开发构建。发布目标为 Windows x64 MSVC 和 macOS Universal。

## Phase 6 本地安装与性能对比

在 Windows 11（10.0.26300）上用 `npm run build:win` 生成了 x64 MSVC 候选包。候选包通过本地安装、WebView2 端到端测试、原生备份导出和恢复、旧版 JSON 导入、关闭主窗口退出，以及卸载。端到端测试从 Electron 0.10 的隔离数据库启动，验证第二实例未打开额外数据库，以及强制结束进程后恢复专注只结算一次。首次升级快照可作为单独的 SQLite 文件打开，快照的 `user_version=1`，日志模式为 `delete`。完整 MSVC 工程的 7 项 Rust 业务测试通过。原有桌面快捷方式的哈希在安装测试前后一致。

| 指标 | 本机精简 Electron 0.10 | Tauri 0.11 x64 MSVC 候选包 |
| --- | ---: | ---: |
| NSIS 安装包 | 113,070,412 字节 | 2,548,486 字节 |
| 安装目录 | 326,485,592 字节 | 8,575,574 字节 |
| 启动至今日待办可见 | 4,420 ms | 1,217 ms |
| 窗口可见后空闲工作集 | 367,468 KiB | 368,644 KiB |

安装目录不含系统 WebView2 运行时和用户数据。启动时间和工作集为本机单次采样。工作集统计包含桌面进程及 WebView 子进程的共享页，同一内存页可能计入多个进程。与本机精简后的 Electron 版相比，安装包体积下降约 97.7%，工作集接近旧版。

本地候选包为 `release/tauri-local/FocusFlow_0.11.0_x64-setup.exe`，SHA-256 为 `4EBD542B2E043CCFDC624282902BEE8D8612B255B8B80FA09E6C48C61216F64B`。

Windows 10 缺失 WebView2 的机器、系统通知、实际系统休眠及 macOS Universal DMG 仍需实机验收。Phase 7 清理 Electron 的条件尚未满足。
