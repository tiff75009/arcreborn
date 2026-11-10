// Real CEF navigation and AppKit selection, using an isolated fixture bundle.
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const bundle=process.env.BROWSER_TAB_ORIGIN_APP;
assert.ok(bundle,'Set BROWSER_TAB_ORIGIN_APP to the TabOriginHarness bundle');
const data=await fs.mkdtemp(path.join(os.tmpdir(),'tab-origin-check-'));
const server=createServer(async(req,res)=>{
  let body=''; for await(const chunk of req) body+=chunk;
  res.setHeader('Content-Type','text/html;charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>${req.url}</title>
    <style>body{font:20px system-ui;padding:24px}a,button{display:block;margin:20px}</style>
    <h1>${req.url}</h1><a id="blank" href="/blank" target="_blank" rel="noopener">Lien nouvel onglet</a>
    <a id="modifier" href="/modifier">Lien avec ⌘</a><a id="middle" href="/middle">Lien clic milieu</a>
    <button id="popup" onclick="window.open('/popup','origin-popup')">window.open</button>
    <form action="/post" method="POST" target="_blank"><input name="value" value="preserved"><button id="post">POST</button></form>
    <p id="payload">${body}</p>`);
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin=`http://127.0.0.1:${server.address().port}`;
const fixture={language:'fr',onboardingComplete:true,sidebarWidth:250,sidebarHidden:false,
  profiles:[{id:'profile',name:'Test',newTabAddress:origin+'/manual'}],
  spaces:[{id:'space',name:'Test',color:'#B5AED9',icon:'◈',profileID:'profile',selectedTabID:'source'}],
  tabs:['source','other','neighbor'].map((id,i)=>({id,spaceID:'space',url:origin+'/'+id,title:id,pinned:false,favorite:false,sidebarOrder:2-i})),
  folders:[],closedTabs:[],activeSpaceID:'space'};
await fs.writeFile(path.join(data,'session.json'),JSON.stringify(fixture));
let app,exited,exitPromise,port,sequence=0;
const checks=[],connections=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,seconds=18){
  const end=Date.now()+seconds*1000;let last;
  while(Date.now()<end){try{const value=await fn();if(value)return value;}catch(e){last=e;}await delay(80);}
  throw Error('Timed out'+(last?': '+last:''));
}
async function state(){return JSON.parse(await fs.readFile(path.join(data,'observed.json'),'utf8'));}
const selected=s=>s.spaces.find(v=>v.id===s.activeSpaceID)?.selectedTabID;
const check=name=>{checks.push(name);console.log('PASS '+name);};
async function command(action,fields={}){
  const id=String(++sequence);
  await fs.writeFile(path.join(data,'command.json'),JSON.stringify({id,action,...fields}));
  await until(async()=>await fs.readFile(path.join(data,'ack'),'utf8')===id);
}
class CDP {
  constructor(ws){this.ws=ws;this.id=0;this.pending=new Map();ws.onmessage=e=>{
    const m=JSON.parse(e.data),p=this.pending.get(m.id);if(!p)return;
    this.pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);
  };}
  static async connect(url){const ws=new WebSocket(url);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});return new CDP(ws);}
  send(method,params={}){return new Promise((resolve,reject)=>{const id=++this.id;
    const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(method+' timed out'));},10000);
    this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({id,method,params}));
  });}
  async evaluate(expression){const r=await this.send('Runtime.evaluate',{expression,returnByValue:true,userGesture:true});
    assert.equal(r.exceptionDetails,undefined);return r.result.value;}
}
async function targets(){return (await fetch(`http://127.0.0.1:${port}/json/list`)).json();}
async function page(url){
  const target=await until(async()=>(await targets()).find(t=>t.type==='page'&&t.url===url));
  const c=await CDP.connect(target.webSocketDebuggerUrl);connections.push(c);
  await until(async()=>await c.evaluate('document.readyState')==='complete');return c;
}
async function launch(){
  await fs.rm(path.join(data,'command.json'),{force:true});
  await fs.rm(path.join(data,'ack'),{force:true});
  const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));port=probe.address().port;await new Promise(r=>probe.close(r));
  const log=await fs.open(path.join(data,'runtime.log'),'a');
  exited=false;app=spawn(path.join(bundle,'Contents/MacOS/Arc Reborn'),[],{
    env:{...process.env,BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_DEBUG_PORT:String(port)},stdio:['ignore',log.fd,log.fd]});
  exitPromise=new Promise(r=>app.once('exit',(code,signal)=>{exited=true;r({code,signal});}));await log.close();
  await until(async()=>{assert.equal(exited,false,'Harness exited');return (await targets()).length;});
}
async function stop(){await command('quit');const result=await until(async()=>exited&&exitPromise,25);assert.equal(result.code,0);}
async function child(url,source){
  const s=await until(async()=>{const s=await state();return s.tabs.some(t=>t.url===url)?s:null;});
  const tab=s.tabs.find(t=>t.url===url),parent=s.tabs.find(t=>t.id===source);
  assert.equal(tab.openerTabID,source);
  const order=s.tabs.filter(t=>t.spaceID==='space'&&!t.pinned&&!t.favorite).sort((a,b)=>a.sidebarOrder-b.sidebarOrder);
  assert.equal(order.findIndex(t=>t.id===tab.id)+1,order.findIndex(t=>t.id===parent.id),'Link must be directly above source');
  return tab;
}
async function returned(source){await until(async()=>selected(await state())===source);}
async function mouseLink(c,id,button='left',modifiers=0){
  const {x,y}=await c.evaluate(`(()=>{const r=document.getElementById(${JSON.stringify(id)}).getBoundingClientRect();return {x:r.x+20,y:r.y+r.height/2}})()`);
  await c.send('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button,modifiers,clickCount:1});
  await c.send('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button,modifiers,clickCount:1});
}
try {
  await launch();let source=await page(origin+'/source');
  await command('new');
  let s=await until(async()=>{const s=await state();return s.tabs.some(t=>t.url===origin+'/manual')?s:null;});
  const manual=s.tabs.find(t=>t.url===origin+'/manual');
  assert.equal(manual.openerTabID,'source');assert.equal(manual.sidebarOrder,0);
  await command('close');await returned('source');check('Manual new tab stays at top and closes back to source');

  await source.evaluate('document.getElementById("blank").click()');
  await child(origin+'/blank','source');const blank=await page(origin+'/blank');
  assert.equal(await blank.evaluate('window.opener === null'),true);
  await command('capture');await command('close');await returned('source');
  check('noopener target=_blank opens above source and returns without JavaScript opener');

  await mouseLink(source,'modifier','left',4);
  const modifier=await child(origin+'/modifier','source');
  assert.equal(selected(await state()),'source');
  await command('select',{tab:modifier.id});await returned(modifier.id);
  await command('close');await returned('source');check('Command-click keeps background focus and returns after selection/close');

  await mouseLink(source,'middle','middle');
  const middle=await child(origin+'/middle','source');
  assert.equal(selected(await state()),'source');
  await command('select',{tab:middle.id});await command('close');await returned('source');
  check('Middle-click uses relative insertion and the same return destination');

  await source.evaluate('document.getElementById("popup").click()');
  const popupTab=await child(origin+'/popup','source'),popup=await page(origin+'/popup');
  await popup.evaluate("void window.open('/nested','nested-origin')");
  await child(origin+'/nested',popupTab.id);const nested=await page(origin+'/nested');
  await nested.evaluate('window.close()');await returned(popupTab.id);
  await popup.evaluate('window.close()');await returned('source');
  check('Nested window.open and script closes return through the originating tabs');

  await command('select',{tab:'other'});const other=await page(origin+'/other');
  await command('select',{tab:'source'});
  await other.evaluate("void window.open('/inactive','inactive-origin')");
  await child(origin+'/inactive','other');const inactive=await page(origin+'/inactive');
  await inactive.evaluate('window.close()');await returned('other');
  check('A background page retains its actual source instead of the previously selected tab');

  await other.evaluate('document.getElementById("post").click()');
  await child(origin+'/post','other');const posted=await page(origin+'/post');
  assert.equal(await posted.evaluate('document.getElementById("payload").textContent'),'value=preserved');
  await command('close');await returned('other');check('POST new-tab navigation preserves its body and return destination');

  await other.evaluate("void window.open('/restart','restart-origin')");
  const restarted=await child(origin+'/restart','other');await page(origin+'/restart');
  await stop();await launch();await page(origin+'/restart');await returned(restarted.id);
  await command('close');await returned('other');check('Return destination survives real application restart');
  await stop();console.log('TAB_ORIGIN_PASS '+checks.length+' runtime checks');
} finally {
  for(const c of connections)c.ws.close();
  if(app&&!exited){app.kill('SIGTERM');await Promise.race([exitPromise,delay(5000)]);if(!exited)app.kill('SIGKILL');}
  server.closeAllConnections();server.close();
  await fs.writeFile(path.join(data,'result.json'),JSON.stringify({checks,data},null,2));
  console.log('Test artifacts: '+data);
}
