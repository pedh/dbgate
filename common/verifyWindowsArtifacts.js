// Verifies that the packaged Electron app (app.asar) contains the API bundle,
// the web frontend and the dist files of all packaged plugins. This catches the
// failure mode of dbgate/dbgate#1300 (build without plugins, app fails to start).
// Usage: node common/verifyWindowsArtifacts.js <path-to-app.asar> <repo-root>
const fs = require('fs');
const path = require('path');

function fail(msg) {
  console.error(`VERIFY FAIL: ${msg}`);
  process.exit(1);
}

// Minimal asar header parser (same on-disk layout used by @electron/asar):
// bytes 0-3:   UInt32LE = 4 (header-size pickle payload size)
// bytes 4-7:   UInt32LE = total size of the remaining header pickle chain
// bytes 8-11:  UInt32LE = 4
// bytes 12-15: UInt32LE = length of the header JSON string
// bytes 16..:  header JSON string, padded to 4-byte boundary
function readAsarHeader(asarPath) {
  const fd = fs.openSync(asarPath, 'r');
  try {
    const sizeBuf = Buffer.alloc(16);
    fs.readSync(fd, sizeBuf, 0, 16, 0);
    const headerStringSize = sizeBuf.readUInt32LE(12);
    const jsonBuf = Buffer.alloc(headerStringSize);
    fs.readSync(fd, jsonBuf, 0, headerStringSize, 16);
    return JSON.parse(jsonBuf.toString('utf-8'));
  } finally {
    fs.closeSync(fd);
  }
}

function collectFiles(node, prefix, result) {
  for (const [name, child] of Object.entries(node.files || {})) {
    const childPath = prefix ? `${prefix}/${name}` : name;
    if (child.files) {
      collectFiles(child, childPath, result);
    } else {
      result.push(childPath);
    }
  }
  return result;
}

const asarPath = process.argv[2];
const repoRoot = process.argv[3] || '.';

if (!asarPath || !fs.existsSync(asarPath)) {
  fail(`asar not found: ${asarPath}`);
}

const header = readAsarHeader(asarPath);
const files = collectFiles(header, '', []);
console.log(`asar ${asarPath}: ${files.length} files`);

const errors = [];

const requiredFiles = ['packages/api/dist/bundle.js', 'packages/web/public/index.html'];
for (const required of requiredFiles) {
  if (!files.includes(required)) {
    errors.push(`missing required file in asar: ${required}`);
  }
}

const expectedPlugins = fs
  .readdirSync(path.join(repoRoot, 'plugins'))
  .filter(name => name.startsWith('dbgate-plugin-'));

if (expectedPlugins.length === 0) {
  fail(`no plugins found in ${path.join(repoRoot, 'plugins')} - wrong repo root argument?`);
}

for (const plugin of expectedPlugins) {
  const backend = `packages/plugins/${plugin}/dist/backend.js`;
  const frontend = `packages/plugins/${plugin}/dist/frontend.js`;
  const manifest = `packages/plugins/${plugin}/package.json`;
  for (const required of [backend, frontend, manifest]) {
    if (!files.includes(required)) {
      errors.push(`missing plugin file in asar: ${required}`);
    }
  }
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(`VERIFY FAIL: ${error}`);
  }
  process.exit(1);
}

console.log(
  `VERIFY OK: bundle, frontend and dist files of all ${expectedPlugins.length} plugins are present in the asar`
);
