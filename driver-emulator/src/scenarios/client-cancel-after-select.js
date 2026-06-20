/* eslint-disable no-console */
//
// Сценарий 6 — Client Cancel After Selection
//
//   Создать Vote заказ -> выбрать водителя -> подождать 30 секунд -> отменить заказ.
//
// Ожидаемая реакция Driver UI: водитель назначен исполнителем, затем заказ отменён клиентом.
//
const CASE_NAME = 'Client Cancel After Selection';
const WAIT_BEFORE_CANCEL_MS = 30000;

async function run({ client, testerUserId, log }) {
  const orderId = await client.createVoteOrder({ caseName: CASE_NAME });

  log('Ожидаем отклики водителей...');
  const candidates = await client.waitForResponses(orderId, { min: 1, includeUserId: testerUserId });

  const target = client.resolveTester(candidates, testerUserId);
  if (!target) {
    log(`Водитель-тестер (${testerUserId || 'не задан'}) не откликнулся — выбор не сделан.`);
    return;
  }

  await client.selectDriver(orderId, target);
  log(`Водитель ${target} назначен. Ждём ${WAIT_BEFORE_CANCEL_MS / 1000} сек перед отменой...`);
  await client.wait(WAIT_BEFORE_CANCEL_MS);

  await client.cancelOrder(orderId, 'client cancel after selection');
  log(`Готово. Проверьте Driver UI (order ${orderId}): заказ должен быть отменён после назначения.`);
}

module.exports = { key: 'client-cancel-after-select', name: CASE_NAME, run };
