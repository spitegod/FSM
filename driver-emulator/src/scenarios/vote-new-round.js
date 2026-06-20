/* eslint-disable no-console */
//
// Сценарий 5 — Vote New Round
//
//   Создать Vote заказ -> подождать отклики -> выбрать другого водителя ->
//   сымитировать отмену выбранного водителя -> вернуть заказ в голосование.
//
// Ожидаемая реакция Driver UI: после release заказ снова в состоянии голосования.
//
const CASE_NAME = 'Vote New Round';

async function run({ client, testerUserId, log }) {
  const orderId = await client.createVoteOrder({ caseName: CASE_NAME });

  log('Ожидаем отклики водителей...');
  const candidates = await client.waitForResponses(orderId, { min: 1, includeUserId: testerUserId });

  // Выбираем "другого" водителя, если он есть; иначе — любого откликнувшегося.
  const target = client.resolveOther(candidates, testerUserId) || client.resolveTester(candidates, testerUserId);
  if (!target) {
    log('Нет откликнувшихся водителей — выбирать некого.');
    return;
  }

  await client.selectDriver(orderId, target);
  log(`Водитель ${target} выбран. Пауза перед "отменой" выбранного водителя...`);
  await client.wait(5000);

  // Имитируем отмену выбранного водителя -> возвращаем заказ в голосование.
  await client.clearSelection(orderId);
  log(`Готово. Проверьте Driver UI (order ${orderId}): заказ должен вернуться в голосование (новый раунд).`);
}

module.exports = { key: 'vote-new-round', name: CASE_NAME, run };
