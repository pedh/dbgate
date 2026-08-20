global.DBGATE_PACKAGES = {
  'dbgate-tools': require('dbgate-tools'),
  'dbgate-sqltree': require('dbgate-sqltree'),
  'dbgate-datalib': require('dbgate-datalib'),
};

// When INTEGRATION_TEST_ENGINES limits the suite to engines which do not support a
// tested feature, the corresponding test.each table is empty. Jest throws on empty
// tables and on suites without any test; registering an explicitly skipped test
// instead keeps the semantics (no engine available to test) visible in CI logs.
function allowEmptyEach(eachFn, registerSkipped) {
  return table => {
    const rows = Array.isArray(table) ? table : [];
    if (rows.length === 0) {
      return (name, fn) => registerSkipped(name);
    }
    return eachFn(table);
  };
}
if (process.env.INTEGRATION_TEST_ENGINES) {
  test.each = allowEmptyEach(test.each.bind(test), name =>
    test.skip(`${name} [skipped: no applicable engine in INTEGRATION_TEST_ENGINES selection]`, () => {})
  );
  describe.each = allowEmptyEach(describe.each.bind(describe), name =>
    describe(name, () => {
      test.skip('[skipped: no applicable engine in INTEGRATION_TEST_ENGINES selection]', () => {});
    })
  );
}

const { prettyFactory } = require('pino-pretty');
const tmp = require('tmp');

const pretty = prettyFactory({
  colorize: true,
  translateTime: 'SYS:standard',
  ignore: 'pid,hostname',
});

global.console = {
  ...console,
  log: (...messages) => {
    try {
      const parsedMessage = JSON.parse(messages[0]);
      process.stdout.write(pretty(parsedMessage));
    } catch (error) {
      process.stdout.write(messages.join(' ') + '\n');
    }
  },
  debug: (...messages) => {
    process.stdout.write(messages.join(' ') + '\n');
  },
};

tmp.setGracefulCleanup();
