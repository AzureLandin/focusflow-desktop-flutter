# 开发流程

FocusFlow 从本地日历待办规格出发，以今日待办为默认首页。项目先检查工作区现有的 Obsidian 插件，沿用其产品命名、React 与 TypeScript 技术栈，并用独立桌面应用实现 SQLite、日期归档和计时行为。

| 阶段 | 实现与验收 |
| --- | --- |
| 需求与界面准备 | 梳理今日待办、日历、专注和设置的入口。按规格确定暖纸底、青绿色和统一的样式变量。 |
| 今日待办与持久化 | 建立 SQLite 版本化迁移、任务增删改查、排序、完成和撤销。使用设备本地日期筛选今日任务。 |
| 月历与日结 | 任务按计划日期创建和查询。跨日后归档已完成及未完成任务，补齐应用关闭期间的日结。 |
| 番茄时钟 | 由主进程维护阶段状态和起止时间戳。每轮完成或打断均有独立记录。覆盖短休息、长休息、打断和进程退出后的恢复。 |
| 页面与使用反馈 | 实现独立专注页、番茄想法、任务完成确认、主题、声音与系统通知开关，以及 JSON 备份和恢复。 |
| Windows 验收与发布 | 运行 TypeScript 检查与 esbuild 构建、Node 业务测试和 Playwright Electron 测试。用 Electron Builder 生成 NSIS x64 安装包，通过 GitHub Release 分发。 |

## 关键实现

- [SQLite 迁移](../src/main/migration-001.sql) 和 [数据仓库](../src/main/repository.ts) 管理结构化数据、日结和事务。备份恢复使用版本化 JSON 和事务。
- [番茄状态机](../src/main/pomodoro.ts) 保留阶段截止时间。窗口重开后可恢复当前阶段，已到期的阶段等用户确认下一步。
- [Electron 主进程](../src/main/index.ts) 和 [预加载桥](../src/main/preload.ts) 将数据库和本地文件操作集中在主进程。渲染进程通过限定的 IPC 接口调用业务功能。
- [React 界面](../src/renderer/index.tsx) 管理页面状态。[样式变量](../src/renderer/styles.css) 统一三种主题和窗口宽度下的布局。实际开发时读取了 `huashu-design` 的适用范围，正式桌面应用的实现依据产品规格。

## 工具与分工

- **OpenAI Codex** 协作梳理规格、实现代码、执行构建、检查界面截图和整理发布文档。
- **Node.js 测试运行器** 覆盖 SQLite 事务、跨日、休息、打断、恢复和备份等业务规则。
- **Playwright Electron** 在隔离数据目录中驱动真实窗口，使用模拟时钟验证计时恢复与跨日。备份场景替换了文件选择对话框的返回值，实际读写的是本机测试文件。
- **PowerShell 和 Python Pillow** 用于本地 Windows 快捷方式、ICO 尺寸导出、4K PNG 和产物校验。**OpenAI ImageGen** 用于候选图标设计和用户头像的局部处理。
- **Git 和 GitHub CLI** 管理源码提交、版本标签、安装包上传与发布核对。

## 复现验收

在仓库根目录执行 `npm ci`、`npm test` 和 `npm run test:e2e`。用 `npm run package:win` 生成安装包，再通过 `FOCUSFLOW_E2E_EXECUTABLE` 指定同版本的打包应用执行真实窗口测试。日结和计时恢复用测试时钟加速。Windows 实际系统休眠和系统通知弹出有待单独实测。
