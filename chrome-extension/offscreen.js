// A hidden page that holds one captured stream per routed tab and plays it on the chosen speaker.
// Capturing a tab stops Chrome playing it normally, so this playback is the only place the sound comes out.

const players = new Map(); // tabId -> { stream, audio }

async function start({ tabId, streamId, deviceId, volume }) {
  stop({ tabId });
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: streamId } },
    video: false,
  });
  const audio = new Audio();
  audio.srcObject = stream;
  audio.volume = volume;
  try {
    await audio.setSinkId(deviceId);
    await audio.play();
  } catch (error) {
    stream.getTracks().forEach((track) => track.stop());
    throw error;
  }
  stream.getAudioTracks()[0].addEventListener('ended', () => {
    stop({ tabId });
    chrome.runtime.sendMessage({ target: 'background', type: 'ended', tabId });
  });
  players.set(tabId, { stream, audio });
}

async function device({ tabId, deviceId }) {
  const player = players.get(tabId);
  if (!player) throw new Error('This tab is no longer playing through SoundSplit.');
  await player.audio.setSinkId(deviceId);
}

async function volume({ tabId, volume }) {
  const player = players.get(tabId);
  if (player) player.audio.volume = volume;
}

function stop({ tabId }) {
  const player = players.get(tabId);
  if (!player) return;
  player.audio.pause();
  player.audio.srcObject = null;
  player.stream.getTracks().forEach((track) => track.stop());
  players.delete(tabId);
}

const handlers = { start, device, volume, stop };

chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message.target !== 'offscreen') return;
  Promise.resolve(handlers[message.type](message))
    .then(() => reply({ ok: true }))
    .catch((error) => reply({ ok: false, error: error.message || String(error) }));
  return true;
});
