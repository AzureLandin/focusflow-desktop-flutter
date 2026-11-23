import { build } from 'esbuild';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';

const test = process.argv.includes('test');
const frontend = process.argv.includes('frontend');
const output = frontend ? 'dist/frontend' : 'dist';
await mkdir(output, { recursive: true });
const options = { bundle: true, logLevel: 'warning', loader: { '.sql': 'text' } };
if (test) {
  await build({ ...options, platform: 'node', target: 'node24', format: 'cjs', entryPoints: ['tests/domain.test.ts'], outfile: 'dist/domain.test.cjs' });
} else {
  const licenses = [
    ['react', 'LICENSE'], ['react-dom', 'LICENSE'], ['scheduler', 'LICENSE'],
    ['date-fns', 'LICENSE.md'], ['zod', 'LICENSE'], ['lucide-react', 'LICENSE'],
  ];
  if (frontend) licenses.push(['@tauri-apps/api', 'LICENSE-MIT']);
  const notices = await Promise.all(licenses.map(async ([name, file]) =>
    `${name}\n\n${(await readFile(`node_modules/${name}/${file}`, 'utf8')).trim()}`));
  const index = await readFile('src/renderer/index.html', 'utf8');
  const tasks = [
    build({ ...options, platform: 'browser', target: frontend ? ['chrome110', 'safari15'] : 'chrome140', jsx: 'automatic', minify: true,
      entryPoints: [frontend ? 'src/platform/tauri-entry.ts' : 'src/renderer/index.tsx'], outfile: `${output}/renderer.js` }),
    writeFile(`${output}/index.html`, frontend ? index.replace(/^.*<meta http-equiv="Content-Security-Policy".*\r?\n/m, '') : index),
    copyFile('assets/icon.png', `${output}/icon.png`),
    copyFile('LICENSE', `${output}/LICENSE`),
    writeFile(`${output}/THIRD_PARTY_LICENSES.txt`, notices.join('\n\n' + '='.repeat(60) + '\n\n') + '\n'),
  ];
  if (!frontend) tasks.push(build({ ...options, platform: 'node', target: 'node24', format: 'cjs', external: ['electron'],
    outExtension: { '.js': '.cjs' }, outdir: output, entryPoints: { main: 'src/main/index.ts', preload: 'src/main/preload.ts' } }));
  await Promise.all(tasks);
}
