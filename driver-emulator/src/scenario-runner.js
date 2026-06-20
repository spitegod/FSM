/* eslint-disable no-console */
//
// Scenario Runner
// ---------------
// Тестовый набор сценариев клиента для ручной проверки реального Driver UI (заказы Vote).
//
// Запуск (без выбора сценария через меню/CLI — крутим набор по кругу):
//   node src/scenario-runner.js
//   npm run client
//
// Параметры:
//   - Водитель-тестер (его u_id или c_id) передаётся при запуске:
//       node src/scenario-runner.js --tester=<userId>
//       TESTER_USER_ID=<userId> node src/scenario-runner.js
//     либо config.clientSimulator.testerUserId
//   - Пауза между заказами (сек): config.clientSimulator.betweenOrdersSeconds
//   - Зацикливание: config.clientSimulator.loop (по умолчанию true)
//   - Набор/порядок сценариев: config.clientSimulator.scenarios (массив key)
//
const { readConfig, sleep, stringifyError } = require('./common');
const { ClientSimulator } = require('./client-simulator');

const SCENARIOS = [
  require('./scenarios/vote-selected'),
  require('./scenarios/vote-not-selected'),
  require('./scenarios/vote-auto-select'),
  require('./scenarios/vote-cancelled'),
  require('./scenarios/vote-new-round'),
  require('./scenarios/client-cancel-after-select'),
  require('./scenarios/no-show'),
];

const SCENARIO_BY_KEY = SCENARIOS.reduce((map, scenario) => {
  map[scenario.key] = scenario;
  return map;
}, {});

const args = process.argv.slice(2);

function getArgValue(name) {
  const direct = args.find(item => item.startsWith(`${name}=`));
  if (direct) return direct.slice(name.length + 1);
  const index = args.indexOf(name);
  if (index >= 0 && args[index + 1]) return args[index + 1];
  return null;
}

function getTesterUserId(config) {
  const fromArg = getArgValue('--tester') || getArgValue('--tester-user-id');
  const fromEnv = process.env.TESTER_USER_ID;
  const fromConfig = config.clientSimulator?.testerUserId;
  const value = fromArg || fromEnv || fromConfig || '';
  return String(value).trim() || null;
}

function selectScenarios(config) {
  const keys = config.clientSimulator?.scenarios;
  if (Array.isArray(keys) && keys.length) {
    const picked = keys.map(key => SCENARIO_BY_KEY[key]).filter(Boolean);
    const missing = keys.filter(key => !SCENARIO_BY_KEY[key]);
    if (missing.length) console.log(`[runner] неизвестные сценарии пропущены: ${missing.join(', ')}`);
    if (picked.length) return picked;
  }
  return SCENARIOS;
}

function log(message) {
  console.log(`[${new Date().toLocaleTimeString()}] [runner] ${message}`);
}

async function main() {
  const config = readConfig();
  const options = config.clientSimulator || {};
  const testerUserId = getTesterUserId(config);
  const betweenMs = Math.max(0, Number(options.betweenOrdersSeconds ?? 30)) * 1000;
  const loop = options.loop !== false;
  const scenarios = selectScenarios(config);
  const client = new ClientSimulator(config);

  log(`API: ${config.apiBase}`);
  log(`Водитель-тестер: ${testerUserId || '(не задан — будет выбран первый откликнувшийся)'}`);
  log(`Сценариев в наборе: ${scenarios.length}; пауза между заказами: ${betweenMs / 1000} сек; loop=${loop}`);

  let round = 0;
  do {
    round += 1;
    if (loop) log(`=== Круг ${round} ===`);

    for (let i = 0; i < scenarios.length; i += 1) {
      const scenario = scenarios[i];
      log(`▶ Сценарий: ${scenario.name} [${scenario.key}]`);
      try {
        await scenario.run({ client, config, testerUserId, log });
      } catch (error) {
        log(`✖ Сценарий "${scenario.name}" упал: ${stringifyError(error)}`);
      }

      const isLast = i === scenarios.length - 1;
      if (!isLast || loop) {
        log(`Пауза ${betweenMs / 1000} сек перед следующим заказом...`);
        await sleep(betweenMs);
      }
    }
  } while (loop);

  log('Набор сценариев завершён.');
}

main().catch(error => {
  console.error(`[runner] fatal: ${stringifyError(error)}`);
  process.exit(1);
});
