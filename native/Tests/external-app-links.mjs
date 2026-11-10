// SPDX-License-Identifier: MPL-2.0
// Run on macOS with Accessibility access, passing a development .app as argv[2].
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const app = path.resolve(process.argv[2] ?? 'native/build/development/Arc Reborn.app');
const dir = await mkdtemp(path.join(path.dirname(app), 'external-link-test-'));
const receiver = path.join(dir, 'Link Receiver.app');
const binary = path.join(receiver, 'Contents/MacOS/LinkReceiver');
const scheme = 'arc-receiver-test-' + process.pid;
const address = scheme + '://open/item?name=Caf%C3%A9%20au%20lait#detail';
const register = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';
const run = (command, args) => execFileSync(command, args, {encoding: 'utf8'}).trim();
const listen = async server => { server.listen(0, '127.0.0.1'); await once(server, 'listening'); return server.address().port; };
async function until(label, read) {
  for (let i = 0; i < 100; i++) { const result = await read(); if (result) return result; await delay(100); }
  throw Error('Timed out: ' + label);
}

const server = createServer((req, res) => {
  if (req.url === '/redirect') { res.writeHead(302, {Location:address}).end(); return; }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end('<title>Essai des liens</title><a id="blank" target="_blank" href="' + address + '">Nouvel onglet</a>' +
    '<p><button id="open">Ouvrir</button></p><a id="unknown" href="arc-missing-' + process.pid + ':test">Inconnu</a>' +
    '<p><a id="next" href="/suite">Suite</a></p><a id="redirect" href="/redirect">Redirection</a>' +
    '<script>document.querySelector("#open").onclick=()=>location.href="' + address + '"</script>');
});
let proc, ws, registered = false, closing = false;
try {
  await mkdir(path.dirname(binary), {recursive:true});
  run('swiftc', [fileURLToPath(new URL('ExternalAppLinkProbe.swift', import.meta.url)), '-o', binary]);
  const info = {CFBundleIdentifier:'local.browser.test.linkreceiver.p' + process.pid,
    CFBundleName:'Link Receiver', CFBundleExecutable:'LinkReceiver', CFBundlePackageType:'APPL', LSUIElement:true,
    CFBundleURLTypes:[{CFBundleURLName:'Test links', CFBundleURLSchemes:[scheme]}]};
  const plist = path.join(receiver, 'Contents/Info.plist');
  await writeFile(plist, JSON.stringify(info));
  run('plutil', ['-convert', 'xml1', plist]);
  run('codesign', ['--force', '--sign', '-', receiver]);
  run(register, ['-f', receiver]); registered = true;
  const origin = 'http://127.0.0.1:' + await listen(server);
  const reservation = createServer(), port = await listen(reservation);
  await new Promise(resolve => reservation.close(resolve));
  const profile = path.join(dir, 'Profile');
  await mkdir(profile);
  await writeFile(path.join(profile,'session.json'), JSON.stringify({language:'fr',onboardingComplete:true,sidebarWidth:240,sidebarHidden:false,
    profiles:[{id:'p',name:'Essai'}],spaces:[{id:'s',name:'Essai',color:'#817BAF',icon:'✦',profileID:'p',selectedTabID:'t'}],
    tabs:[{id:'t',spaceID:'s',url:origin,title:'Essai',pinned:false,favorite:false}],folders:[],closedTabs:[],activeSpaceID:'s'}));
  proc = spawn(path.join(app, 'Contents/MacOS/Arc Reborn'), [], {stdio:'ignore',env:{...process.env,
    BROWSER_NATIVE_TEST_DATA:profile, BROWSER_NATIVE_DEBUG_PORT:String(port)}});
  const targets = async () => (await (await fetch('http://127.0.0.1:' + port + '/json/list')).json()).filter(t => t.type === 'page');
  const page = await until('page', async () => {
    try { return (await targets()).find(t => t.url === origin + '/'); } catch { return false; }
  });
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await once(ws, 'open');
  let seq = 0;
  const pending = new Map();
  ws.addEventListener('message', event => {
    const packet=JSON.parse(event.data), item=pending.get(packet.id);
    if (!item) return;
    pending.delete(packet.id);clearTimeout(item.timer);
    packet.error ? item.reject(Error(packet.error.message)) : item.resolve(packet.result);
  });
  ws.addEventListener('close',()=>{
    for (const item of pending.values()) { clearTimeout(item.timer);item.reject(Error('CDP closed')); }
    pending.clear();
  });
  function rpc(method, params = {}) {
    const id = ++seq;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id);reject(Error(method + ' timed out')); }, 5000);
      pending.set(id,{resolve,reject,timer});
      ws.send(JSON.stringify({id, method, params}));
    });
  }
  const evaluate = async expression => (await rpc('Runtime.evaluate', {expression,returnByValue:true})).result.value;
  const sheet = (...buttons) => run(binary, ['--sheet', String(proc.pid), ...buttons]);
  const received = () => readFile(path.join(dir, 'received.json'), 'utf8').then(JSON.parse, () => null);
  async function click(id) {
    const [x, y] = await evaluate('(()=>{const r=document.getElementById(' + JSON.stringify(id) + ').getBoundingClientRect();return [r.x+4,r.y+4]})()');
    for (const type of ['mousePressed','mouseReleased']) await rpc('Input.dispatchMouseEvent', {type,x,y,button:'left',clickCount:1});
  }
  await until('document', () => evaluate('document.readyState==="complete" && !!document.querySelector("#next")'));
  const prior = await rpc('Page.getNavigationHistory');
  await evaluate('location.href=' + JSON.stringify(address));
  await delay(450);
  assert.equal(sheet(), '');
  assert.equal(await received(), null);
  await evaluate('document.body.appendChild(document.createElement("iframe")).src=' + JSON.stringify(address));
  await delay(450);
  assert.equal(sheet(), '');
  assert.equal(await received(), null);
  await click('redirect');
  await delay(450);
  assert.equal(sheet(), '');
  assert.equal(await received(), null);

  await click('blank');
  await until('named confirmation', () => sheet().includes('Ouvrir Link Receiver ?'));
  assert.ok(sheet().includes('127.0.0.1'));
  sheet('Annuler');
  await until('cancel', () => !sheet());
  assert.equal(await received(), null);
  assert.equal((await targets()).length, 1);

  await click('unknown');
  await until('missing app', () => sheet().includes('Aucune application disponible'));
  sheet('OK');
  await until('dismiss', () => !sheet());
  await click('open');
  await until('named button', () => sheet().includes('Ouvrir Link Receiver'));
  sheet('Ouvrir Link Receiver');
  assert.deepEqual(await until('OS handoff', received), [address]);
  assert.equal(await evaluate('location.href'), origin + '/');
  const after = await rpc('Page.getNavigationHistory');
  assert.deepEqual(after.entries.map(e => e.id), prior.entries.map(e => e.id));
  await click('open');
  await until('pending handoff', () => sheet().includes('Ouvrir Link Receiver'));
  await rpc('Page.navigate', {url:origin + '/changed'});
  await until('navigation dismisses the old confirmation', () => !sheet());
  await until('new page', () => evaluate('location.pathname==="/changed" && !!document.querySelector("#next")'));
  await click('next');
  await until('ordinary web navigation', () => evaluate('location.pathname==="/suite"'));
  // Fulfill official-origin invite fixtures inside this disposable browser.
  // No Discord API, local RPC, account or server-joining action is involved.
  const discordLink = 'discord:///invite-proxy/gca';
  const discordAppName=run(binary,['--app-name',discordLink]);
  if (discordAppName) {
  const fixtureErrors=[];
  const fulfill = params => { void rpc('Fetch.fulfillRequest',params).catch(error=>{
    if (!closing && !/Invalid InterceptionId/i.test(error.message)) fixtureErrors.push(error);
  }); };
  ws.addEventListener('message', event => {
    const packet = JSON.parse(event.data);
    if (packet.method !== 'Fetch.requestPaused') return;
    const request = packet.params;
    if (request.resourceType === 'Script') {
      fulfill({requestId:request.requestId,responseCode:200,
        responseHeaders:[{name:'Content-Type',value:'application/javascript'}],body:''});
      return;
    }
    const frame = request.request.url.includes('frame=1');
    const html = '<title>Discord invitation fixture</title><body><h1>Invitation</h1><script>setTimeout(()=>{' +
      (frame ? 'document.body.appendChild(document.createElement("iframe")).contentWindow.location.href=' : 'location.href=') +
      JSON.stringify(discordLink) + '},200)</script>';
    fulfill({requestId:request.requestId,responseCode:200,
      responseHeaders:[{name:'Content-Type',value:'text/html; charset=utf-8'}],body:Buffer.from(html).toString('base64')});
  });
  await rpc('Fetch.enable', {patterns:[{urlPattern:'https://discord.com/invite/*'},{urlPattern:'https://discord.com.example.invalid/invite/*'}]});
  for (const suffix of ['?deferred=1','?frame=1']) {
    run(binary,['--activate',String(proc.pid)]);await delay(150);
    await rpc('Page.navigate', {url:'https://discord.com/invite/gca'+suffix});
    const confirmation = await until('deferred Discord confirmation', () => {
      const text=sheet();return text.includes('Ouvrir '+discordAppName) || text.includes('Aucune application disponible') ? text : false;
    });
    if (confirmation.includes('Ouvrir '+discordAppName)) assert.ok(confirmation.includes('discord.com'));
    sheet(confirmation.includes('Ouvrir '+discordAppName) ? 'Annuler' : 'OK'); await until('Discord cancel', () => !sheet());
    await evaluate('location.href='+JSON.stringify(discordLink));
    await delay(450);assert.equal(sheet(),'','Deferred retries must not repeat the prompt');
    await evaluate('location.href="discord:///invite-proxy/other-code"');
    await delay(450);assert.equal(sheet(),'','A different invite must not inherit permission');
    assert.equal((await targets()).length,1);
  }
  await rpc('Page.navigate', {url:'https://discord.com.example.invalid/invite/gca'});
  await delay(650);assert.equal(sheet(),'','Lookalike hosts must not gain deferred handoff permission');
  console.log('PASS Discord invitations: deferred main frame, inherited iframe, named confirmation, cancel, one prompt per document, exact invite, lookalikes and no extra tab');
  if (process.env.BROWSER_TEST_LIVE_DISCORD === '1') {
    // Load the actual public URL, blocking app scripts to avoid Discord RPC or
    // account actions. The native invitation offer must not depend on scripts.
    await rpc('Fetch.disable');
    await rpc('Fetch.enable',{patterns:[{resourceType:'Script'}]});
    await rpc('Page.navigate',{url:'https://discord.gg/gca'});
    await until('live invite native confirmation',()=>sheet().includes('Ouvrir '+discordAppName));
    assert.match(sheet(),/discord\.(com|gg)/);
    sheet('Annuler');await until('live invite cancel',()=>!sheet());
    await rpc('Page.stopLoading');
    console.log('PASS actual discord.gg/gca navigation: native Discord confirmation shown and cancelled, no server joined');
  }
  await rpc('Fetch.disable');
  assert.equal(fixtureErrors.length,0,fixtureErrors.map(e=>e.message).join('; '));
  } else console.log('SKIP Discord native confirmation: no registered Discord app on this Mac');
  console.log('PASS external links: user gesture, subframes, redirects, named confirmation and source, cancel, target=_blank, missing app, exact URL delivery, browser history and document changes');
} catch (error) {
  console.error('External test failure artifacts:',dir);
  throw error;
} finally {
  closing = true;
  ws?.close();
  if (proc?.pid && proc.exitCode === null && !proc.signalCode) {
    const exited = once(proc, 'exit');
    proc.kill('SIGTERM');
    await exited;
  }
  if (registered) run(register, ['-u', receiver]);
  if (server.listening) await new Promise(resolve => server.close(resolve));
  if (process.env.BROWSER_KEEP_EXTERNAL_TEST === '1') console.log('External test artifacts:',dir);
  else await rm(dir, {recursive:true,force:true});
}
