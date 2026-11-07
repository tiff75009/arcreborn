// SPDX-License-Identifier: MPL-2.0
// Run either "widevine" (network required) or "h264" (entirely local).
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

// On a clean profile, exercise the same on-demand update button available to a user.
async function checkWidevineComponent(port, origin) {
  let target;
  const deadline = Date.now() + 15000;
  while (!target && Date.now() < deadline) {
    try {
      const response = await fetch('http://127.0.0.1:' + port + '/json/list', { signal: AbortSignal.timeout(1000) });
      target = (await response.json()).find(page => page.url === 'chrome://components/' && page.type === 'page');
    } catch { /* The test browser may still be starting its debugging endpoint. */ }
    if (!target) await delay(150);
  }
  if (!target) throw Error('The component manager did not open');
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  try {
    await once(socket, 'open', { signal: AbortSignal.timeout(5000) });
    async function command(id, method, params) {
      const signal = AbortSignal.timeout(15000);
      let message = once(socket, 'message', { signal });
      socket.send(JSON.stringify({ id, method, params }));
      for (;;) {
        const [event] = await message;
        const reply = JSON.parse(event.data);
        if (reply.id === id) {
          if (reply.error) throw Error(reply.error.message);
          return reply.result;
        }
        message = once(socket, 'message', { signal });
      }
    }
    const click = async () => {
      const deadline = Date.now() + 10000;
      while (Date.now() < deadline) {
        const button = document.getElementById('oimompecagnajdejgnnjijobebaeigek');
        if (button?.matches('button.button-check-update')) { button.click(); return true; }
        await new Promise(resolve => setTimeout(resolve, 150));
      }
      return false;
    };
    const result = await command(1, 'Runtime.evaluate', { expression: '(' + click + ')()', awaitPromise: true, returnByValue: true });
    assert.equal(result.result?.value, true, 'Widevine update button missing');
    await command(2, 'Page.navigate', { url: origin });
  } finally { socket.close(); }
}

