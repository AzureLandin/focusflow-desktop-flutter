import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { _electron as electron } from 'playwright-core';

const require = createRequire(import.meta.url);
const packaged = process.env.FOCUSFLOW_E2E_EXECUTABLE;
const executablePath = packaged ? resolve(packaged) : require('electron');
const dateKey = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
const minute = 60_000;

test('FocusFlow desktop acceptance across interruption, timer recovery and day rollover', { timeout: 180_000 }, async (t) => {
  const profile = process.env.FOCUSFLOW_E2E_PROFILE || await mkdtemp(join(tmpdir(), 'focusflow-ui-'));
  const capture = process.env.FOCUSFLOW_E2E_SCREENSHOTS;
  if (capture) await mkdir(capture, { recursive: true });
  let app;
  let page;
  const errors = [];
  t.after(async () => {
    await app?.close();
    if (!process.env.FOCUSFLOW_E2E_PROFILE) await rm(profile, { recursive: true, force: true, maxRetries: 4, retryDelay: 250 });
  });
  const morning = new Date();
  morning.setHours(10, 0, 0, 0);
  const tomorrow = new Date(morning);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const todayKey = dateKey(morning);
  const tomorrowKey = dateKey(tomorrow);
  async function launch(now) {
    app = await electron.launch({ executablePath, args: [...(packaged ? [] : [resolve('.')]), `--user-data-dir=${profile}`] });
    await app.evaluate((_electron, time) => { Date.now = () => time; }, now);
    page = await app.firstWindow();
    page.setDefaultTimeout(7000);
    page.on('pageerror', (error) => errors.push(error.message));
  }
  const heading = (text) => page.getByRole('heading', { name: text, exact: true });
  const button = (text) => page.getByRole('button', { name: text, exact: true });
  const click = (text) => button(text).click();
  const read = () => page.evaluate(async () => {
    const result = await window.focusflow.read({});
    if (!result.ok) throw new Error(result.message);
    return result.value;
  });
  const clock = (now) => app.evaluate((_electron, time) => { Date.now = () => time; }, now);
  const resize = (width, height) => app.evaluate(({ BrowserWindow }, dimensions) => {
    BrowserWindow.getAllWindows()[0].setContentSize(dimensions.width, dimensions.height);
  }, { width, height });
  const fits = () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);
  const shot = (name) => capture && page.screenshot({ path: join(capture, `${name}.png`), animations: 'disabled' });
  const saveTask = async (name, { plan, description } = {}) => {
    await page.getByLabel('任务名称').fill(name);
    if (description) await page.getByLabel(/描述/).fill(description);
    if (plan) {
      await page.getByRole('checkbox', { name: '启用番茄时钟' }).check();
      await page.getByLabel('计划番茄数').fill(String(plan));
    }
    await click('保存任务');
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
  };

  await launch(+morning);
  await heading('今日待办').waitFor();
  assert.match(await page.getByRole('heading', { level: 1 }).innerText(), /今日待办/);
  assert.equal((await read()).settings.focusMinutes, 25);
  assert.equal((await read()).settings.shortMinutes, 5);
  await shot('01-today-empty');
  await click('设置');
  await page.getByRole('checkbox', { name: /提示音/ }).uncheck();
  await page.getByRole('checkbox', { name: /系统通知/ }).uncheck();
  await click('保存设置');
  await page.getByText('设置已保存', { exact: true }).waitFor();
  await click('今日待办');
  await click('详细添加');
  await saveTask('整理研究笔记', { plan: 2, description: '把参考资料和要点归在一起' });
  const quickInput = page.getByRole('textbox', { name: '快速添加任务' });
  for (const title of ['明早再处理', '临时任务']) {
    await quickInput.fill(title);
    await quickInput.press('Enter');
    await page.getByText(title, { exact: true }).waitFor();
  }
  await click('上移：明早再处理');
  assert.equal((await read()).todayData.tasks[0].title, '明早再处理');
  await page.getByRole('checkbox', { name: '完成：临时任务' }).click();
  await page.getByRole('checkbox', { name: '撤销完成：临时任务' }).click();
  await click('删除：临时任务');
  await click('确认删除');
  await page.getByText('临时任务', { exact: true }).waitFor({ state: 'hidden' });
  await click('编辑：明早再处理');
  await saveTask('稍后再处理');
  const toggle = page.getByRole('switch', { name: '番茄时钟：稍后再处理' });
  await toggle.click();
  await page.waitForFunction(() => document.querySelector('[aria-label="番茄时钟：稍后再处理"]')?.getAttribute('aria-checked') === 'true');
  await toggle.click();
  await page.waitForFunction(() => document.querySelector('[aria-label="番茄时钟：稍后再处理"]')?.getAttribute('aria-checked') === 'false');
  await shot('02-today-tasks');
  await click('开始专注');
  assert.equal(await page.getByLabel('本次计划番茄数').inputValue(), '2');
  await click('开始计时');
  await heading('整理研究笔记').waitFor();
  assert.equal(await page.getByRole('navigation', { name: '主导航' }).count(), 0);
  const thought = page.getByRole('textbox', { name: '番茄想法内容' });
  await thought.fill('回头核对第二篇论文的图表');
  await thought.press('Control+Enter');
  await page.getByText('回头核对第二篇论文的图表', { exact: true }).waitFor();
  await shot('03-focus');
  await resize(800, 590);
  await click('番茄想法（1）');
  await page.getByText('回头核对第二篇论文的图表', { exact: true }).waitFor();
  assert.equal(await fits(), true);
  await click('番茄想法（1）');
  await resize(1220, 680);
  await click('打断番茄');
  assert.equal(await button('确认打断').isDisabled(), true);
  await page.getByRole('radio', { name: '接到电话或消息' }).check();
  await click('确认打断');
  await heading('今日待办').waitFor();
  const interrupted = (await read()).todayData;
  assert.equal(interrupted.record.total_completed_pomodoros, 0);
  assert.equal(interrupted.activity[0].reason, '接到电话或消息');
  assert.equal(interrupted.thoughts.length, 1);
  await click('开始专注');
  await click('开始计时');
  await heading('整理研究笔记').waitFor();
  await app.close();
  app = undefined;
  await launch(+morning + 25 * minute);
  await page.getByText('已恢复上次的专注会话', { exact: true }).waitFor();
  await click('开始短休息');
  await page.getByText('休息计时中', { exact: true }).waitFor();
  await clock(+morning + 30 * minute);
  await click('开始下一个番茄');
  await page.getByText('专注计时中', { exact: true }).waitFor();
  await clock(+morning + 55 * minute);
  await click('查看专注总结');
  await page.getByText('这项任务完成了吗？', { exact: true }).waitFor();
  await click('任务已完成');
  await page.getByRole('checkbox', { name: '撤销完成：整理研究笔记' }).waitFor();
  assert.equal((await read()).todayData.record.total_completed_pomodoros, 2);
  await click('日历');
  await heading('日历').waitFor();
  await click('下个月');
  await click('上个月');
  await click('回到今天');
  await page.getByRole('button', { name: new RegExp(`^${tomorrowKey}`) }).click();
  await click('为这天添加任务');
  await saveTask('明日任务');
  await page.getByText('明日任务', { exact: true }).waitFor();
  await shot('04-calendar');
  assert.equal((await read()).todayData.tasks.some(({ title }) => title === '明日任务'), false);

  await app.close();
  app = undefined;
  await launch(+tomorrow);
  await heading('今日待办').waitFor();
  await page.getByText('明日任务', { exact: true }).waitFor();
  assert.equal((await read()).todayData.tasks.filter(({ title }) => title === '明日任务').length, 1);
  await click('日历');
  await page.getByRole('button', { name: new RegExp(`^${todayKey}`) }).click();
  await page.getByText('历史记录', { exact: true }).waitFor();
  const historic = page.getByRole('complementary', { name: '日期详情' });
  await historic.getByText('稍后再处理', { exact: true }).waitFor();
  assert.ok(await historic.getByText('未完成', { exact: true }).count() > 0);
  await historic.getByText(/专注记录/).click();
  await historic.getByText(/接到电话或消息/).waitFor();
  await click('番茄想法（1）');
  await page.getByText('回头核对第二篇论文的图表', { exact: true }).waitFor();
  await click('关闭');

  await click('今日待办');
  await click('快速开始专注');
  await page.getByLabel('这次想专注做什么？').fill('快速整理');
  await click('开始计时');
  await click('打断番茄');
  await page.getByRole('radio', { name: '临时有事' }).check();
  await click('确认打断');
  await heading('将专注事项加入今日待办？').waitFor();
  await click('加入今日待办');
  assert.equal((await read()).todayData.tasks.find(({ title }) => title === '快速整理')?.completed_pomodoros, 0);
  await click('设置');
  for (const theme of ['dark', 'light', 'system']) {
    await page.getByRole('combobox', { name: '主题' }).selectOption(theme);
    await click('保存设置');
    await page.waitForFunction((value) => document.documentElement.dataset.theme === value, theme);
  }
  const backupPath = join(profile, 'acceptance-backup.json');
  await app.evaluate(({ dialog }, path) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: path });
    dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [path] });
    dialog.showMessageBox = async () => ({ response: 1, checkboxChecked: false });
  }, backupPath);
  await click('导出 JSON 备份');
  await page.getByText('备份已导出', { exact: true }).waitFor();
  assert.equal(JSON.parse(await readFile(backupPath, 'utf8')).format, 'focusflow-backup');
  await click('恢复 JSON 备份');
  await page.getByText('备份已恢复', { exact: true }).waitFor();
  assert.equal((await read()).todayData.tasks.length, 2);

  for (const [width, height] of [[960, 640], [800, 590]]) {
    await resize(width, height);
    for (const title of ['日历', '设置', '今日待办']) {
      await click(title);
      await heading(title).waitFor();
      assert.equal(await fits(), true, `${title}, ${width}`);
    }
  }
  await shot('05-compact-today');
  assert.deepEqual(errors, []);
});
