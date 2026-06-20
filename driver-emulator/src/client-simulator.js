/* eslint-disable no-console */
//
// Client Simulator
// ----------------
// Эмулирует действия клиента (пассажира) для РУЧНОГО тестирования реального Driver UI
// на заказах типа Vote. Работает напрямую с реальным backend:
//
//   - создаёт Vote-заказы через существующий order-generator.js;
//   - выбирает победителя реальным backend-вызовом (set_performer) — именно это
//     заставляет интерфейс водителя показать "Назначен исполнителем";
//   - дублирует выбор в data/passenger-choices.json — локальный канал для
//     ботов-водителей из simulator.js (как это делает веб-клиент);
//   - умеет отменять заказ и возвращать его в голосование (release performer).
//
// Минимальный API (по ТЗ):
//   createVoteOrder()
//   selectDriver(orderId, userId)
//   clearSelection(orderId)
//   wait(ms)
//
const {
  readConfig,
  readJson,
  writeJson,
  sleep,
  resolveProjectPath,
  apiPostUrlEncoded,
  isBackendError,
  normalizeErrorMessage,
  stringifyError,
} = require('./common');
const {
  getGeneratorConfig,
  getClients,
  loginSession,
  createOrder,
} = require('./order-generator');

const PASSENGER_CHOICES_FILE = 'data/passenger-choices.json';

const ACTIONS = {
  SET_CONFIRM_STATE: 'set_confirm_state',
  SET_PERFORMER: 'set_performer',
  SET_CANCEL_STATE: 'set_cancel_state',
};

// Состояния водителя в заказе (как в simulator.js / web Driver UI).
const DRIVER_STATES = {
  CONSIDERING: 1, // кандидат (откликнулся, ждёт выбора клиента)
  CANCELED: 2,
  PERFORMER: 3, // выбран исполнителем
  ARRIVED: 4,
  STARTED: 5,
  FINISHED: 6,
};

