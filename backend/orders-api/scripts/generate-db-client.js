const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const projectRoot = path.resolve(__dirname, '..');
const schemaPath = path.join(projectRoot, 'prisma', 'schema.prisma');

if (!fs.existsSync(schemaPath)) {
  console.log('[build] No prisma/schema.prisma found, skipping Prisma client generation.');
  process.exit(0);
}

const npxCmd = process.platform === 'win32' ? 'npx.cmd' : 'npx';
const result = spawnSync(npxCmd, ['prisma', 'generate', '--schema', schemaPath], {
  cwd: projectRoot,
  stdio: 'inherit',
  env: process.env,
});

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}
