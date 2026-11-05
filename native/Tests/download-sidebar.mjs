// SPDX-License-Identifier: MPL-2.0
// Run after a native build: node native/Tests/download-sidebar.mjs
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, mkdir, readFile, writeFile, realpath, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const bundle = process.env.BROWSER_SMOKE_APP || fileURLToPath(new URL('../build/Arc Reborn.app',import.meta.url));
const sleep = ms => new Promise(resolve => setTimeout(resolve,ms));
const payload = Buffer.alloc(48 * 1024,65);
const server = createServer((req,res) => {
  if (req.url === '/sample') {
    res.writeHead(200,{'Content-Type':'text/plain','Content-Length':payload.length,
      'Content-Disposition':'attachment; filename="Arc-Reborn-test.txt"'});
    res.write(payload.subarray(0,1024));
    setTimeout(() => res.end(payload.subarray(1024)),550);
    return;
  }
  res.end('<!doctype html><title>Download test</title><a href="/sample" download>Download</a>');
});
const listen = server => new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
await listen(server);
const origin = 'http://127.0.0.1:'+server.address().port;

async function check(hidden) {
  const root = await mkdtemp(path.join(tmpdir(),'arc-download-test-'));
  const folder = path.join(root,'Téléchargements locaux');
  const report = path.join(root,'windows.json.snapshot');
  await mkdir(folder);
  const tab = {id:'tab',spaceID:'space',url:origin+'/',title:'Download test',pinned:false,favorite:false};
  const space = {id:'space',name:'Test',profileID:'user',icon:'sf:folder',color:'#574B72',selectedTabID:tab.id};
  await writeFile(path.join(root,'session.json'),JSON.stringify({language:'fr',onboardingComplete:true,
    sidebarHidden:hidden,sidebarWidth:240,activeSpaceID:space.id,profiles:[{id:'user',name:'Test'}],
    tabs:[tab],spaces:[space],closedTabs:[],folders:[]}));
  const probe = createServer(); await listen(probe);
  const port = probe.address().port; await new Promise(resolve => probe.close(resolve));
  const child = spawn(path.join(bundle,'Contents/MacOS/Arc Reborn'),[],{stdio:'ignore',env:{...process.env,
    BROWSER_NATIVE_TEST_DATA:root,BROWSER_NATIVE_TEST_DOWNLOADS:folder,BROWSER_NATIVE_DEBUG_PORT:String(port),
    BROWSER_NATIVE_HOST_DIAGNOSTICS:report}});
  const exited = new Promise(resolve => child.once('exit',resolve));
  let ws;
  try {
    let page;
    for (let i=0;i<150 && !page;i++) {
      try { page = (await (await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.url===tab.url); } catch {}
      if (!page) await sleep(100);
    }
    assert.ok(page,'the isolated fixture must load');
    ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((ok,fail)=>{ws.onopen=ok;ws.onerror=fail;});
    // A CDP target can load before AppKit has presented its document window.
    let presented = false;
    for (let i=0;i<100 && !presented;i++) {
      try {
        const windows = JSON.parse(await readFile(report,'utf8'));
        presented = windows.some(w=>w.visible && w.key && w.views.some(v=>!v.hidden && v.class.includes('RenderWidget')));
      } catch {}
      if (!presented) await sleep(80);
    }
    assert.ok(presented,'the document window must be visible before the download gesture');
    ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:'document.querySelector("a").click()',userGesture:true}}));
    let sawFlight = false, destinationVisible = false, visibleAfter, lastReport;
    for (let i=0;i<85;i++) {
      await sleep(85);
      let windows;
      try { windows = JSON.parse(await readFile(report,'utf8')); } catch { continue; }
      const visible = windows.filter(w=>w.visible);
      assert.ok(!visible.some(w=>w.class==='NativeWidgetMacNSWindow' || w.class==='NSSavePanel'),'unexpected download window');
      const views = visible.flatMap(w=>w.views);
      const flight = views.some(v=>!v.hidden && v.class.includes('DownloadFlightView'));
      const footer = views.some(v=>!v.hidden && v.class.includes('LibraryFooterButton'));
      sawFlight ||= flight;
      destinationVisible ||= flight && footer;
      visibleAfter = footer;
      lastReport = windows;
    }
    assert.ok(lastReport && sawFlight && destinationVisible,'flight and its sidebar destination must both be visible');
    assert.ok(hidden || visibleAfter,'a pinned sidebar stays visible');
    const records = JSON.parse(await readFile(path.join(root,'library.json'),'utf8')).downloads;
    assert.equal(records.length,1); assert.equal(records[0].profileID,'user'); assert.equal(records[0].state,'complete');
    const file = path.join(folder,'Arc-Reborn-test.txt');
    assert.equal(await realpath(records[0].path),await realpath(file));
    assert.deepEqual(await readFile(file),payload);
    console.log('PASS: real download, sidebar animation and no Chromium popup ('+(hidden?'auto-hide':'pinned')+')');
  } finally {
    ws?.close(); if (child.exitCode===null && child.signalCode===null) child.kill('SIGTERM');
    await exited; await rm(root,{recursive:true,force:true});
  }
}
try { await check(false); await check(true); }
finally { server.closeAllConnections(); server.close(); }
