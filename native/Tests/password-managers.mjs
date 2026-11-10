import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
// Native-only source distributions need no npm dependencies for this test.
class CDP {
 constructor(ws){this.ws=ws;this.seq=0;this.pending=new Map();ws.onmessage=({data})=>{const m=JSON.parse(data),p=this.pending.get(m.id);if(p){this.pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}};}
 static async connect(url){const ws=new WebSocket(url);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});return new CDP(ws);}
 send(method,params={}){return new Promise((resolve,reject)=>{const id=++this.seq,timer=setTimeout(()=>{this.pending.delete(id);reject(Error('CDP timeout: '+method));},12000);this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({id,method,params}));});}
 async evaluate(expression){if(typeof expression==='function')expression='('+expression.toString()+')()';const result=await this.send('Runtime.evaluate',{expression,returnByValue:true,userGesture:true});if(result.exceptionDetails)throw Error('Fixture evaluation failed');return result.result.value;}
 async goto(url){await this.send('Page.navigate',{url});await until(async()=>await this.evaluate('location.href=== '+JSON.stringify(url)+' && document.readyState=== "complete"'));}
 async waitForURL(url){await until(async()=>await this.evaluate('location.href=== '+JSON.stringify(url)));}
 locator(selector){const page=this,query='document.querySelector('+JSON.stringify(selector)+')';return {
  async inputValue(){return page.evaluate(query+'.value');},
  async fill(value){await page.evaluate(query+'.focus();'+query+'.select()');await page.send('Input.insertText',{text:value});},
  async click(){const box=await page.evaluate('(()=>{const r='+query+'.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()');await page.send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,...box});await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,...box});}
 };}
 async close(){this.ws.close();}
}
const data=await fs.mkdtemp(path.join(os.tmpdir(),'arc-password-runtime-'));
const logPath=path.join(data,'app.log');
const server=createServer(async(req,res)=>{
 for await(const _ of req){}
 res.setHeader('Content-Type','text/html;charset=utf-8');
 if(req.url.startsWith('/success')) {res.end('<title>Signed in</title><h1>Signed in</h1>');return;}
 res.end('<title>Login fixture</title><form method="post" action="/success"><input id="username" name="username" autocomplete="username"><input id="password" name="password" type="password" autocomplete="current-password"><button id="login">Se connecter</button></form>');
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
const profile='password-fixture';
const state={language:'fr',onboardingComplete:true,sidebarWidth:250,sidebarHidden:false,themeAppearance:'dark',savePasswords:true,automaticSignIn:false,formSuggestions:true,passwordManagerID:'native',profiles:[{id:profile,name:'Personnel'}],spaces:[{id:'space',name:'Personnel',color:'#B5AED9',icon:'sf:key',profileID:profile,selectedTabID:'tab'}],tabs:[{id:'tab',spaceID:'space',url:origin+'/login',title:'Login fixture',pinned:true,favorite:false}],folders:[],closedTabs:[],activeSpaceID:'space'};
await fs.writeFile(path.join(data,'session.json'),JSON.stringify(state));
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const appPath=process.env.PASSWORD_RUNTIME_APP;assert(appPath);
const log=await fs.open(logPath,'w');
const fixtureRoot=process.env.PASSWORD_MANAGER_FIXTURES;
const switches=fixtureRoot?['--disable-component-update','--load-extension='+path.join(fixtureRoot,'proton')+','+path.join(fixtureRoot,'onepassword')]:[];
const app=spawn(path.join(appPath,'Contents/MacOS/Arc Reborn'),switches,{env:{...process.env,BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_DEBUG_PORT:String(port)},stdio:['ignore',log.fd,log.fd]});
const exit=new Promise(r=>app.once('exit',(code,signal)=>r({code,signal})));let seq=0,browser;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,timeout=20000){let end=Date.now()+timeout;while(Date.now()<end){const v=await fn().catch(()=>null);if(v)return v;await sleep(150);}throw Error('Timeout');}
async function logs(){return fs.readFile(logPath,'utf8');}
async function command(s){const value=(++seq)+' '+s;await fs.writeFile(path.join(data,'command'),value);}
async function marker(s,prior=0){await until(async()=>(await logs()).split(s).length-1>prior);}
function pass(s){console.log('PASS '+s);}
try{
 await until(async()=>fetch(`http://127.0.0.1:${port}/json/version`).then(r=>r.json()));
 const target=await until(async()=>{const targets=await fetch(`http://127.0.0.1:${port}/json/list`).then(r=>r.json());return targets.find(p=>p.url.startsWith(origin));});
 browser=await CDP.connect(target.webSocketDebuggerUrl);await browser.send('Page.enable');const page=browser;
 if(fixtureRoot){await until(async()=>await page.evaluate(()=>document.documentElement.dataset.protonFixture==='active'&&document.documentElement.dataset.onepasswordFixture==='active'));pass('both isolated manager fixtures are initially active');}
 async function login(user,pwd){await page.goto(origin+'/login');await page.locator('#username').fill(user);await page.locator('#password').fill(pwd);await page.locator('#login').click();await page.waitForURL(origin+'/success');}
 await login('clara@example.test','ArcFixture-Save-482!');await marker('PROMPT save');pass('native prompt after a real form submission');
 await command('save');await marker('ACTION save');
 await page.goto(origin+'/login');await page.locator('#username').click();await until(async()=>await page.locator('#password').inputValue()==='ArcFixture-Save-482!');pass('saved password fills again in its original profile');
 await login('clara@example.test','ArcFixture-Updated-584!');await marker('PROMPT update');await command('save');await marker('ACTION save',1);
 await page.goto(origin+'/login');await page.locator('#username').click();await until(async()=>await page.locator('#password').inputValue()==='ArcFixture-Updated-584!');pass('native update replaces the password after consent');
 await command('settings');await marker('SETTINGS');await command('external');await marker('MANAGER ghmbeldphafepmbegfdlkpapadhbakde');
 await page.goto(origin+'/login');await sleep(800);assert.equal(await page.locator('#password').inputValue(),'');assert.equal(await page.locator('#username').inputValue(),'');pass('external mode stops filling existing Chromium logins');
 if(fixtureRoot){assert.equal(await page.evaluate(()=>document.documentElement.dataset.protonFixture),'active');assert.equal(await page.evaluate(()=>document.documentElement.dataset.onepasswordFixture),undefined);pass('only the chosen manager extension remains active');}
 const before=(await logs()).split('PROMPT save').length-1;
 await login('external@example.test','ArcFixture-External-793!');await sleep(1200);assert.equal((await logs()).split('PROMPT save').length-1,before);pass('external mode shows no native save prompt');
 await command('settings');await marker('SETTINGS',1);await command('native');await marker('MANAGER native');
 if(fixtureRoot){await page.goto(origin+'/login');await until(async()=>await page.evaluate(()=>document.documentElement.dataset.onepasswordFixture==='active'));pass('returning to the native vault restores extensions paused by this feature');}
 await login('declined@example.test','ArcFixture-Decline-371!');await marker('PROMPT save',before);
 await command('later');await marker('ACTION later');
 await page.goto(origin+'/login');await sleep(700);assert.notEqual(await page.locator('#username').inputValue(),'declined@example.test');pass('declining does not replace existing saved credentials');
 const preNever=(await logs()).split('PROMPT save').length-1;
 await login('never@example.test','ArcFixture-Never-981!');await marker('PROMPT save',preNever);await command('never');await marker('ACTION never');
 const postNever=(await logs()).split('PROMPT save').length-1;
 await login('no-prompt@example.test','ArcFixture-NoPrompt-397!');await sleep(1000);assert.equal((await logs()).split('PROMPT save').length-1,postNever);pass('never for this site suppresses future save prompts');
 await command('quit');const result=await Promise.race([exit,sleep(25000).then(()=>{throw Error('Quit timeout');})]);assert.equal(result.code,0);await browser.close();browser=null;pass('clean shutdown');
 const session=JSON.parse(await fs.readFile(path.join(data,'session.json'),'utf8'));assert.equal(session.passwordManagerID,'native');pass('manager selection persists');
 console.log('DATA '+data);
}catch(error){console.error(await logs());console.error('DATA '+data);throw error;}finally{if(browser)await browser.close().catch(()=>{});if(app.exitCode===null){app.kill('SIGTERM');await exit;}await log.close();await new Promise(r=>server.close(r));}
