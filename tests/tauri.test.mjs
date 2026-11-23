import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { copyFile, mkdtemp, readdir, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from 'playwright-core';

async function freePort() {
  const server = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const { port } = server.address();
  await new Promise((done) => server.close(done));
  return port;
}

async function openWebView(executable, profile) {
  const port = await freePort();
  const child = spawn(executable, [], { windowsHide: true, stdio: 'ignore', env: {
    ...process.env, FOCUSFLOW_DATA_DIR: profile,
    WEBVIEW2_USER_DATA_FOLDER: join(profile, 'WebView2'),
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port}`,
  } });
  const closed = once(child, 'close');
  let startupError;
  child.once('error', (error) => { startupError = error; });
  void closed.catch(() => {});
  const endpoint = `http://127.0.0.1:${port}`;
  let browser;
  try {
    for (let attempt = 0; attempt < 80; attempt++) {
      if (startupError) throw startupError;
      if (child.exitCode !== null) throw new Error(`FocusFlow exited with ${child.exitCode}`);
      if (await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(1000) }).then((response) => response.ok).catch(() => false)) break;
      await delay(250);
    }
    browser = await chromium.connectOverCDP(endpoint, { timeout: 5000 });
    const context = browser.contexts()[0];
    const page = context.pages()[0] ?? await context.waitForEvent('page', { timeout: 5000 });
    return { page, pid: child.pid, async close() {
      if (child.exitCode === null && child.signalCode === null) child.kill();
      await closed;
      await browser.close().catch(() => {});
    } };
  } catch (error) {
    if (child.exitCode === null && child.signalCode === null) child.kill();
    await closed.catch(() => {});
    await browser?.close().catch(() => {});
    throw error;
  }
}

test('Tauri IPC and the bundled WebView2 work through a separate data directory', {
  skip: process.platform !== 'win32', timeout: 120_000,
}, async (t) => {
  const profile = await mkdtemp(join(tmpdir(), 'FocusFlow 中文测试 '));
  const executable = resolve(process.env.FOCUSFLOW_E2E_EXECUTABLE ?? 'src-tauri/target/release/focusflow.exe');
  const database = join(profile, 'focusflow.sqlite3');
  const legacy = process.env.FOCUSFLOW_LEGACY_DB;
  if (legacy) await copyFile(legacy, database);
  let app;
  t.after(async () => {
    await app?.close();
    await rm(profile, { recursive: true, force: true, maxRetries: 4, retryDelay: 250 });
  });

  app = await openWebView(executable, profile);
  let { page } = app;
  await page.getByRole('heading', { name: '今日待办', exact: true }).waitFor();
  const read = () => page.evaluate(() => window.focusflow.read({}));
  const initial = await read();
  assert.equal(initial.ok, true);
  assert.equal(initial.value.dataPath, database);
  if (legacy) {
    assert.ok(initial.value.todayData.tasks.length > 0, 'Legacy tasks are visible in the isolated profile');
    assert.ok((await readdir(profile)).some((file) => file.startsWith('before-tauri-')));
  }

  const duplicateProfile = 'duplicate-instance';
  const duplicate = spawn(executable, [], { windowsHide: true, stdio: 'ignore', env: {
    ...process.env, FOCUSFLOW_DATA_DIR: join(profile, duplicateProfile),
  } });
  try {
    await once(duplicate, 'close', { signal: AbortSignal.timeout(8000) });
    assert.ok(!(await readdir(profile)).includes(duplicateProfile), 'A second instance must exit before opening its database');
  } finally {
    if (duplicate.exitCode === null && duplicate.signalCode === null) duplicate.kill();
  }

  const invalid = await page.evaluate(() => window.focusflow.command({ type: 'moveTask', id: 'incorrect', direction: 9 }));
  assert.equal(invalid.ok, false);
  assert.match(invalid.message, /输入格式/);
  await page.getByRole('button', { name: '详细添加', exact: true }).click();
  await page.getByLabel('任务名称').fill('Tauri 日历测试');
  await page.getByRole('checkbox', { name: '启用番茄时钟' }).check();
  await page.getByRole('button', { name: '保存任务', exact: true }).click();
  await page.getByText('Tauri 日历测试', { exact: true }).waitFor();
  await page.getByRole('button', { name: '日历', exact: true }).click();
  await page.getByRole('heading', { name: '日历', exact: true }).waitFor();
  await page.getByRole('button', { name: '今日待办', exact: true }).click();
  await page.getByRole('listitem').filter({ hasText: 'Tauri 日历测试' })
    .getByRole('button', { name: '开始专注', exact: true }).click();
  await page.getByRole('button', { name: '开始计时', exact: true }).click();
  await page.getByRole('heading', { name: 'Tauri 日历测试', exact: true }).waitFor();
  const thought = page.getByRole('textbox', { name: '番茄想法内容' });
  await thought.fill('WebView2 临时想法');
  await thought.press('Control+Enter');
  await page.getByText('WebView2 临时想法', { exact: true }).waitFor();

  await app.close();
  app = undefined;
  const db = new DatabaseSync(database);
  const end = Date.now() - 1000;
  db.prepare("UPDATE pomodoro_sessions SET phase_started_at=?, phase_ends_at=? WHERE status='focus_running'").run(end - 60_000, end);
  db.close();

  app = await openWebView(executable, profile);
  page = app.page;
  await page.getByText('已恢复上次的专注会话', { exact: true }).waitFor();
  await page.getByRole('button', { name: '查看专注总结', exact: true }).click();
  await page.getByRole('button', { name: '任务已完成', exact: true }).click();
  await page.getByRole('checkbox', { name: '撤销完成：Tauri 日历测试' }).waitFor();
  const finish = await read();
  assert.equal(finish.value.todayData.record.total_completed_pomodoros, 1);
  assert.equal(finish.value.todayData.thoughts[0].content, 'WebView2 临时想法');
});
