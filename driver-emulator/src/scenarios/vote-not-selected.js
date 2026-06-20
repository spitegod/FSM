/* eslint-disable no-console */
//
// Сценарий 2 — Vote Other Driver Selected
//
//   Создать Vote заказ -> подождать отклики -> выбрать ДРУГОГО водителя (не тестера).
//
// Ожидаемая реакция Driver UI тестера:
//   Новый заказ -> Голосование -> Не выбран
//
// Нужно минимум два отклика: сам тестер и ещё один водитель (например бот из simulator.js).
//
const CASE_NAME = 'Vote Other Driver Selected';

async function run({ client, testerUserId, log }) {
  const orderId = await client.createVoteOrder({ caseName: CASE_NAME });

  log('Ожидаем отклики минимум двух водителей (тестер + другой)...');
  const candidates = await client.waitForResponses(orderId, { min: 2, includeUserId: testerUserId });

  const other = client.resolveOther(candidates, testerUserId);
  if (!other) {
    log('Нет второго (другого) водителя в откликах — выбрать "другого" не из кого. Запустите бота-водителя или дождитесь ещё одного отклика.');
    return;
  }

  await client.selectDriver(orderId, other);
  log(`Готово. Проверьте Driver UI тестера: должно быть "Не выбран" (исполнителем выбран водитель ${other}, order ${orderId}).`);
}

module.exports = { key: 'vote-not-selected', name: CASE_NAME, run };
