// Native CEF integration: direct CDP targets include independently persisted profiles.
import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve('native'), data=await fs.mkdtemp(path.join(os.tmpdir(),'browser-native-test-'));
const report={data,checks:[],failure:null};
const server=createServer(async(req,res)=>{
  if(req.url==='/favicon.png') { res.setHeader('Content-Type','image/png'); res.end(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAMElEQVR4nO3OIQEAAAgDMJKg6Z+MBhDjZmJ+tdOXVAICAgICAgICAgICAgICAunAAzX/1HnVWnPXAAAAAElFTkSuQmCC','base64')); return; }
  let body='';for await(const c of req)body+=c;
  const title=({'/':'Native Browser Test','/next':'Second Page','/popup':'Popup','/post':'POST Complete','/blank':'Blank Link'})[req.url]||'Native Browser Test';
  res.setHeader('Content-Type','text/html;charset=utf-8');
  res.end(`<!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="/favicon.png"><title>${title}</title><style>body{font:17px system-ui;background:#f8fafc;color:#243348;margin:0;padding:70px}h1{font-size:42px}button,a,input{padding:12px;margin:8px}</style></head><body><h1>${title}</h1><p>Page locale rendue par Chromium dans une interface AppKit native.</p><a id="next" href="/next">Page suivante</a><a id="blank" href="/blank" target="_blank">Nouvel onglet</a><button id="popup" onclick="window.child=window.open('/popup','native-popup')">Fenêtre secondaire</button><form action="/post" method="POST" target="_blank"><input name="message" value="preserved"><button id="post">Envoyer</button></form><p id="payload">${body}</p></body></html>`);
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
const state={language:'fr',onboardingComplete:true,sidebarWidth:250,sidebarHidden:false,profiles:[{id:'profile-a',name:'Personnel'},{id:'profile-b',name:'Travail'}],spaces:[{id:'space-a',name:'Personnel',color:'#B5AED9',icon:'◈',profileID:'profile-a',selectedTabID:'tab-a'},{id:'space-b',name:'Travail',color:'#A8CCBA',icon:'✦',profileID:'profile-b',selectedTabID:'tab-b'}],tabs:[{id:'tab-a',spaceID:'space-a',url:origin,title:'Navigation native',pinned:true,favorite:false},{id:'tab-b',spaceID:'space-b',url:origin,title:'Profil séparé',pinned:false,favorite:false}],folders:[],closedTabs:[],activeSpaceID:'space-a'};
state.tabs[0].favorite=true; state.tabs[1].pinned=true; state.tabs[1].favoriteSourceID='tab-a';
state.themeAppearance='dark';
state.spaces[0].theme={points:[{color:'#B5AED9',x:0.2,y:0.3},{color:'#00ACCA',x:0.8,y:0.7}],gradient:0.72,grain:0.35};
await fs.writeFile(path.join(data,'session.json'),JSON.stringify(state));
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,seconds=12){const end=Date.now()+seconds*1000;let last;while(Date.now()<end){try{const v=await fn();if(v)return v;}catch(e){last=e;}await delay(100);}throw Error('Timed out'+(last?`: ${last}`:''));}
class CDP {
  constructor(ws){this.ws=ws;this.id=0;this.pending=new Map();ws.onmessage=event=>{const m=JSON.parse(event.data);const p=this.pending.get(m.id);if(p){this.pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}};}
  static async connect(url){const ws=new WebSocket(url);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});return new CDP(ws);}
  send(method,params={}){return new Promise((resolve,reject)=>{const id=++this.id;const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(`CDP timeout: ${method}`));},10000);this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({id,method,params}));});}
  async evaluate(expression){const r=await this.send('Runtime.evaluate',{expression,returnByValue:true,userGesture:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
  close(){this.ws.close();}
}
let app,log,exited=true,exitPromise,debugPort;const connections=[];
async function launch(seconds){
  const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));debugPort=probe.address().port;await new Promise(r=>probe.close(r));
  log=await fs.open(path.join(root,'build','smoke-app.log'),'a');
  app=spawn(path.resolve(process.env.BROWSER_SMOKE_APP || path.join(root,'build','Arc Reborn.app'),'Contents','MacOS','Arc Reborn'),[],{env:{...process.env,BROWSER_NATIVE_TEST_BACKGROUND:'1',BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_DEBUG_PORT:String(debugPort),BROWSER_NATIVE_TEST_AUTOCLOSE:String(seconds)},stdio:['ignore',log.fd,log.fd]});exited=false;
  exitPromise=new Promise(resolve=>app.once('exit',(code,signal)=>{exited=true;resolve({code,signal});}));
  console.log(JSON.stringify({pid:app.pid,origin,debugPort,data}));
  const target=await until(async()=>{if(exited)throw Error('App exited');return (await targets()).find(p=>p.url.startsWith(origin));},20);
  return connect(target);
}
async function targets(){return (await fetch(`http://127.0.0.1:${debugPort}/json/list`,{signal:AbortSignal.timeout(2000)})).json();}
async function connect(target){const c=await CDP.connect(target.webSocketDebuggerUrl);connections.push(c);await c.send('Page.enable');return c;}
async function title(c,value){await until(async()=>await c.evaluate('document.title')===value);}
async function finish(){
  let timeout;const result=await Promise.race([exitPromise,new Promise((_,reject)=>{timeout=setTimeout(()=>reject(Error('Orderly shutdown timed out')),35000);})]);clearTimeout(timeout);assert.equal(result.code,0,JSON.stringify(result));assert.equal(result.signal,null);await log.close();log=null;
  return JSON.parse(await fs.readFile(path.join(data,'session.json'),'utf8'));
}
function check(s){report.checks.push(s);console.log('PASS '+s);}
// Multi-window persistence overrides the shared sidebar's last active space.
// Switching the fixture's profile must update that explicit window selection.
async function selectSavedSpace(state) {
  const file=path.join(data,'windows.json');
  const records=JSON.parse(await fs.readFile(file,'utf8'));
  for (const record of records) {
    record.activeSpaceID=state.activeSpaceID;
    record.selections=Object.fromEntries(state.spaces.filter(s=>s.selectedTabID).map(s=>[s.id,s.selectedTabID]));
  }
  await fs.writeFile(file,JSON.stringify(records));
}

