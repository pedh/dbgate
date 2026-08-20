// Startup smoke test for the packaged Electron app, enabled with DBGATE_SMOKE_TEST=1.
//
// The renderer only sends 'app-started' once the API answered and the plugin list was
// loaded, so reaching that point already proves the packaged app is not broken. On top of
// that every packaged plugin backend is required from its packaged location, which is
// exactly what failed in dbgate/dbgate#1300 - the app started but no plugin could be
// loaded because the plugin dist files never made it into the package.
//
// A packaged Windows app is a GUI binary and has no console attached, so the result is
// also written to DBGATE_SMOKE_TEST_RESULT in addition to the process exit code.

const fs = require('fs');
const path = require('path');

const TIMEOUT_MS = Number(process.env.DBGATE_SMOKE_TEST_TIMEOUT || 120000);

function writeResult(result) {
  const file = process.env.DBGATE_SMOKE_TEST_RESULT;
  if (!file) return;
  try {
    fs.writeFileSync(file, JSON.stringify(result, null, 2), 'utf-8');
  } catch (err) {
    console.error(`SMOKE_TEST could not write result to ${file}: ${err.message}`);
  }
}

function loadPackagedPlugins() {
  const pluginsDir = path.resolve(__dirname, '../packages/plugins');
  if (!fs.existsSync(pluginsDir)) {
    throw new Error(`packaged plugins directory ${pluginsDir} does not exist`);
  }

  const packageNames = fs.readdirSync(pluginsDir).filter(x => x.startsWith('dbgate-plugin-'));
  if (packageNames.length == 0) {
    throw new Error(`no plugin found in ${pluginsDir}`);
  }

  for (const packageName of packageNames) {
    const backendPath = path.join(pluginsDir, packageName, 'dist', 'backend.js');
    const plugin = require(backendPath);
    const resolved = plugin.__esModule ? plugin.default : plugin;
    if (!resolved || (!resolved.drivers && !resolved.packageName)) {
      throw new Error(`plugin ${packageName} loaded from ${backendPath} exports no driver`);
    }
  }

  return packageNames;
}

function startSmokeTest(app) {
  const timer = setTimeout(() => {
    console.error(`SMOKE_TEST_FAILED app did not start within ${TIMEOUT_MS} ms`);
    writeResult({ ok: false, error: `app did not start within ${TIMEOUT_MS} ms` });
    app.exit(1);
  }, TIMEOUT_MS);

  return () => {
    clearTimeout(timer);
    try {
      const plugins = loadPackagedPlugins();
      console.log(`SMOKE_TEST_OK app started and loaded ${plugins.length} plugin backends`);
      writeResult({ ok: true, plugins });
      app.exit(0);
    } catch (err) {
      console.error(`SMOKE_TEST_FAILED ${err.message}`);
      writeResult({ ok: false, error: err.message });
      app.exit(1);
    }
  };
}

module.exports = { startSmokeTest };