function toState(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

class ClientSimulator {
  constructor(config = null) {
    this.config = config || readConfig();
    this.generator = getGeneratorConfig(this.config);
    this.clients = getClients(this.config, this.generator);
    this.options = this.config.clientSimulator || {};
    this.session = null;
    this.client = null;
    // Запоминаем выбранного водителя по заказу, чтобы clearSelection() мог его "отпустить".
    this.selectedByOrder = new Map();
  }

  log(message) {
    console.log(`[${new Date().toLocaleTimeString()}] [client] ${message}`);
  }

  get pollIntervalMs() {
    return Math.max(500, Number(this.options.pollIntervalMs || 2000));
  }

  get responseTimeoutMs() {
    return Math.max(5000, Number(this.options.responseTimeoutMs || 60000));
  }

  async ensureSession() {
    if (this.session) return this.session;
    if (!this.clients.length) {
      throw new Error('Нет аккаунтов клиента. Заполните config.orderGenerator.clients[] или включите useManagerAsClient.');
    }
    this.client = this.clients[0];
    this.session = await loginSession(this.config.apiBase, this.client, this.client.name || this.client.login || 'client');
    this.log(`сессия клиента: ${this.client.name || this.client.login}`);
    return this.session;
  }

  authFields(extra = {}) {
    return {
      token: this.session.token,
      u_hash: this.session.u_hash,
      ...extra,
    };
  }

  // ===================== passenger-choices.json (зеркало для ботов) =====================

  choicesPath() {
    return resolveProjectPath(PASSENGER_CHOICES_FILE);
  }

  readChoices() {
    const data = readJson(this.choicesPath(), {});
    return data && typeof data === 'object' && !Array.isArray(data) ? data : {};
  }

  writeChoice(orderId, userId) {
    const data = this.readChoices();
    data[String(orderId)] = String(userId);
    writeJson(this.choicesPath(), data);
  }

  removeChoice(orderId) {
    const data = this.readChoices();
    if (data[String(orderId)] === undefined) return;
    delete data[String(orderId)];
    writeJson(this.choicesPath(), data);
  }

  // ===================== Минимальный API =====================

  // Создаёт Vote-заказ и подтверждает его (как делает веб-клиент для b_voting).
  // caseName -> попадает в комментарий заказа ("[CASE] ..."), чтобы тестер видел,
  // какой сценарий сейчас проверяется.
  async createVoteOrder({ caseName } = {}) {
    await this.ensureSession();
    const overrides = caseName ? { comment: `[CASE] ${caseName}` } : {};
    const result = await createOrder(this.config, this.generator, this.client, 0, 'voting', overrides);
    const orderId = result?.orderId;
    if (!orderId) {
      throw new Error('createVoteOrder: backend не вернул orderId');
    }

    // Vote-заказ должен быть подтверждён, иначе он не уходит в голосование.
    try {
      const confirm = await apiPostUrlEncoded(this.config.apiBase, `/drive/get/${orderId}`, this.authFields({
        action: ACTIONS.SET_CONFIRM_STATE,
      }));
      if (isBackendError(confirm)) {
        this.log(`order ${orderId}: confirm пропущен: ${normalizeErrorMessage(confirm)}`);
      }
    } catch (error) {
      this.log(`order ${orderId}: confirm пропущен: ${stringifyError(error)}`);
    }

    this.log(`Vote-заказ создан: ${orderId}${caseName ? ` (кейс: ${caseName})` : ''}`);
    return orderId;
  }

  // Выбирает водителя исполнителем. Это РЕАЛЬНЫЙ backend-вызов (set_performer/performer=1),
  // он и заставляет Driver UI показать "Назначен исполнителем".
  // Дополнительно пишет выбор в passenger-choices.json для ботов-водителей.
  async selectDriver(orderId, userId) {
    if (!orderId || !userId) throw new Error('selectDriver: нужны orderId и userId');
    await this.ensureSession();

    const response = await apiPostUrlEncoded(this.config.apiBase, `/drive/get/${orderId}`, this.authFields({
      action: ACTIONS.SET_PERFORMER,
      performer: '1',
      u_id: userId,
    }));
    if (isBackendError(response)) {
      throw new Error(`selectDriver(${orderId}, ${userId}) failed: ${normalizeErrorMessage(response)}`);
    }

    this.selectedByOrder.set(String(orderId), String(userId));
    this.writeChoice(orderId, userId);
    this.log(`order ${orderId}: водитель ${userId} назначен исполнителем`);
    return response;
  }

  // Снимает выбор: возвращает заказ в голосование (release performer=0) и чистит локальный файл.
  async clearSelection(orderId) {
    if (!orderId) throw new Error('clearSelection: нужен orderId');
    const userId = this.selectedByOrder.get(String(orderId));
    this.removeChoice(orderId);

    if (!userId) {
      this.log(`order ${orderId}: локальный выбор очищен (на backend никто не был выбран)`);
      return null;
    }

    await this.ensureSession();
    const response = await apiPostUrlEncoded(this.config.apiBase, `/drive/get/${orderId}`, this.authFields({
      action: ACTIONS.SET_PERFORMER,
      performer: '0',
      u_id: userId,
    }));
    if (isBackendError(response)) {
      this.log(`order ${orderId}: release водителя ${userId} не удался: ${normalizeErrorMessage(response)}`);
    } else {
      this.log(`order ${orderId}: водитель ${userId} отпущен, заказ возвращён в голосование`);
    }
    this.selectedByOrder.delete(String(orderId));
    return response;
  }

  // Пауза.
  wait(ms) {
    return sleep(Math.max(0, Number(ms) || 0));
  }

  // ===================== Дополнительные действия клиента =====================

  // Отмена заказа клиентом (set_cancel_state).
  async cancelOrder(orderId, reason = undefined) {
    if (!orderId) throw new Error('cancelOrder: нужен orderId');
    await this.ensureSession();
    const response = await apiPostUrlEncoded(this.config.apiBase, `/drive/get/${orderId}`, this.authFields({
      action: ACTIONS.SET_CANCEL_STATE,
      reason,
    }));
    if (isBackendError(response)) {
      throw new Error(`cancelOrder(${orderId}) failed: ${normalizeErrorMessage(response)}`);
    }
    this.removeChoice(orderId);
    this.selectedByOrder.delete(String(orderId));
    this.log(`order ${orderId}: заказ отменён клиентом`);
    return response;
  }

  // ===================== Чтение состояния заказа =====================

  normalizeOrderDetail(response, orderId) {
    const booking = response?.data?.booking ?? response?.booking;
    if (Array.isArray(booking)) {
      return booking.find(item => String(item?.b_id ?? item?.id) === String(orderId)) || booking[0] || null;
    }
    if (booking && typeof booking === 'object') {
      return booking[orderId] || Object.values(booking)[0] || null;
    }
    if (response?.data && typeof response.data === 'object' && (response.data.b_id || response.data.id)) {
      return response.data;
    }
    return null;
  }

  async getOrder(orderId) {
    if (!orderId) return null;
    await this.ensureSession();
    const response = await apiPostUrlEncoded(
      this.config.apiBase,
      `/drive/get/${orderId}?fields=00000000u1`,
      this.authFields({ array_type: 'list' }),
    );
    if (isBackendError(response)) return null;
    return this.normalizeOrderDetail(response, orderId);
  }

  // Список откликнувшихся водителей: [{ u_id, c_id, c_state }].
  async getResponders(orderId) {
    const order = await this.getOrder(orderId);
    const drivers = Array.isArray(order?.drivers) ? order.drivers : [];
    return drivers
      .map(driver => ({
        u_id: String(driver?.u_id ?? driver?.user_id ?? ''),
        c_id: String(driver?.c_id ?? driver?.car_id ?? ''),
        c_state: toState(driver?.c_state ?? driver?.state ?? driver?.driver_state),
      }))
      .filter(driver => driver.u_id || driver.c_id);
  }

  // Только кандидаты (откликнулись и ждут выбора).
  async getCandidates(orderId) {
    const responders = await this.getResponders(orderId);
    return responders.filter(driver => driver.c_state === DRIVER_STATES.CONSIDERING || driver.c_state === null);
  }

  // Ждёт, пока появится минимум `min` откликов (по умолчанию 1).
  // Если задан includeUserId — ждёт, пока среди кандидатов появится именно этот водитель.
  async waitForResponses(orderId, { min = 1, includeUserId = null, timeoutMs = null } = {}) {
    const deadline = Date.now() + (Number(timeoutMs) || this.responseTimeoutMs);
    let lastCount = -1;

    while (Date.now() < deadline) {
      const candidates = await this.getCandidates(orderId).catch(() => []);
      if (candidates.length !== lastCount) {
        this.log(`order ${orderId}: откликнулось водителей — ${candidates.length}`);
        lastCount = candidates.length;
      }

      const hasTester = !includeUserId ||
        candidates.some(driver => String(driver.u_id) === String(includeUserId) || String(driver.c_id) === String(includeUserId));

      if (candidates.length >= min && hasTester) return candidates;
      await sleep(this.pollIntervalMs);
    }

    this.log(`order ${orderId}: время ожидания откликов истекло`);
    return this.getCandidates(orderId).catch(() => []);
  }

  // Ждёт, пока выбранный водитель не достигнет нужного состояния (например, ARRIVED).
  async waitForDriverState(orderId, userId, state, { timeoutMs = null } = {}) {
    const target = Number(state);
    const deadline = Date.now() + (Number(timeoutMs) || this.responseTimeoutMs);

    while (Date.now() < deadline) {
      const responders = await this.getResponders(orderId).catch(() => []);
      const driver = responders.find(item => String(item.u_id) === String(userId) || String(item.c_id) === String(userId));
      if (driver && Number(driver.c_state) === target) return driver;
      await sleep(this.pollIntervalMs);
    }
    return null;
  }

  // ===================== Выбор тестера / другого водителя =====================

  // Возвращает u_id водителя-тестера среди откликнувшихся.
  // Приоритет: явно заданный testerUserId; иначе единственный отклик; иначе первый.
  resolveTester(responders, testerUserId = null) {
    const list = Array.isArray(responders) ? responders : [];
    if (testerUserId) {
      const found = list.find(driver =>
        String(driver.u_id) === String(testerUserId) || String(driver.c_id) === String(testerUserId));
      if (found) return found.u_id || testerUserId;
      return null; // тестер задан, но ещё не откликнулся
    }
    if (list.length === 1) return list[0].u_id;
    return list.length ? list[0].u_id : null;
  }

  // Возвращает u_id любого водителя, кроме excludeUserId (для "выбран другой").
  resolveOther(responders, excludeUserId = null) {
    const list = Array.isArray(responders) ? responders : [];
    const other = list.find(driver =>
      String(driver.u_id) !== String(excludeUserId) && String(driver.c_id) !== String(excludeUserId));
    return other ? other.u_id : null;
  }
}

module.exports = {
  ClientSimulator,
  DRIVER_STATES,
  ACTIONS,
};
