/* eslint-disable no-console */
//
// Сценарий 3 — Vote Auto Select
//
//   Создать Vote заказ -> подождать отклики -> ничего не делать.
//   Дальнейшее поведение определяется сервером (авто-выбор / таймаут).
//
const CASE_NAME = 'Vote Auto Select';

async function run({ client, testerUserId, log }) {
  const orderId = await client.createVoteOrder({ caseName: CASE_NAME });

  log('Ожидаем отклики водителей...');
  const candidates = await client.waitForResponses(orderId, { min: 1, includeUserId: testerUserId });

  log(`Откликов: ${candidates.length}. Клиент намеренно ничего не выбирает — дальнейшее поведение за сервером.`);
  log(`Наблюдайте Driver UI (order ${orderId}): авто-выбор или завершение голосования по таймауту.`);
}

module.exports = { key: 'vote-auto-select', name: CASE_NAME, run };
