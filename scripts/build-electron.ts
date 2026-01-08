import { build } from 'esbuild';
import { rmSync, mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';

const outDir = 'dist-electron';
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

await build({
  entryPoints: ['electron/main.ts'],
  outfile: join(outDir, 'main.cjs'),
  platform: 'node',
  format: 'cjs',
  bundle: true,
  external: ['electron', 'electron-store'],
});

await build({
  entryPoints: ['electron/preload.ts'],
  outfile: join(outDir, 'preload.cjs'),
  platform: 'node',
  format: 'cjs',
  bundle: true,
  external: ['electron'],
});

writeFileSync(join(outDir, 'package.json'), JSON.stringify({ type: 'commonjs' }));



