import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, Notification, powerMonitor, type IpcMainInvokeEvent } from 'electron';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ZodError } from 'zod';
import type { Result } from '../shared/model';
import { exportBackup, restoreBackup } from './backup';
import { UserError } from './database';
import { Repository } from './repository';

app.setName('FocusFlow');
if (process.platform === 'win32') app.setAppUserModelId('com.focusflow.desktop');
const customProfile = app.commandLine.getSwitchValue('user-data-dir');
if (customProfile) app.setPath('userData', customProfile);
const indexPath = join(__dirname, 'index.html');
let window: BrowserWindow | undefined;
let store: Repository;
let heartbeat: ReturnType<typeof setInterval> | undefined;
let backupDialog = false;
let heartbeatFailed = false;

function createWindow() {
  const main = new BrowserWindow({
    title: 'FocusFlow', width: 1240, height: 840, minWidth: 800, minHeight: 590,
    show: false, autoHideMenuBar: true, backgroundColor: nativeTheme.shouldUseDarkColors ? '#212521' : '#f8f7f2',
    icon: join(__dirname, 'icon.png'),
    webPreferences: { preload: join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true,
      nodeIntegration: false, autoplayPolicy: 'no-user-gesture-required' },
  });
  window = main;
  main.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  main.webContents.on('will-navigate', (event) => event.preventDefault());
  main.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  main.webContents.session.setPermissionCheckHandler(() => false);
  main.on('ready-to-show', () => main.show());
  main.on('closed', () => { if (window === main) window = undefined; });
  void main.loadFile(indexPath).catch((error) => {
    console.error(error);
    dialog.showErrorBox('FocusFlow 无法启动', '无法加载应用界面。请重新安装后再试。');
  });
}

function handle<T>(channel: string, action: (input: unknown) => T | Promise<T>) {
  ipcMain.handle(channel, async (event: IpcMainInvokeEvent, input: unknown): Promise<Result<T>> => {
    if (event.sender !== window?.webContents || event.senderFrame?.url !== pathToFileURL(indexPath).href) {
      return { ok: false, message: '无法验证操作来源。' };
    }
    try { return { ok: true, value: await action(input) }; }
    catch (error) {
      if (error instanceof UserError) return { ok: false, message: error.message };
      if (error instanceof ZodError) return { ok: false, message: '输入格式或数值超出允许范围，请检查后重试。' };
      console.error(error);
      return { ok: false, message: '操作失败。请重试，或在设置中检查数据位置和磁盘空间。' };
    }
  });
}

async function backup(action: unknown) {
  const main = window;
  if (!main || backupDialog || (action !== 'export' && action !== 'import')) return false;
  if (store.pulse().session) throw new UserError('请在专注会话结束后管理备份。');
  backupDialog = true;
  try {
    if (action === 'export') {
      const { filePath } = await dialog.showSaveDialog(main, { title: '导出 FocusFlow 备份', defaultPath: 'FocusFlow-backup.json',
        filters: [{ name: 'JSON 备份', extensions: ['json'] }] });
      if (!filePath) return false;
      await writeFile(filePath, exportBackup(store.db), 'utf8');
      return true;
    }
    const selected = await dialog.showOpenDialog(main, { title: '选择 FocusFlow 备份', properties: ['openFile'],
      filters: [{ name: 'JSON 备份', extensions: ['json'] }] });
    const [file] = selected.filePaths;
    if (!file) return false;
    if ((await stat(file)).size > 100 * 1024 * 1024) throw new UserError('备份文件超过 100 MB。');
    const { response } = await dialog.showMessageBox(main, { type: 'warning', title: '恢复备份',
      message: '用此备份替换当前应用数据？', detail: '应用会先在数据目录保存当前数据的 JSON 备份。',
      buttons: ['取消', '恢复备份'], defaultId: 0, cancelId: 0 });
    if (response !== 1) return false;
    const contents = await readFile(file, 'utf8');
    if (store.pulse().session) throw new UserError('请在专注会话结束后再恢复备份。');
    await writeFile(join(app.getPath('userData'), `before-restore-${Date.now()}.json`), exportBackup(store.db), { encoding: 'utf8', flag: 'wx' });
    if (store.pulse().session) throw new UserError('请在专注会话结束后再恢复备份。');
    restoreBackup(store.db, contents);
    store.recheck();
    return true;
  } finally { backupDialog = false; }
}

function sync() {
  try { store.sync(); heartbeatFailed = false; }
  catch (error) { if (!heartbeatFailed) console.error(error); heartbeatFailed = true; }
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => {
    if (window?.isMinimized()) window.restore();
    window?.focus();
  });
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
  app.on('before-quit', () => { clearInterval(heartbeat); store?.db.close(); });
  app.on('activate', () => { if (!window && store) createWindow(); });
  void app.whenReady().then(async () => {
    const profile = app.getPath('userData');
    await mkdir(profile, { recursive: true });
    store = new Repository(join(profile, 'focusflow.sqlite3'), () => Date.now(), (message) => {
      const settings = store.settings();
      if (settings.sound && window && !window.webContents.isLoading()) window.webContents.send('timer:chime');
      if (settings.notifications && Notification.isSupported()) new Notification({ title: 'FocusFlow', body: message, silent: true }).show();
    });
    handle('workspace:read', (query) => store.read(query));
    handle('workspace:pulse', () => store.pulse());
    handle('workspace:command', (command) => store.command(command));
    handle('workspace:backup', backup);
    Menu.setApplicationMenu(process.platform === 'darwin'
      ? Menu.buildFromTemplate([{ role: 'appMenu' }, { role: 'editMenu' }, { role: 'windowMenu' }])
      : null);
    createWindow();
    heartbeat = setInterval(sync, 750);
    powerMonitor.on('resume', sync);
    app.on('browser-window-focus', sync);
  }).catch((error: unknown) => {
    console.error(error);
    dialog.showErrorBox('FocusFlow 无法启动', error instanceof Error ? error.message : '无法打开本地数据。');
    app.quit();
  });
}
