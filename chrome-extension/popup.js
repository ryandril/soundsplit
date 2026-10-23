const $ = (selector) => document.querySelector(selector);

let tab;
let devices = [];
let routes = {};

function send(message) {
  return chrome.runtime.sendMessage({ ...message, target: 'background' }).then((reply) => {
    if (!reply?.ok) throw new Error(reply?.error || 'Something went wrong.');
    return reply;
  });
}

function showError(error) {
  const box = $('.error');
  box.hidden = !error;
  box.textContent = error ? friendly(error.message || String(error)) : '';
}

function friendly(message) {
  if (/active stream/i.test(message)) return 'Another extension is already capturing this tab.';
  if (/NotFoundError|not found/i.test(message)) return 'That speaker is no longer connected.';
  return message;
}

// "MacBook Air Speakers (Built-in)" -> "MacBook Air Speakers"
const shortName = (label) => label.replace(/\s*\((Built-in|Bluetooth|Virtual|USB)\)$/i, '');

async function loadDevices() {
  const all = await navigator.mediaDevices.enumerateDevices();
  // "default" and "communications" are aliases for another entry in the list.
  devices = all.filter((d) => d.kind === 'audiooutput' && d.deviceId && !['default', 'communications'].includes(d.deviceId));
  return devices.length > 0 && devices.every((d) => d.label);
}

function option(label, deviceId, checked) {
  const button = document.createElement('button');
  button.className = 'option';
  button.setAttribute('role', 'radio');
  button.setAttribute('aria-checked', String(checked));
  button.dataset.deviceId = deviceId;
  button.innerHTML = '<span class="check">✓</span><span></span>';
  button.lastChild.textContent = label;
  button.addEventListener('click', () => choose(deviceId, label));
  return button;
}

function render() {
  const route = routes[tab.id];
  $('.tab-status').textContent = route ? `Playing on ${shortName(route.deviceLabel)}` : 'Playing on your system output';

  const options = $('.options');
  options.replaceChildren(
    option('System output', '', !route),
    ...devices.map((d) => option(shortName(d.label), d.deviceId, route?.deviceId === d.deviceId)),
  );

  $('.volume').hidden = !route;
  if (route) {
    const percent = Math.round(route.volume * 100);
    $('.volume input').value = percent;
    $('.volume-value').textContent = percent;
  }

  const others = Object.entries(routes).filter(([id]) => Number(id) !== tab.id);
  $('.others').hidden = others.length === 0;
  $('.others ul').replaceChildren(...others.map(([id, r]) => {
    const item = document.createElement('li');
    item.innerHTML = '<span></span><span></span><button class="reset">Reset</button>';
    item.children[0].textContent = r.title;
    item.children[1].textContent = shortName(r.deviceLabel);
    item.children[2].title = 'Send this tab back to the system output';
    item.children[2].addEventListener('click', () => run(() => send({ type: 'unroute', tabId: Number(id) })));
    return item;
  }));
}

async function run(action) {
  showError(null);
  for (const button of document.querySelectorAll('.option')) button.disabled = true;
  try {
    await action();
  } catch (error) {
    showError(error);
  }
  ({ routes } = await send({ type: 'list' }));
  render();
}

function choose(deviceId, label) {
  const route = routes[tab.id];
  if ((route?.deviceId ?? '') === deviceId) return;
  run(async () => {
    if (!deviceId) return send({ type: 'unroute', tabId: tab.id });
    if (route) return send({ type: 'switch', tabId: tab.id, deviceId, deviceLabel: label });
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
    return send({ type: 'route', tabId: tab.id, streamId, title: tab.title, deviceId, deviceLabel: label, volume: 1 });
  });
}

$('.volume input').addEventListener('input', (event) => {
  const volume = event.target.value / 100;
  $('.volume-value').textContent = event.target.value;
  routes[tab.id].volume = volume;
  send({ type: 'volume', tabId: tab.id, volume }).catch(showError);
});

$('[data-action="allow"]').addEventListener('click', () => {
  chrome.tabs.create({ url: 'permission.html' });
  window.close();
});

(async () => {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  $('.tab-title').textContent = tab.title || 'This tab';
  if (tab.favIconUrl) $('.favicon').src = tab.favIconUrl;
  else $('.favicon').hidden = true;

  ({ routes } = await send({ type: 'list' }));

  if (!/^https?:|^file:/.test(tab.url || '')) {
    $('.unsupported').hidden = false;
    $('.tab-status').textContent = '';
  } else if (!(await loadDevices())) {
    $('.needs-access').hidden = false;
  } else {
    $('.picker').hidden = false;
  }
  render();
})();
