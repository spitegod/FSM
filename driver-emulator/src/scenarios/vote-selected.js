/* eslint-disable no-console */
//
// Сценарий 1 — Vote Driver Selected
//
//   Создать Vote заказ -> подождать отклики -> выбрать ОСНОВНОГО водителя (тестера) -> завершить.
//
// Ожидаемая реакция Driver UI тестера:
//   Новый заказ -> Голосование -> Назначен исполнителем
//
const CASE_NAME = 'Vote Driver Selected';

async function run({ client, testerUserId, log }) {
  const orderId = await client.createVoteOrder({ caseName: CASE_NAME });

  log('Ожидаем отклики водителей (откликнитесь в реальном Driver UI)...');
  const candidates = await client.waitForResponses(orderId, { min: 1, includeUserId: testerUserId });

  const target = client.resolveTester(candidates, testerUserId);
  if (!target) {
    log(`Водитель-тестер (${testerUserId || 'не задан'}) ещё не откликнулся — выбор не сделан. Откликнитесь в Driver UI и перезапустите кейс.`);
    return;
  }

  await client.selectDriver(orderId, target);
  log(`Готово. Проверьте Driver UI: должно быть "Назначен исполнителем" (order ${orderId}, водитель ${target}).`);
}

module.exports = { key: 'vote-selected', name: CASE_NAME, run };
