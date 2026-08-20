// Copies the built plugins into app/packages/plugins and verifies that everything the
// packaged Electron app needs at runtime is present before electron-builder runs.
//
// The previous `copyfiles --up 3 "../plugins/dist/**/*"` silently succeeded when the
// glob matched nothing, so a broken plugin build produced an installer without any
// plugin backend and the app failed to start (dbgate/dbgate#1300).

const fs = require('fs');
const path = require('path');

const appDir = path.resolve(__dirname, '..', 'app');
const pluginsDistDir = path.resolve(__dirname, '..', 'plugins', 'dist');
const targetDir = path.join(appDir, 'packages', 'plugins');

function fail(message) {
  console.error(`copyPackagedPlugins: ${message}`);
  process.exit(1);
}

if (!fs.existsSync(pluginsDistDir)) {
  fail(`${pluginsDistDir} does not exist, run "yarn plugins:copydist" first`);
}

const packageNames = fs.readdirSync(pluginsDistDir).filter(x => x.startsWith('dbgate-plugin-'));

if (packageNames.length === 0) {
  fail(`no plugins found in ${pluginsDistDir}, run "yarn plugins:copydist" first`);
}

fs.rmSync(targetDir, { recursive: true, force: true });
fs.mkdirSync(targetDir, { recursive: true });

for (const packageName of packageNames) {
  fs.cpSync(path.join(pluginsDistDir, packageName), path.join(targetDir, packageName), { recursive: true });

  // packagedPluginList / getPluginBackendPath resolve exactly these two files at runtime
  for (const required of ['package.json', path.join('dist', 'backend.js')]) {
    const file = path.join(targetDir, packageName, required);
    if (!fs.existsSync(file) || fs.statSync(file).size === 0) {
      fail(`${packageName} is missing ${required}`);
    }
  }
}

console.log(`copyPackagedPlugins: copied ${packageNames.length} plugins into ${targetDir}`);
