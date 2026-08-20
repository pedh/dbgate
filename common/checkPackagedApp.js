// Verifies that a packaged DbGate installation really contains everything the app needs
// to start, most importantly the plugin backends. A build that silently lost the plugin
// dist files still produces a working-looking installer, but the app then fails on
// startup with "cannot find plugin module" (dbgate/dbgate#1300).
//
// Usage: node common/checkPackagedApp.js <resources-dir>
//   <resources-dir> is the "resources" directory of an installed / unpacked app,
//   ie. the directory containing app.asar.

const fs = require('fs');
const path = require('path');

const resourcesDir = process.argv[2];

if (!resourcesDir) {
  console.error('checkPackagedApp: usage: node common/checkPackagedApp.js <resources-dir>');
  process.exit(2);
}

const errors = [];

function fail(message) {
  errors.push(message);
  console.error(`FAIL ${message}`);
}

function ok(message) {
  console.log(`OK   ${message}`);
}

// Minimal asar reader: an asar file is a 16 byte pickle header, a JSON directory listing
// and then the concatenated file contents. Only the listing is needed here.
function readAsarListing(asarPath) {
  const fd = fs.openSync(asarPath, 'r');
  try {
    const sizeBuf = Buffer.alloc(16);
    fs.readSync(fd, sizeBuf, 0, 16, 0);
    const headerSize = sizeBuf.readUInt32LE(12);
    const headerBuf = Buffer.alloc(headerSize);
    fs.readSync(fd, headerBuf, 0, headerSize, 16);
    return JSON.parse(headerBuf.toString('utf-8'));
  } finally {
    fs.closeSync(fd);
  }
}

function asarEntry(listing, entryPath) {
  let node = listing;
  for (const part of entryPath.split('/')) {
    node = node?.files?.[part];
    if (!node) return null;
  }
  return node;
}

function asarChildren(listing, entryPath) {
  const node = entryPath ? asarEntry(listing, entryPath) : listing;
  return Object.keys(node?.files || {});
}

const asarPath = path.join(resourcesDir, 'app.asar');
const unpackedDir = path.join(resourcesDir, 'app.asar.unpacked');

if (!fs.existsSync(asarPath)) {
  console.error(`checkPackagedApp: ${asarPath} not found`);
  process.exit(2);
}

console.log(`checkPackagedApp: inspecting ${asarPath}`);
const listing = readAsarListing(asarPath);

// The API bundle resolves plugins relative to its own directory, so the layout inside
// the archive has to be exactly packages/plugins/<name>/dist/backend.js
for (const entry of ['src/electron.js', 'packages/api/dist/bundle.js', 'packages/web/public/index.html']) {
  if (asarEntry(listing, entry)) {
    ok(`${entry} present`);
  } else {
    fail(`${entry} missing from app.asar`);
  }
}

const pluginNames = asarChildren(listing, 'packages/plugins').filter(x => x.startsWith('dbgate-plugin-'));

if (pluginNames.length === 0) {
  fail('no dbgate-plugin-* directory in app.asar/packages/plugins');
} else {
  ok(`${pluginNames.length} plugins packaged: ${pluginNames.join(', ')}`);
}

for (const pluginName of pluginNames) {
  for (const required of ['dist/backend.js', 'dist/frontend.js', 'package.json']) {
    const entry = asarEntry(listing, `packages/plugins/${pluginName}/${required}`);
    if (!entry) {
      fail(`${pluginName}/${required} missing from app.asar`);
    } else if (!entry.size) {
      fail(`${pluginName}/${required} is empty in app.asar`);
    }
  }
}

if (pluginNames.length > 0 && errors.length === 0) {
  ok('every packaged plugin has a non-empty backend and frontend bundle');
}

// native modules are asarUnpack-ed, so they must exist as real files on disk
if (fs.existsSync(unpackedDir)) {
  ok(`app.asar.unpacked present`);
} else {
  console.log(`NOTE app.asar.unpacked not present`);
}

if (errors.length > 0) {
  console.error(`checkPackagedApp: ${errors.length} problem(s) found`);
  process.exit(1);
}

console.log('checkPackagedApp: packaged app structure is valid');
