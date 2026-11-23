import { build } from 'esbuild';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';

const test = process.argv.includes('test');
await mkdir('dist', { recursive: true });
const options = { bundle: true, logLevel: 'warning', loader: { '.sql': 'text' } };
if (test) {
  await build({ ...options, platform: 'node', target: 'node24', format: 'cjs', entryPoints: ['tests/domain.test.ts'], outfile: 'dist/domain.test.cjs' });
} else {
  const licenses = [
    ['react', 'LICENSE'], ['react-dom', 'LICENSE'], ['scheduler', 'LICENSE'],
    ['date-fns', 'LICENSE.md'], ['zod', 'LICENSE'], ['lucide-react', 'LICENSE'],
  ];
  const notices = await Promise.all(licenses.map(async ([name, file]) =>
    `${name}\n\n${(await readFile(`node_modules/${name}/${file}`, 'utf8')).trim()}`));
  await Promise.all([
    build({ ...options, platform: 'node', target: 'node24', format: 'cjs', external: ['electron'],
      outExtension: { '.js': '.cjs' }, outdir: 'dist', entryPoints: { main: 'src/main/index.ts', preload: 'src/main/preload.ts' } }),
    build({ ...options, platform: 'browser', target: 'chrome140', jsx: 'automatic', minify: true,
      entryPoints: ['src/renderer/index.tsx'], outfile: 'dist/renderer.js' }),
    copyFile('src/renderer/index.html', 'dist/index.html'),
    copyFile('assets/icon.png', 'dist/icon.png'),
    writeFile('dist/THIRD_PARTY_LICENSES.txt', notices.join('\n\n' + '='.repeat(60) + '\n\n') + '\n'),
  ]);
}
