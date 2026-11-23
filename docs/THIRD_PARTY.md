# 开源依赖与素材来源

桌面版在早期 FocusFlow Obsidian 插件的产品方向和前端技术栈基础上实现。任务、日历、番茄状态机和 SQLite 数据仓库由本项目实现。下列开源项目提供界面、日期处理、桌面容器、数据库、构建与测试能力。

| 项目 | 用途 | 上游许可 |
| --- | --- | --- |
| [React、React DOM、Scheduler](https://github.com/facebook/react) | 桌面界面与 React 运行时 | MIT |
| [date-fns](https://github.com/date-fns/date-fns) | 本地日期和日历计算 | MIT |
| [Zod](https://github.com/colinhacks/zod) | IPC 输入和应用设置校验 | MIT |
| [Lucide](https://github.com/lucide-icons/lucide) | 界面线性图标，包含其上游图标许可 | ISC，附带上游许可声明 |
| [Electron](https://github.com/electron/electron) | 桌面运行时、系统通知和进程隔离 | MIT，Chromium 等组件另附许可 |
| [Node.js](https://github.com/nodejs/node) 与 [SQLite](https://sqlite.org/copyright.html) | 主进程和 `node:sqlite` 本地数据库 | Node.js 为 MIT，SQLite 核心为公有领域 |
| [TypeScript](https://github.com/microsoft/TypeScript) | 类型检查 | Apache-2.0 |
| [esbuild](https://github.com/evanw/esbuild) | 构建主进程、预加载桥和界面 | MIT |
| [Playwright](https://github.com/microsoft/playwright) | Electron 窗口端到端测试 | Apache-2.0 |
| [Electron Builder](https://github.com/electron-userland/electron-builder) 与 [NSIS](https://nsis.sourceforge.io/License) | Windows x64 安装包 | Electron Builder 为 MIT，NSIS 许可见上游 |

确切依赖版本见 [`package-lock.json`](../package-lock.json)。构建把界面运行依赖的原版许可汇入 `dist/THIRD_PARTY_LICENSES.txt`。Windows 发行目录另附 Electron 与 Chromium 的许可证文件。

## 图标与素材

[`assets/icon.png`](../assets/icon.png) 和 [`assets/icon.ico`](../assets/icon.ico) 是构建与安装包使用的默认 FocusFlow 图标，由程序绘制生成。公开发行使用此图标。
