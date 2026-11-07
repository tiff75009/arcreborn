// SPDX-License-Identifier: MPL-2.0
// --live checks Google's harmless public fixtures with the normal engine.
// The default uses Chromium's own test verdicts and never needs an API key.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, readFile, readdir, rm, stat} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const live = process.argv.includes('--live');
const dir = await mkdtemp(path.join(tmpdir(),'arc-reputation-'));
const downloads = path.join(dir,'Downloads');
const snapshot = path.join(dir,'windows.snapshot');
const harmless = Buffer.from('Arc Reborn security regression fixture. This file contains only text.\n');
const listed = 'https://testsafebrowsing.appspot.com/s/phishing.html';
const googleTests = 'https://testsafebrowsing.appspot.com/';
const fixture = createServer((req,res) => {
  if (['/blocked.dmg','/safe.txt'].includes(req.url)) {
    res.writeHead(200,{'Content-Disposition':'attachment; filename="'+req.url.slice(1)+'"','Content-Type':'application/octet-stream','Content-Length':harmless.length});
    res.end(harmless);
  } else if (req.url === '/redirect') {
    res.writeHead(302,{Location:live ? listed : '/flagged'}); res.end();
  } else {
    res.setHeader('Content-Type','text/html; charset=utf-8');
    res.end('<title>Arc fixture</title><main>Article de test</main><a href="/redirect">Lien</a> <a href="/safe.txt" download>Texte</a> <a href="/blocked.dmg" download>Archive</a>');
  }
});
const listen = server => new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const sleep = ms=>new Promise(r=>setTimeout(r,ms));
async function until(check, message, seconds=18) {
  for (const deadline=Date.now()+seconds*1000; Date.now()<deadline;) {
    try { const result=await check(); if (result) return result; } catch {}
    await sleep(200);
  }
  throw new Error(message);
}

await listen(fixture);
const origin='http://127.0.0.1:'+fixture.address().port;
const probe=createServer(); await listen(probe); const port=probe.address().port; await new Promise(r=>probe.close(r));
await mkdir(downloads);
const session={language:'fr',onboardingComplete:true,sidebarWidth:240,sidebarHidden:false,activeSpaceID:'space',
  profiles:[{id:'user',name:'Essai'}],spaces:[{id:'space',name:'Essai',profileID:'user',icon:'sf:shield',color:'#574B72',selectedTabID:'tab'}],
  tabs:[{id:'tab',spaceID:'space',url:origin+'/',title:'Essai',pinned:false,favorite:false}],folders:[],closedTabs:[]};
await writeFile(path.join(dir,'session.json'),JSON.stringify(session));
const switches=['--safebrowsing-fast-initial-lists-update'];
if (!live) switches.push('--mark_as_phishing='+origin+'/flagged','--safebrowsing-manual-download-blacklist='+createHash('sha256').update(harmless).digest('hex'));
const bundle=process.env.BROWSER_SMOKE_APP || fileURLToPath(new URL('../build/Arc Reborn.app',import.meta.url));
const app=spawn(path.join(bundle,'Contents/MacOS/Arc Reborn'),switches,{stdio:'ignore',env:{...process.env,
  BROWSER_NATIVE_TEST_DATA:dir,BROWSER_NATIVE_TEST_DOWNLOADS:downloads,BROWSER_NATIVE_DEBUG_PORT:String(port),BROWSER_NATIVE_HOST_DIAGNOSTICS:snapshot}});