async function widevine() {
  const assets = 'https://storage.googleapis.com/shaka-demo-assets/angel-one-widevine/';
  const license = 'https://proxy.uat.widevine.com/proxy';
  const response = await fetch(new URL('dash.mpd', assets));
  if (!response.ok) throw Error('Shaka manifest HTTP ' + response.status);
  const xml = new DOMParser().parseFromString(await response.text(), 'application/xml');
  const videoSet = xml.querySelector('AdaptationSet[contentType="video"]');
  const rep = videoSet.querySelector('Representation[mimeType="video/mp4"][codecs^="avc1"]');
  const pssh = videoSet.querySelector('ContentProtection[schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"]')
    .getElementsByTagNameNS('urn:mpeg:cenc:2013', 'pssh')[0].textContent;
  const mime = 'video/mp4; codecs="' + rep.getAttribute('codecs') + '"';
  const config = [{ initDataTypes: ['cenc'], videoCapabilities: [{ contentType: mime }] }];

  // On a fresh profile the page can load before Chromium's signed component arrives.
  let access;
  const deadline = Date.now() + 100000;
  while (!access) {
    try { access = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', config); }
    catch (err) {
      if (err.name !== 'NotSupportedError') throw err;
      if (Date.now() >= deadline) throw Error('Widevine unavailable after 100 s on a fresh profile. Check its status in chrome://components. ' + err);
      await new Promise(resolve => setTimeout(resolve, 1500));
    }
  }
  const keys = await access.createMediaKeys().catch(err => {
    throw Error('Widevine registered but could not create a CDM: ' + err);
  });
  const video = document.querySelector('video');
  await video.setMediaKeys(keys);
  const session = keys.createSession();
  const usable = new Promise((resolve, reject) => {
    session.onkeystatuseschange = () => {
      const statuses = [...session.keyStatuses.values()];
      if (statuses.includes('usable')) resolve();
      else if (statuses.some(status => ['internal-error', 'expired', 'output-restricted'].includes(status))) reject(Error('CDM: ' + statuses.join(', ')));
    };
    session.onmessage = async event => {
      try {
        const answer = await fetch(license, { method: 'POST', body: event.message });
        if (!answer.ok) throw Error('Widevine test license HTTP ' + answer.status);
        await session.update(await answer.arrayBuffer());
      } catch (err) { reject(err); }
    };
  });
  const init = Uint8Array.from(atob(pssh), c => c.charCodeAt(0));
  await Promise.all([usable, session.generateRequest('cenc', init)]);
  const media = new MediaSource();
  const opened = new Promise(resolve => media.addEventListener('sourceopen', resolve, { once: true }));
  const objectURL = URL.createObjectURL(media);
  try {
    video.src = objectURL;
    await opened;
    const buffer = media.addSourceBuffer(mime);
    const sample = await fetch(new URL(rep.querySelector('BaseURL').textContent, assets));
    if (!sample.ok) throw Error('Shaka sample HTTP ' + sample.status);
    const data = await sample.arrayBuffer();
    await new Promise((resolve, reject) => {
      buffer.addEventListener('updateend', resolve, { once: true });
      buffer.addEventListener('error', () => reject(Error('Encrypted MP4 append failed')), { once: true });
      buffer.appendBuffer(data);
    });
    media.endOfStream();
    await video.play();
    while (video.currentTime < 1 && !video.ended) {
      if (video.error) throw Error(video.error.message);
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    const quality = video.getVideoPlaybackQuality();
    return { keySystem: access.keySystem, keys: [...session.keyStatuses.values()],
      seconds: video.currentTime, frames: quality.totalVideoFrames - quality.droppedVideoFrames, width: video.videoWidth };
  } finally {
    video.pause();
    URL.revokeObjectURL(objectURL);
    await session.close();
  }
}

async function h264() {
  const formats = RTCRtpSender.getCapabilities('video').codecs.filter(c => c.mimeType.toLowerCase() === 'video/h264');
  if (!formats.length) throw Error('H.264 unavailable for WebRTC sending');
  const canvas = document.createElement('canvas');
  canvas.width = 320;
  canvas.height = 180;
  const paint = canvas.getContext('2d');
  let tick = 0;
  const timer = setInterval(() => {
    paint.fillStyle = ++tick % 2 ? 'navy' : 'orange';
    paint.fillRect(0, 0, canvas.width, canvas.height);
  }, 66);
  const stream = canvas.captureStream(15);
  const sender = new RTCPeerConnection({ iceServers: [] });
  const receiver = new RTCPeerConnection({ iceServers: [] });
  async function localDescription(pc, description) {
    const gathered = new Promise(resolve => {
      pc.addEventListener('icecandidate', event => { if (!event.candidate) resolve(); });
    });
    await pc.setLocalDescription(description);
    if (pc.iceGatheringState !== 'complete') await gathered;
    return pc.localDescription;
  }
  try {
    sender.addTransceiver(stream.getVideoTracks()[0], { direction: 'sendonly' }).setCodecPreferences(formats);
    await receiver.setRemoteDescription(await localDescription(sender, await sender.createOffer()));
    await sender.setRemoteDescription(await localDescription(receiver, await receiver.createAnswer()));
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      const [tx, rx] = await Promise.all([sender.getStats(), receiver.getStats()]);
      const sent = [...tx.values()].find(s => s.type === 'outbound-rtp' && s.kind === 'video');
      const received = [...rx.values()].find(s => s.type === 'inbound-rtp' && s.kind === 'video');
      if (sent?.framesEncoded > 5 && received?.framesDecoded > 5) {
        const codec = tx.get(sent.codecId);
        return { send: codec.mimeType, receive: rx.get(received.codecId).mimeType, fmtp: codec.sdpFmtpLine,
          encoded: sent.framesEncoded, decoded: received.framesDecoded, encoder: sent.encoderImplementation,
          powerEfficientEncoder: sent.powerEfficientEncoder };
      }
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    throw Error('H.264 negotiation produced no decoded frames: ' + receiver.connectionState);
  } finally {
    sender.close(); receiver.close();
    clearInterval(timer); stream.getTracks().forEach(track => track.stop());
  }
}

const mode = process.argv[2];
if (!['h264', 'widevine'].includes(mode)) throw Error('Expected widevine or h264');
const profile = await mkdtemp(path.join(os.tmpdir(), 'arc-media-check-'));
const bundle = process.env.BROWSER_SMOKE_APP || fileURLToPath(new URL('../build/development/Arc Reborn.app', import.meta.url));
const run = mode === 'h264' ? h264 : widevine;
const script = '(' + run.toString() + ')().then(result => ({ result }), e => ({ error: String(e) }))' +
  '.then(value => fetch("/result", { method: "POST", body: JSON.stringify(value) }))';
let finish;
const result = new Promise(resolve => { finish = resolve; });
const server = createServer(async (req, res) => {
  if (req.url === '/result' && req.method === 'POST') {
    let data = '';
    for await (const chunk of req) data += chunk;
    res.end();
    finish(JSON.parse(data));
  } else {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end('<title>Arc Reborn media test</title><video muted playsinline></video><script>' + script + '</script>');
  }
});
let app, timer, ended;
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = 'http://127.0.0.1:' + server.address().port;
  let debugPort;
  if (mode === 'widevine') {
    const probe = createServer();
    probe.listen(0, '127.0.0.1');
    await once(probe, 'listening');
    debugPort = probe.address().port;
    await new Promise(resolve => probe.close(resolve));
  }
  // The signed release also initializes four app-level preferences on startup.
  const domain = execFileSync('/usr/libexec/PlistBuddy', ['-c', 'Print CFBundleIdentifier', path.join(bundle, 'Contents/Info.plist')], {encoding:'utf8'}).trim();
  function pref(key, fallback) {
    try { return execFileSync('defaults', ['read', domain, key], {encoding:'utf8', stdio:['ignore','pipe','ignore']}).trim(); }
    catch { return fallback; }
  }
  await writeFile(path.join(profile, 'session.json'), JSON.stringify({
    language:pref('BrowserLanguage','fr'), savePasswords:pref('BrowserSavePasswords','1') !== '0',
    automaticSignIn:pref('BrowserAutomaticSignIn','1') !== '0', formSuggestions:pref('BrowserFormSuggestions','1') !== '0',
    onboardingComplete:true, sidebarHidden:false, sidebarWidth:228, activeSpaceID:'s',
    profiles:[{id:'p',name:'Media'}], spaces:[{id:'s',profileID:'p',name:'Media',color:'#8871C5',icon:'◈',selectedTabID:'t'}],
    tabs:[{id:'t',spaceID:'s',url:debugPort ? 'chrome://components/' : origin,title:'Media',pinned:false,favorite:false}], folders:[], closedTabs:[]
  }));
  const switches = mode === 'widevine' ? ['--component-updater=fast-update'] : ['--disable-component-update'];
  // A different window can cover the fixture while a license request is in flight.
  switches.push('--disable-backgrounding-occluded-windows', '--disable-background-media-suspend');
  if (mode === 'h264' && process.env.BROWSER_RTC_SOFTWARE_ONLY === '1') switches.push('--disable-accelerated-video-encode');
  app = spawn(path.join(bundle, 'Contents/MacOS/Arc Reborn'), switches, {
    env:{...process.env, BROWSER_NATIVE_TEST_DATA:profile, BROWSER_NATIVE_TEST_AUTOCLOSE:'170',
      ...(debugPort ? { BROWSER_NATIVE_DEBUG_PORT:String(debugPort) } : {})}, stdio:'ignore'
  });
  ended = once(app, 'exit');
  const playback = debugPort ? checkWidevineComponent(debugPort, origin).then(() => result) : result;
  const report = await Promise.race([playback,
    ended.then(([code, signal]) => { throw Error('Arc Reborn exited: ' + (signal || code)); }),
    new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Timed out waiting for ' + mode)), mode === 'widevine' ? 160000 : 35000); })
  ]);
  assert.ok(!report.error, report.error);
  const evidence = report.result;
  if (mode === 'widevine') {
    assert.equal(evidence.keySystem, 'com.widevine.alpha');
    assert.ok(evidence.keys.includes('usable') && evidence.frames > 0 && evidence.seconds >= 1 && evidence.width > 0);
  } else {
    assert.equal(evidence.send.toLowerCase(), 'video/h264');
    assert.equal(evidence.receive.toLowerCase(), 'video/h264');
  }
  console.log(JSON.stringify(evidence));
} finally {
  clearTimeout(timer);
  if (app?.exitCode === null && app.signalCode === null && app.pid) { app.kill('SIGTERM'); await ended; }
  server.closeAllConnections(); server.close();
  await rm(profile, { recursive:true, force:true });
}