try{
  await fs.writeFile(path.join(root,'build','smoke-app.log'),'');
  const page=await launch(25);await title(page,'Native Browser Test');check('Chromium navigation in AppKit');
  assert.equal(await page.evaluate('matchMedia("(prefers-color-scheme: dark)").matches'),true);check('Dark appearance reaches Chromium');
  assert.equal(await page.evaluate('typeof window.require+":"+typeof window.process'),'undefined:undefined');check('No Node integration');
  await page.evaluate('document.cookie="scope=first; Max-Age=3600; path=/";localStorage.setItem("profile","first")');
  await page.evaluate('document.querySelector("#next").click()');await title(page,'Second Page');
  const history=await page.send('Page.getNavigationHistory');await page.send('Page.navigateToHistoryEntry',{entryId:history.entries[history.currentIndex-1].id});await title(page,'Native Browser Test');check('Navigation and back history');
  await page.evaluate('document.querySelector("#blank").click()');
  const blank=await connect(await until(async()=>(await targets()).find(p=>p.url===origin+'/blank')));await title(blank,'Blank Link');
  check('target=_blank opens a native tab');
  await blank.evaluate('window.close()');
  await page.evaluate('document.querySelector("#popup").click()');
  const popup=await connect(await until(async()=>(await targets()).find(p=>p.url===origin+'/popup')));await title(popup,'Popup');assert.equal(await popup.evaluate('!!window.opener'),true);check('Popup preserves opener');
  await page.evaluate('document.querySelector("#post").click()');
  const posted=await connect(await until(async()=>(await targets()).find(p=>p.url===origin+'/post')));await title(posted,'POST Complete');assert.equal(await posted.evaluate('document.querySelector("#payload").textContent'),'message=preserved');check('POST popup preserves request body');
  await posted.evaluate('window.close()');await popup.evaluate('window.close()');
  await until(async()=>(await targets()).filter(p=>p.type==='page').length===1);check('Script-created tabs close');
  await until(async()=>{try{return (await fs.readdir(path.join(data,'favicons'))).length>0;}catch{return false;}});check('CEF favicon persists before shutdown');
  let saved=await finish();assert.equal(saved.spaces.length,2);assert.equal(saved.tabs.length,2);check('Orderly shutdown and session restoration');
  assert.equal(saved.tabs.find(t=>t.id==='tab-a').favorite,true);assert.equal(saved.tabs.find(t=>t.id==='tab-b').favoriteSourceID,'tab-a');check('Shared favorite and profile-local tab persist');
  assert.deepEqual(saved.spaces[0].theme,state.spaces[0].theme);check('Gradient and grain persist on disk');
  saved.themeAppearance='light';saved.activeSpaceID='space-b';await fs.writeFile(path.join(data,'session.json'),JSON.stringify(saved));await selectSavedSpace(saved);
  const second=await launch(10);await title(second,'Native Browser Test');assert.equal((await targets()).filter(p=>p.type==='page').length,1);check('Restoring favorites does not load their pages');assert.equal(await second.evaluate('document.cookie'),'');assert.equal(await second.evaluate('localStorage.getItem("profile")'),null);await second.evaluate('document.cookie="scope=second; Max-Age=3600; path=/";localStorage.setItem("profile","second")');check('Cookie and localStorage isolation between profiles');
  assert.equal(await second.evaluate('matchMedia("(prefers-color-scheme: light)").matches'),true);check('Light appearance reaches Chromium');
  saved=await finish();
  if(process.env.BROWSER_SMOKE_REBUILD==='1'){
    const bundle=path.join(root,'build','Arc Reborn.app');
    const requirement=()=>execFileSync('/usr/bin/codesign',['-d','-r-',bundle],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
    const before=requirement();
    await new Promise((resolve,reject)=>{const build=spawn(path.join(root,'scripts','build.sh'),[],{stdio:'ignore'});build.once('exit',code=>code===0?resolve():reject(Error('Rebuild failed: '+code)));});
    assert.equal(requirement(),before);check('Signing identity remains stable across rebuild');
  }
  saved.themeAppearance='automatic';saved.activeSpaceID='space-a';saved.spaces[0].selectedTabID='tab-a';await fs.writeFile(path.join(data,'session.json'),JSON.stringify(saved));await selectSavedSpace(saved);
  const restored=await launch(10);await title(restored,'Native Browser Test');assert.equal(await restored.evaluate('document.cookie'),'scope=first');assert.equal(await restored.evaluate('localStorage.getItem("profile")'),'first');check('Cookies and localStorage persist across restart');await finish();
  const diagnostics=path.join(data,'Chromium','Diagnostics');
  for (const run of await fs.readdir(diagnostics)) {
    const trace=await fs.readFile(path.join(diagnostics,run,'events.jsonl'),'utf8');
    assert.doesNotMatch(trace, /"event":"chrome.unmanaged-created"/, 'A new tab escaped into a Chromium window');
    assert.doesNotMatch(trace, /"event":"app.uncaught-exception"/);
  }
  check('No standalone Chromium window for links, popups, POST or restoration');
  const logs=await fs.readFile(path.join(root,'build','smoke-app.log'),'utf8');assert.doesNotMatch(logs,/Keychain lookup failed|Encryption is not available|Cannot create profile/);check('No Keychain or profile initialization errors');
}catch(error){report.failure=String(error);console.error(error);}
finally{connections.forEach(c=>c.close());if(!exited){app.kill('SIGTERM');await exitPromise;}if(log)await log.close();server.closeAllConnections();await new Promise(r=>server.close(r));await fs.writeFile(path.join(root,'build','smoke-report.json'),JSON.stringify(report,null,2));}
if(report.failure)process.exitCode=1;else console.log('NATIVE_SMOKE_PASS');
