const fs = require('fs');
const path = require('path');
const volatilePackages = require('./common/volatilePackages');

function adjustFile(file, isApp = false) {
  const json = JSON.parse(fs.readFileSync(file, { encoding: 'utf-8' }));

  function processPackageFile(packageFile) {
    const pluginJson = JSON.parse(fs.readFileSync(packageFile, { encoding: 'utf-8' }));
    for (const depkey of ['dependencies', 'optionalDependencies']) {
      for (const dependency of Object.keys(pluginJson[depkey] || {})) {
        if (!volatilePackages.includes(dependency)) {
          // add only voletile packages
          continue;
        }
        if (!json[depkey]) {
          json[depkey] = {};
        }
        if (json[depkey][dependency]) {
          if (json[depkey][dependency] != pluginJson[depkey][dependency]) {
            console.log(`Dependency ${dependency} in ${packageFile} is different from ${file}`);
          }
          continue;
        }
        json[depkey][dependency] = pluginJson[depkey][dependency];
      }
    }
  }

  for (const packageName of fs.readdirSync('plugins')) {
    if (!packageName.startsWith('dbgate-plugin-')) continue;
    processPackageFile(path.join('plugins', packageName, 'package.json'));
  }

  if (isApp) {
    // add volatile dependencies from api to app
    processPackageFile(path.join('packages', 'api', 'package.json'));
  }

  if (process.platform != 'win32') {
    delete json.optionalDependencies.msnodesqlv8;
  }

  if (isApp && json.build?.mac && !process.env.APPLE_ID) {
    // without Apple credentials (e.g. fork builds) notarization cannot run
    json.build.mac.notarize = false;
  }

  if (isApp && json.build?.mac && !process.env.CSC_LINK) {
    // without a signing certificate (e.g. fork builds) skip code signing entirely
    json.build.mac.identity = null;
  }

  if (isApp && Array.isArray(json.build?.linux?.target) && !process.env.SNAPCRAFT_STORE_CREDENTIALS) {
    // without snapcraft credentials (e.g. fork builds) the snap target cannot be published
    json.build.linux.target = json.build.linux.target.filter(x => x !== 'snap');
  }

  if (isApp && Array.isArray(json.build?.win?.target)) {
    // the windows-latest runner ships Visual Studio 2026, whose MSBuild cannot
    // provide the v143 ARM64 cross build tools - the better-sqlite3 native rebuild
    // for arm64 fails, so build x64 installers/zips only
    json.build.win.target = json.build.win.target.map(t => ({ ...t, arch: ['x64'] }));
  }

  if (process.argv.includes('--community')) {
    delete json.optionalDependencies['mongodb-client-encryption'];
    delete json.dependencies['@mongosh/service-provider-node-driver'];
    delete json.dependencies['@mongosh/browser-runtime-electron'];
  }

  if (isApp && process.argv.includes('--premium')) {
    json.build.win.target = [
      {
        target: 'nsis',
        arch: ['x64'],
      },
    ];
    json.build.linux.target = [
      {
        target: 'AppImage',
        arch: ['x64'],
      },
    ];
    json.name = 'dbgate-premium';
    json.build.artifactName = 'dbgate-premium-${version}-${os}_${arch}.${ext}';
    json.build.appId = 'org.dbgate.premium';
    json.build.productName = 'DbGate Premium';
  }

  fs.writeFileSync(file, JSON.stringify(json, null, 2), 'utf-8');
}

adjustFile('packages/api/package.json');
adjustFile('app/package.json', true);

fs.writeFileSync('common/useBundleExternals.js', "module.exports = 'true';", 'utf-8');