const exited=new Promise(resolve=>app.once('exit',resolve));
let browser;
async function records() { return JSON.parse(await readFile(path.join(dir,'library.json'),'utf8')).downloads; }
async function visibleDocument() {
  return JSON.parse(await readFile(snapshot,'utf8')).some(w=>w.visible && w.views.some(v=>v.class.includes('RenderWidget') && !v.hidden));
}
try {
  browser=await until(()=>chromium.connectOverCDP('http://127.0.0.1:'+port,{timeout:650}), 'Isolated Dev browser did not start');
  const page=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>p.url()===origin+'/'),'Missing fixture tab');
  await until(visibleDocument,'Native document is hidden');
  if (live) {
    const profileRoot=path.join(dir,'Chromium','MockKeychain');
    await until(async()=>{
      // The v4 database lives in the Chromium profile root or its Safe Browsing directory.
      for (const root of [path.join(profileRoot,'Safe Browsing'),profileRoot]) {
        for (const name of await readdir(root).catch(()=>[])) {
          if (/phish|soceng/i.test(name) && (await stat(path.join(root,name))).size>1000) return true;
        }
      }
      return false;
    },'Google did not provision a local phishing list',90);
  }
  await page.getByText('Lien',{exact:true}).click({noWaitAfter:true});
  await page.locator('#primary-button').waitFor({state:'visible',timeout:16000});
  assert.match(await page.locator('body').innerText(),/site dangereux|dangerous site/i);
  assert.equal(await page.locator('input[type=password]').count(),0);
  await until(visibleDocument,'The native overlay covered the security warning');
  await page.locator('#primary-button').click({noWaitAfter:true});
  await page.getByText('Article de test',{exact:true}).waitFor();
  console.log('PASS phishing through redirect, rendered security interstitial, safe return ('+(live?'Google':'local verdict')+')');
  await page.getByText('Texte',{exact:true}).click({noWaitAfter:true});
  await until(async()=>(await records()).some(r=>r.state==='complete' && r.name==='safe.txt'),'Harmless transfer did not complete');
  assert.deepEqual(await readFile(path.join(downloads,'safe.txt')),harmless);
  if (live) {
    // Google serves these harmless bytes as text/html with a Windows filename.
    // Preserve the remote bytes and URL, using a macOS-inspected target type.
    await page.goto(googleTests);
    await page.locator('a[href$="/s/content.exe"]').first().evaluate(link=>{link.download='sample.dmg';});
    await page.locator('a[href$="/s/content.exe"]').first().click({noWaitAfter:true});
  } else {
    await page.getByText('Archive',{exact:true}).click({noWaitAfter:true});
  }
  try {
    await until(async()=>(await records()).some(r=>r.state==='blocked'),'Expected a security block for '+(live?'Google sample':'local flagged file'),35);
  } catch (error) {
    const cdp=await browser.newBrowserCDPSession();
    const {histograms}=await cdp.send('Browser.getHistograms',{query:'SBClientDownload'});
    console.error('Download classification',JSON.stringify(histograms.filter(h=>/CheckDownloadStats|ResponseCode|Result/.test(h.name)).map(h=>[h.name,h.buckets.map(b=>b.low)])));
    if (live && process.env.GOOGLE_API_KEY && histograms.some(h=>h.name.endsWith('NetworkResult') && h.buckets.some(b=>b.low===403))) {
      // Request only error metadata from the same Google service. Never log
      // URLs containing the key, response bodies or authentication headers.
      const reply=await fetch('https://sb-ssl.google.com/safebrowsing/clientreport/download',{
        method:'POST',headers:{'X-Goog-Api-Key':process.env.GOOGLE_API_KEY,'Content-Type':'application/octet-stream'},body:new Uint8Array(),signal:AbortSignal.timeout(8000)});
      const details=(await reply.json().catch(()=>({}))).error?.details || [];
      for (const item of details) {
        const service=item.metadata?.service;
        if (/^[a-z0-9-]+\.googleapis\.com$/.test(service) && /^[A-Z_]+$/.test(item.reason))
          console.error('Google API access:',item.reason,service);
      }
    }
    console.error('Native transfer states',(await records()).map(r=>[r.name,r.state]));
    throw error;
  }
  const blocked=(await records()).find(r=>r.state==='blocked');
  assert.equal(blocked.path,''); assert.ok(blocked.name);
  await until(async()=>JSON.parse(await readFile(snapshot,'utf8')).some(w=>w.visible && w.views.some(v=>v.class==='DownloadWarning' && !v.hidden && v.label.includes('bloqué'))),'Missing native download warning',3);
  await until(async()=>(await readdir(downloads)).every(name=>name==='safe.txt'),'A final or partial blocked file was left in Downloads');
  console.log('PASS harmless download completed, security verdict reached native library, no blocked file left on disk');
} finally {
  if (app.exitCode===null && app.signalCode===null) app.kill('SIGTERM');
  await exited; await browser?.close().catch(()=>{}); fixture.closeAllConnections(); fixture.close();
  await rm(dir,{recursive:true,force:true});
}
