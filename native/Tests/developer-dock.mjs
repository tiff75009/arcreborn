import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve('native/build'), data=await fs.mkdtemp(path.join(os.tmpdir(),'browser-dock-'));
const server=createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end('<!doctype html>'+(req.url==='/wide'?'':'<meta name="viewport" content="width=device-width,initial-scale=1">')+'<title>Dock Test</title><style>body{background:#eee;margin:0}#picked{position:absolute;left:30px;top:70px;width:180px;height:90px;background:#60a0ee}#link{position:absolute;left:250px;top:20px}</style><a id="link" href="/wide">Hover this link</a><button id="picked" onclick="window.clicked=true">Inspect this element</button>');});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const origin=`http://127.0.0.1:${server.address().port}/`;
const log=await fs.open(path.join(data,'app.log'),'w');
const app=spawn(path.join(root,'DeveloperDockTest.app/Contents/MacOS/Arc Reborn'),[],{env:{...process.env,BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_DEBUG_PORT:String(port),BROWSER_DOCK_TEST_URL:origin},stdio:['ignore',log.fd,log.fd]});
let exited=false; const exit=new Promise(r=>app.on('exit',(code,signal)=>{exited=true;r({code,signal});}));
const sockets=[]; let commandID=0;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,timeout=8000){const end=Date.now()+timeout;let last;while(Date.now()<end){try{const value=await fn();if(value)return value;}catch(e){last=e;}await delay(80);}throw Error('Timed out '+(last||''));}
async function command(name){await fs.writeFile(path.join(data,'command'),`${++commandID} ${name}`);}
async function state(){return JSON.parse(await fs.readFile(path.join(data,'snapshot.json'),'utf8'));}
async function targets(){return (await fetch(`http://127.0.0.1:${port}/json/list`)).json();}
async function connect(target){const ws=new WebSocket(target.webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});sockets.push(ws);let id=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data);if(pending.has(m.id)){const [r,j]=pending.get(m.id);pending.delete(m.id);m.error?j(Error(JSON.stringify(m.error))):r(m.result);}};const send=(method,params={})=>new Promise((r,j)=>{const current=++id;const timeout=setTimeout(()=>{pending.delete(current);j(Error('CDP timeout: '+method));},5000);pending.set(current,[value=>{clearTimeout(timeout);r(value);},error=>{clearTimeout(timeout);j(error);}]);ws.send(JSON.stringify({id:current,method,params}));});return {send,evaluate:async expression=>{const result=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;}};}
let failure;
try {
 const page=await connect(await until(async()=>(await targets()).find(x=>x.url===origin)));
 await until(async()=>(await state()).views.length===1);
 // A real link hover creates Chromium's status bubble. Its window used to
 // receive width=0 during a transient DevTools layout and abort the browser.
 await page.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:280,y:28});
 await delay(200);
 await command('console');
 await until(async()=>{const s=await state();return s.open&&s.views.length===2&&s.views.every(x=>x.window===s.window&&!x.hidden)&&s.visibleWindows.length===1;});
 console.log('PASS Console embedded beside the page in the same visible window');
 const firstToolsTarget=await until(async()=>(await targets()).find(x=>x.url.startsWith('devtools://')));
 let tools=await connect(firstToolsTarget);
 await until(async()=>await tools.evaluate("!!document.querySelector('.root-view')"),15000);
 await until(async()=>await tools.evaluate("!!globalThis.__browserEmbeddedReady"));
 await tools.evaluate("globalThis.__browserDevToolsHost(JSON.stringify({type:'bounds',x:2000,y:0,width:375,height:667}))");
 await delay(150);
 assert.equal(await page.evaluate('innerWidth>0&&innerHeight>0'),true);
 await tools.evaluate("globalThis.__browserDevToolsHost(JSON.stringify({type:'bounds',x:0,y:0,width:0,height:0}))");
 await delay(150);
 assert.equal(await page.evaluate('innerWidth>0&&innerHeight>0'),true);
 await tools.evaluate("import('/bundled/panels/emulation/emulation.js').then(E=>E.InspectedPagePlaceholder.InspectedPagePlaceholder.instance().update())");
 console.log('PASS Transient empty/out-of-container DevTools bounds keep the page and status bubble alive');
 const selectedPanel="(async()=>{const UI=await import('/bundled/ui/legacy/legacy.js');return UI.InspectorView.InspectorView.instance().tabbedPane.selectedTabId;})()";
 await until(async()=>await tools.evaluate(selectedPanel)==='console');
 await command('network');await until(async()=>await tools.evaluate(selectedPanel)==='network');
 console.log('PASS Console/Network switch inside the existing dock');
 const deviceButton="(async()=>{const UI=await import('/bundled/ui/legacy/legacy.js');const toolbar=UI.InspectorView.InspectorView.instance().tabbedPane.leftToolbar();const button=toolbar.querySelector('[data-browser-device-toggle]')||toolbar.shadowRoot.querySelector('[data-browser-device-toggle]');if(!button||button.getBoundingClientRect().width<10)throw Error('Device button is not visible');const r=button.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()";
 const clickDevice=async()=>{let point;await until(async()=>{const first=await tools.evaluate(deviceButton);await delay(150);point=await tools.evaluate(deviceButton);return first.x===point.x&&first.y===point.y;});await tools.send('Input.dispatchMouseEvent',{type:'mouseMoved',...point});await tools.send('Input.dispatchMouseEvent',{type:'mousePressed',...point,button:'left',clickCount:1});await tools.send('Input.dispatchMouseEvent',{type:'mouseReleased',...point,button:'left',clickCount:1});};
 await clickDevice();
 await until(async()=>await page.evaluate('navigator.maxTouchPoints')===1);
 await tools.evaluate("import('/bundled/models/emulation/emulation.js').then(E=>{const m=E.DeviceModeModel.DeviceModeModel.instance();m.setWidthAndScaleToFit(375);m.setHeightAndScaleToFit(667);})");
 await until(async()=>await page.evaluate('innerWidth===375&&innerHeight===667'));
 assert.equal(await page.evaluate("matchMedia('(pointer: coarse)').matches&&navigator.userAgent.includes('Mobile')&&devicePixelRatio===2"),true);
 // Removing an existing meta element does not clear Blink's viewport description.
 // A fresh page without the meta proves that real mobile layout is enabled.
 await page.send('Page.navigate',{url:origin+'wide'});
 await until(async()=>await page.evaluate("location.pathname==='/wide'&&document.readyState==='complete'&&innerWidth===980"));
 await page.send('Page.navigate',{url:origin});
 await until(async()=>await page.evaluate("location.pathname==='/'&&document.readyState==='complete'&&innerWidth===375"));
 await until(async()=>{const s=await state();return s.views.some(v=>v.width<=375&&v.height<700&&v.x>0&&v.y>=0)&&s.visibleWindows.length===1;});
 console.log('PASS Device button enables real mobile emulation: viewport meta, touch, UA, DPR and editable dimensions');
 await command('close');await until(async()=>!(await state()).open&&(await state()).views.length===1);
 await command('console');
 tools=await connect(await until(async()=>(await targets()).find(x=>x.url.startsWith('devtools://')&&x.id!==firstToolsTarget.id)));
 await until(async()=>await tools.evaluate('!!globalThis.__browserEmbeddedReady'));
 await until(async()=>await page.evaluate('navigator.maxTouchPoints===1&&innerWidth===375'));
 assert.equal((await state()).visibleWindows.length,1);
 console.log('PASS Console reopens with the saved mobile mode in the same window');
 await clickDevice();
 await until(async()=>await page.evaluate('navigator.maxTouchPoints===0&&innerWidth>500'));
 await delay(1400); // Regression: the renderer's old Android scrollbar timer crashed after returning to desktop.
 assert.equal(await page.evaluate('navigator.maxTouchPoints'),0);
 console.log('PASS Device button restores the desktop viewport');
 await command('resize');await until(async()=>{const s=await state();return s.views.length===2&&s.views.every(v=>v.width<=820&&v.height<=600);});
 await command('hide');await until(async()=>(await state()).views.every(x=>x.hidden));
 await command('show');await until(async()=>(await state()).views.every(x=>!x.hidden));
 console.log('PASS Dock follows resizing and tab visibility');
 await tools.evaluate('InspectorFrontendHost.closeWindow()');await until(async()=>!(await state()).open&&(await state()).views.length===1);
 await command('inspect');await until(async()=>{const s=await state();return s.tool==='inspect'&&!s.open&&s.views.length===1;});
 await page.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:90,y:100});
 await page.send('Input.dispatchMouseEvent',{type:'mousePressed',x:90,y:100,button:'left',clickCount:1});
 await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:90,y:100,button:'left',clickCount:1});
 await until(async()=>(await state()).open&&(await state()).views.length===2);
 const inspector=await connect(await until(async()=>(await targets()).find(x=>x.url.startsWith('devtools://')&&x.id!==firstToolsTarget.id)));
 await until(async()=>await inspector.evaluate("!!document.querySelector('.root-view')"),15000);
 const selectedNode="(async()=>{const SDK=await import('/bundled/core/sdk/sdk.js');const UI=await import('/bundled/ui/legacy/legacy.js');return UI.Context.Context.instance().flavor(SDK.DOMModel.DOMNode)?.getAttribute('id');})()";
 await until(async()=>await inspector.evaluate(selectedNode)==='picked');
 assert.notEqual(await page.evaluate('window.clicked'),true);
 assert.equal((await state()).visibleWindows.length,1);
 console.log('PASS Inspect selects the actual clicked element, then opens Elements without triggering the page click');
 await command('inspect');await until(async()=>(await state()).tool==='inspect');
 await until(async()=>await inspector.evaluate("(async()=>{const SDK=await import('/bundled/core/sdk/sdk.js');return SDK.TargetManager.TargetManager.instance().models(SDK.OverlayModel.OverlayModel).some(model=>model.inspectModeEnabled());})()"));
 await page.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:95,y:105});
 await page.send('Input.dispatchMouseEvent',{type:'mousePressed',x:95,y:105,button:'left',clickCount:1});
 await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:95,y:105,button:'left',clickCount:1});
 await until(async()=>(await state()).tool==='elements');
 assert.notEqual(await page.evaluate('window.clicked'),true);
 console.log('PASS Selection also works with an already-open inspector');
 await command('close');await until(async()=>!(await state()).open);
 await command('inspect');await until(async()=>(await state()).tool==='inspect');
 await page.send('Input.dispatchKeyEvent',{type:'rawKeyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27,nativeVirtualKeyCode:53});
 await page.send('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27,nativeVirtualKeyCode:53});
 await until(async()=>(await state()).tool==='');
 console.log('PASS Escape cancels selection without opening a panel');
} catch(error){failure=error;console.error(error);console.error(await state().catch(()=>({})));}
finally {sockets.forEach(s=>s.close());await command('quit');const result=await Promise.race([exit,delay(6000).then(()=>null)]);if(!result&&!exited)app.kill('SIGTERM');const finished=await exit;if(finished.code!==0){failure ||= Error('Unclean test shutdown: '+JSON.stringify(finished));console.error(failure);}else console.log('PASS Orderly shutdown');await log.close();await new Promise(r=>server.close(r));console.log('Isolated profile: '+data);}
if(!failure){
 const directory=path.join(data,'Chromium','Diagnostics');
 const [run]=await fs.readdir(directory);
 const records=(await fs.readFile(path.join(directory,run,'events.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);
 const mobile=records.filter(r=>r.event==='devtools.frontend'&&r.detail.event==='device.state').map(r=>r.detail.enabled);
 assert.ok(mobile.includes(true)&&mobile.includes(false));
 assert.ok(records.some(r=>r.event==='cef.loaded-image'&&r.uuid));
 assert.ok(records.some(r=>r.event==='app.quit-request'));
 assert.ok(!(await fs.readFile(path.join(directory,run,'process.log'),'utf8')).includes('Unable to initialize logging'));
 console.log('PASS Persistent diagnostics record mobile transitions, engine identity and shutdown');
}
if(failure)process.exitCode=1;
