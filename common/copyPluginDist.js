// Copies a built plugin into plugins/dist/<packageName>, so that it can be picked up by
// app packaging (app/package.json "predist") and by packagedPluginsDir() at runtime.
//
// This replaces `yarn pack && dbgate-copydist`, which extracted the tarball
// asynchronously without ever awaiting the result or checking for errors: the process
// could exit before the extraction finished, leaving an empty or partial plugin
// directory while still reporting success. The packaged app then found no plugin
// backends and failed to start (dbgate/dbgate#1300). Windows was hit hardest, because
// file locking makes the extraction both slower and more likely to fail outright.

const fs = require('fs');
const path = require('path');

const pluginDir = process.cwd();
const manifestFile = path.join(pluginDir, 'package.json');

if (!fs.existsSync(manifestFile)) {
  console.error(`copyPluginDist: no package.json in ${pluginDir}`);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf-8'));
const packageName = manifest.name;

if (!packageName || !packageName.startsWith('dbgate-plugin-')) {
  console.error(`copyPluginDist: ${packageName} is not a dbgate plugin`);
  process.exit(1);
}

const targetDir = path.resolve(pluginDir, '..', 'dist', packageName);

// Files needed at runtime: the backend/frontend bundles (dist), the manifest and the
// readme + icon shown in the plugins UI.
const copiedEntries = ['package.json', 'README.md', ...(manifest.files || ['dist'])];

fs.rmSync(targetDir, { recursive: true, force: true });
fs.mkdirSync(targetDir, { recursive: true });

for (const entry of copiedEntries) {
  const source = path.join(pluginDir, entry);
  if (!fs.existsSync(source)) {
    continue;
  }
  fs.cpSync(source, path.join(targetDir, entry), { recursive: true });
}

// The whole point of this script is that a broken copy must not look like a success.
for (const required of ['package.json', path.join('dist', 'backend.js'), path.join('dist', 'frontend.js')]) {
  const file = path.join(targetDir, required);
  if (!fs.existsSync(file) || fs.statSync(file).size === 0) {
    console.error(`copyPluginDist: ${packageName} is missing ${required} after copy, build it first`);
    process.exit(1);
  }
}

console.log(`copyPluginDist: ${packageName} -> ${targetDir}`);
