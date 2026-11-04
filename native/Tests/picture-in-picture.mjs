import {spawn,execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const data=await fs.mkdtemp(path.join(os.tmpdir(),'browser-pip-'));
// Local silent fixture: no network video, account or user profile is involved.
const movie=path.join(data,'video.webm');
execFileSync('/opt/homebrew/bin/ffmpeg',['-v','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-t','3','-c:v','libvpx','-b:v','450k','-c:a','libopus',movie]);
const media=await fs.readFile(movie);
const fixture=`<!doctype html><style>body{background:#242237;color:white;font:22px system-ui;padding:30px}video{width:640px;height:360px;border-radius:16px}</style><h1>Browser · Picture in Picture</h1><video controls loop src="/video.webm"></video><script>const video=document.querySelector('video');</script>`;
const server=createServer((req,res)=>{res.setHeader('Content-Type',req.url==='/video.webm'?'video/webm':'text/html');res.end(req.url==='/video.webm'?media:fixture)});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const origin=`http://127.0.0.1:${server.address().port}/`;
const log=await fs.open(path.join(data,'app.log'),'w');
const app=spawn(path.resolve('native/build/pip-check/PictureInPictureTest.app/Contents/MacOS/Arc Reborn'),[],{env:{...process.env,BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_DEBUG_PORT:String(port),BROWSER_PIP_TEST_URL:origin},stdio:['ignore',log.fd,log.fd]});
const exit=new Promise(r=>app.on('exit',(code,signal)=>r({code,signal})));let n=0,ws,failure;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn){for(let i=0;i<250;i++){try{const v=await fn();if(v)return v;}catch{}await delay(60);}throw Error('Timed out');}
const command=async name=>{await fs.writeFile(path.join(data,'command'),`${++n} ${name}`);await delay(130)};
const state=async()=>JSON.parse(await fs.readFile(path.join(data,'snapshot.json'),'utf8'));
try {
 const target=await until(async()=>(await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(x=>x.url===origin));
 ws=new WebSocket(target.webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
 let id=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data);if(pending.has(m.id)){pending.get(m.id)(m.result);pending.delete(m.id)}};
 const evaluate=expression=>new Promise(r=>{pending.set(++id,m=>r(m?.result?.value));ws.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,returnByValue:true,awaitPromise:true,userGesture:true}}))});
 const active=()=>evaluate('!!document.pictureInPictureElement');
 await evaluate('video.play().then(()=>true)');await until(()=>evaluate('video.readyState>=2'));
 await command('toggle');await until(active);await until(async()=>(await state()).result==='opened');
 await evaluate('video.play()');assert.equal(await evaluate('video.paused'),false);console.log('PASS Real Chromium PiP opens and plays the original video');
 await command('hide');await command('show');assert.equal(await active(),true);console.log('PASS Manual PiP remains open when switching tabs');
 await command('toggle');await until(async()=>!await active());await until(async()=>!(await state()).active);
 await command('hide');await until(active);await command('show');await until(async()=>!await active());
 console.log('PASS Automatic PiP opens on departure and returns inline on arrival');
 await delay(200);await command('disable');await command('hide');await delay(400);assert.equal(await active(),false);await command('show');await command('enable');
 await evaluate('video.pause()');await command('hide');await delay(400);assert.equal(await active(),false);await command('show');
 await evaluate('video.play()');await evaluate('video.muted=true');await command('hide');await delay(400);assert.equal(await active(),false);await command('show');await evaluate('video.muted=false');
 console.log('PASS Site opt-out, paused video and muted preview do not auto-open');
 await command('quick-switch');await delay(900);assert.equal(await active(),false);assert.equal((await state()).backendVisible,false);
 console.log('PASS Rapid tab return cancels pending automatic PiP without a stray browser window');
 await command('hide');await until(active);await evaluate('document.exitPictureInPicture()');await until(async()=>!(await state()).active);await delay(650);assert.equal(await active(),false);await command('show');
 console.log('PASS Closing PiP while away does not reopen it');
 await command('hide');await until(active);await command('focus-pip');await delay(300);await command('return-pip');await until(async()=>(await state()).returned);await until(async()=>!await active());
 assert.equal((await state()).backendVisible,false);console.log('PASS Chromium return button selects the AppKit tab without showing a backend window');
 await command('toggle');await until(active);await command('close-tab');await until(async()=>!(await state()).active);
 console.log('PASS Closing the source tab cleans up the PiP session');
}catch(error){failure=error;console.error(error);console.error(await state().catch(()=>({})));}
finally{ws?.close();await command('quit');const result=await Promise.race([exit,delay(5000).then(()=>null)]);if(!result)app.kill('SIGTERM');const ended=await exit;if(ended.code!==0)failure ||= Error(JSON.stringify(ended));await log.close();await new Promise(r=>server.close(r));console.log('Isolated profile: '+data)}
if(failure)process.exitCode=1;else console.log('PICTURE_IN_PICTURE_PASS');
