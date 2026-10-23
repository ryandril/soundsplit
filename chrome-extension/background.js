// Keeps the list of routed tabs and relays commands to the offscreen player.
// Routes live in session storage because Chrome stops this service worker whenever it's idle.

const OFFSCREEN = 'offscreen.html';

async function getRoutes() {
  const { routes = {} } = await chrome.storage.session.get('routes');
  return routes;
}

async function setRoutes(routes) {
  await chrome.storage.session.set({ routes });
  await chrome.action.setBadgeBackgroundColor({ color: '#4a4a4f' });
  for (const tabId of Object.keys(routes)) {
    chrome.action.setBadgeText({ tabId: Number(tabId), text: '•' }).catch(() => {});
  }
}

async function ensurePlayer() {
  const existing = await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] });
  if (existing.length) return;
  await chrome.offscreen.createDocument({
    url: OFFSCREEN,
    reasons: ['USER_MEDIA'],
    justification: "Plays a tab's captured audio on the speaker the user picked.",
  });
}

async function toPlayer(message) {
  await ensurePlayer();
  const reply = await chrome.runtime.sendMessage({ ...message, target: 'offscreen' });
  if (!reply?.ok) throw new Error(reply?.error || 'The audio player did not respond.');
  return reply;
}

async function forget(tabId) {
  const routes = await getRoutes();
  if (!(tabId in routes)) return;
  delete routes[tabId];
  await setRoutes(routes);
  chrome.action.setBadgeText({ tabId: Number(tabId), text: '' }).catch(() => {});
  if (!Object.keys(routes).length) {
    // Nothing left to play: close the player so Chrome isn't holding an audio page open.
    chrome.offscreen.closeDocument().catch(() => {});
  }
}

const handlers = {
  async list() {
    return { routes: await getRoutes() };
  },

  // A new route: the popup already turned the user's click into a capture stream ID.
  async route({ tabId, streamId, title, deviceId, deviceLabel, volume }) {
    await toPlayer({ type: 'start', tabId, streamId, deviceId, volume });
    const routes = await getRoutes();
    routes[tabId] = { title, deviceId, deviceLabel, volume };
    await setRoutes(routes);
    return {};
  },

  async switch({ tabId, deviceId, deviceLabel }) {
    await toPlayer({ type: 'device', tabId, deviceId });
    const routes = await getRoutes();
    Object.assign(routes[tabId], { deviceId, deviceLabel });
    await setRoutes(routes);
    return {};
  },

  async volume({ tabId, volume }) {
    await toPlayer({ type: 'volume', tabId, volume });
    const routes = await getRoutes();
    if (routes[tabId]) routes[tabId].volume = volume;
    await setRoutes(routes);
    return {};
  },

  async unroute({ tabId }) {
    await toPlayer({ type: 'stop', tabId }).catch(() => {});
    await forget(tabId);
    return {};
  },

  // The captured stream ended on its own: the tab closed, or Chrome stopped the capture.
  async ended({ tabId }) {
    await forget(tabId);
    return {};
  },
};

chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message.target !== 'background') return;
  handlers[message.type](message)
    .then((result) => reply({ ok: true, ...result }))
    .catch((error) => reply({ ok: false, error: error.message || String(error) }));
  return true;
});

chrome.tabs.onRemoved.addListener((tabId) => {
  handlers.unroute({ tabId });
});

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === 'install') chrome.tabs.create({ url: 'permission.html' });
});
