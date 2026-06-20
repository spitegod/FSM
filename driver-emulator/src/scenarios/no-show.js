/* eslint-disable no-console */
//
// Сценарий 7 — No Show
//
//   Создать Vote заказ -> выбрать водителя -> дождаться прибытия -> сымитировать отсутствие клиента.
//
// ВНИМАНИЕ: по договорённости шаг "отсутствие клиента" пока ОСТАВЛЕН (явного backend-API
// "неявки" нет). Сейчас сценарий доводит заказ до назначения водителя и подсказывает тестеру,
// что дальше неявку нужно проверять вручную на реальном Driver UI. Логику можно дополнить позже.
//
const CASE_NAME = 'No Show';

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
  log(`Водитель ${target} назначен (order ${orderId}).`);
  log('Шаг "отсутствие клиента" пока оставлен — проверьте flow неявки вручную на реальном Driver UI.');
}

module.exports = { key: 'no-show', name: CASE_NAME, run };
