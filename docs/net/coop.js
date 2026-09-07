/* Two-player transport. Gameplay is authoritative on the room owner's phone. */
(() => {
  'use strict';
  const PROTOCOL = 'greg-mutki-coop-1';
  const PREFIX = 'greg-mutki-v1-';
  const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const MAX_MESSAGE = 65536;
  let peer, connection, timeout, heartbeat, generation = 0, events = [], code = '';
  let hosting = false, occupied = false, latestSnapshot = null;
  const emit = (type, data = {}) => {
    if (events.length >= 128) events.shift();
    events.push({ type, ...data });
  };
  const normalize = value => String(value).trim().toUpperCase();
  const validCode = value => /^[A-HJ-NP-Z2-9]{6}$/.test(value);
  const stop = () => {
    generation++;
    clearTimeout(timeout);
    clearInterval(heartbeat);
    const oldPeer = peer;
    peer = connection = null;
    oldPeer?.destroy();
    occupied = false;
    latestSnapshot = null;
    events = [];
  };
  const send = (message, snapshot = false) => {
    if (!connection?.open) return false;
    const serialized = typeof message === 'string' ? message : JSON.stringify(message);
    if (serialized.length > MAX_MESSAGE) return false;
    // Discard old state under congestion; commands remain reliable and ordered.
    if (snapshot && (connection.bufferSize > 0 || connection.dataChannel?.bufferedAmount > MAX_MESSAGE)) return false;
    try { connection.send(serialized); return true; }
    catch { return false; }
  };
  const attach = (incoming, token) => {
    if (hosting && (occupied || incoming.metadata?.protocol !== PROTOCOL)) {
      incoming.on('open', () => {
        incoming.send(JSON.stringify({ type: 'rejected', reason: 'Комната занята или версии игры отличаются.' }));
        setTimeout(() => incoming.close(), 200);
      });
      return;
    }
    occupied = true;
    connection = incoming;
    const current = () => token === generation && incoming === connection;
    incoming.on('open', () => {
      if (!current()) return;
      clearTimeout(timeout);
      emit('connected');
      send({ type: 'presence', visible: !document.hidden });
      heartbeat = setInterval(() => send({ type: 'presence', visible: !document.hidden }), 1000);
    });
    incoming.on('data', raw => {
      if (!current() || typeof raw !== 'string' || raw.length > MAX_MESSAGE) return;
      try {
        const data = JSON.parse(raw);
        if (!data || typeof data !== 'object' || Array.isArray(data)) return;
        if (data.type === 'snapshot' && !hosting) latestSnapshot = data;
        else emit('message', { data });
      } catch { /* Invalid messages do not enter the game. */ }
    });
    incoming.on('close', () => {
      if (!current()) return;
      clearInterval(heartbeat);
      emit('closed', { message: 'Напарник вышел. Создайте новую комнату, чтобы сыграть снова.' });
    });
    incoming.on('error', () => {
      if (current()) emit('closed', { message: 'Соединение потеряно. Проверьте интернет и создайте новую комнату.' });
    });
  };
  const start = (isHost, roomCode = '') => {
    stop();
    hosting = isHost;
    if (typeof Peer === 'undefined' || typeof RTCPeerConnection === 'undefined') {
      emit('error', { message: 'Браузер не поддерживает сетевую игру. Откройте игру в актуальном Chrome или Safari.' });
      return;
    }
    if (hosting) {
      const random = crypto.getRandomValues(new Uint8Array(6));
      code = Array.from(random, byte => ALPHABET[byte % ALPHABET.length]).join('');
    } else {
      code = normalize(roomCode);
      if (!validCode(code)) {
        emit('error', { message: 'Введите 6 символов кода комнаты латинскими буквами и цифрами.' });
        return;
      }
    }
    const token = generation;
    // Deployments may provide their own signaling and short-lived TURN credentials.
    const options = { debug: 0, ...(window.GREG_MUTKI_RTC_OPTIONS || {}) };
    peer = hosting ? new Peer(PREFIX + code, options) : new Peer(options);
    const current = () => token === generation;
    timeout = setTimeout(() => {
      if (current()) emit('error', { message: 'Не удалось подключиться. Проверьте код и интернет. Попробуйте подключить оба телефона к одному Wi-Fi.' });
    }, 25000);
    peer.on('open', () => {
      if (!current()) return;
      if (hosting) {
        clearTimeout(timeout);
        emit('room', { code });
      } else {
        attach(peer.connect(PREFIX + code, { reliable: true, serialization: 'raw', metadata: { protocol: PROTOCOL } }), token);
      }
    });
    peer.on('connection', incoming => {
      if (current() && hosting) attach(incoming, token);
      else incoming.on('open', () => incoming.close());
    });
    peer.on('error', error => {
      if (!current()) return;
      if (connection?.open && error.type === 'network') return;
      const messages = {
        'peer-unavailable': 'Комната не найдена. Проверьте код и убедитесь, что первый телефон оставлен в игре.',
        'unavailable-id': 'Этот код уже занят. Нажмите «Создать комнату» ещё раз.',
        'network': 'Сервис подключения недоступен. Проверьте интернет и попробуйте снова.'
      };
      emit('error', { message: messages[error.type] || 'Не удалось соединить телефоны. Попробуйте общий Wi-Fi или другую сеть.' });
    });
    peer.on('disconnected', () => {
      if (!current() || connection?.open) return;
      emit('error', { message: 'Связь с сервисом комнат прервана. Создайте комнату заново.' });
    });
  };
  window.GregMutkiCoop = {
    host: () => start(true),
    join: value => start(false, value),
    close: stop,
    send: value => send(value),
    snapshot: value => send(value, true),
    poll: () => {
      const batch = events;
      events = [];
      if (latestSnapshot) {
        batch.push({ type: 'message', data: latestSnapshot });
        latestSnapshot = null;
      }
      return JSON.stringify(batch);
    },
    inviteCode: () => {
      const value = normalize(new URLSearchParams(location.hash.slice(1)).get('room') || '');
      return validCode(value) ? value : '';
    },
    visible: () => !document.hidden,
    copyInvite: async () => {
      const invite = new URL(location.href);
      invite.hash = 'room=' + code;
      try {
        await navigator.clipboard.writeText(invite.href);
        emit('notice', { message: 'Приглашение скопировано. Отправь его напарнику.' });
      } catch {
        emit('notice', { message: 'Код комнаты: ' + code + '. Передай его напарнику.' });
      }
    }
  };
  document.addEventListener('visibilitychange', () => send({ type: 'presence', visible: !document.hidden }));
  window.addEventListener('pagehide', () => send({ type: 'presence', visible: false }));
})();
