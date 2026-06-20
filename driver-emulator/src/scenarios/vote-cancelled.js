/* eslint-disable no-console */
//
// Сценарий 4 — Vote Cancel During Voting
//
//   Создать Vote заказ -> подождать отклики -> отменить заказ.
//
// Ожидаемая реакция Driver UI: заказ исчезает / помечается отменённым во время голосования.
//
const CASE_NAME = 'Vote Cancel During Voting';

async function run({ client, testerUserId, log }) {
  const orderId = await client.createVoteOrder({ caseName: CASE_NAME });

  log('Ожидаем отклики водителей...');
  await client.waitForResponses(orderId, { min: 1, includeUserId: testerUserId });

  await client.cancelOrder(orderId, 'client cancel during voting');
  log(`Готово. Проверьте Driver UI (order ${orderId}): заказ должен быть отменён во время голосования.`);
}

module.exports = { key: 'vote-cancelled', name: CASE_NAME, run };
