// SPDX-License-Identifier: MPL-2.0
// Real Chromium playback in a throwaway native profile. Optional argument: an
// H.264/AAC MP4 to use instead of the generated sample. Requires Node and ffmpeg.
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, readFile, rm, mkdir, open, copyFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const native=fileURLToPath(new URL('../',import.meta.url));
const scratch=await mkdtemp(path.join(os.tmpdir(),'browser-native-test-media-'));
const profile=path.join(scratch,'profile'); await mkdir(profile);
const ffmpeg=(...args)=>execFileSync('ffmpeg',['-nostdin','-loglevel','error','-y',...args],{cwd:scratch});
let app,server,log,timer;
try {
  if(process.argv[2]) await copyFile(path.resolve(process.argv[2]),path.join(scratch,'sample.mp4'));
  else ffmpeg('-f','lavfi','-i','testsrc2=size=144x108:rate=24','-f','lavfi','-i','sine=frequency=440','-t','2','-c:v','libx264','-profile:v','main','-pix_fmt','yuv420p','-c:a','aac','sample.mp4');
  ffmpeg('-i','sample.mp4','-c','copy','-movflags','frag_keyframe+empty_moov+default_base_moof','fragment.mp4');
  ffmpeg('-i','sample.mp4','-c','copy','-hls_segment_type','fmp4','-hls_time','2','-hls_playlist_type','vod','stream.m3u8');
  ffmpeg('-i','sample.mp4','-t','2','-vf','scale=160:-2','-c:v','libvpx-vp9','-deadline','realtime','-cpu-used','8','-c:a','libopus','control.webm');
  const matrix=process.env.BROWSER_MEDIA_TEST_MATRIX==='1';
  if(matrix) {
    const source=['-i','sample.mp4','-t','2','-vf','scale=160:-2'];
    ffmpeg(...source,'-pix_fmt','yuv420p','-c:v','libvpx','-deadline','realtime','-c:a','libopus','vp8.webm');
    ffmpeg(...source,'-pix_fmt','yuv420p','-c:v','libsvtav1','-preset','12','-c:a','libopus','av1.webm');
    ffmpeg(...source,'-pix_fmt','yuv420p10le','-c:v','libx265','-preset','ultrafast','-x265-params','log-level=error','-tag:v','hvc1','-c:a','aac','hevc10.mp4');
    ffmpeg(...source,'-pix_fmt','yuv420p','-c:v','libx265','-preset','ultrafast','-x265-params','log-level=error','-tag:v','hvc1','-c:a','aac','hevc.mp4');
  }
  const script=async function (liveStream,matrix) {
    const mime='video/mp4; codecs="avc1.4d401e, mp4a.40.2"';
    const withTimeout=(operation,ms)=>new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error('Playback timeout')),ms);
      Promise.resolve(operation).then(resolve,reject).finally(()=>clearTimeout(timer));
    });
    const results={fileSupport:document.createElement('video').canPlayType(mime),mseSupport:MediaSource.isTypeSupported(mime),playback:{}};
    for (const name of ['control.webm','sample.mp4','MSE','stream.m3u8',...(matrix?['vp8.webm','av1.webm','hevc.mp4','hevc10.mp4']:[]),...(liveStream?['liveHLS']:[])]) {
      const v=document.createElement('video');v.muted=true;document.body.append(v);
      if(name==='liveHLS')v.crossOrigin='anonymous';
      let objectURL,poll;
      try {
        if(name==='MSE'){
          if(!results.mseSupport) throw Error('MSE H.264/AAC unsupported');
          const media=new MediaSource(); const opened=new Promise(r=>media.addEventListener('sourceopen',r,{once:true}));
          v.src=objectURL=URL.createObjectURL(media); await withTimeout(opened,5000);
          const source=media.addSourceBuffer(mime);
          const data=await (await fetch('fragment.mp4')).arrayBuffer();
          await withTimeout(new Promise((resolve,reject)=>{source.addEventListener('updateend',resolve,{once:true});source.addEventListener('error',()=>reject(Error('SourceBuffer error')),{once:true});source.appendBuffer(data)}),5000);media.endOfStream();
        } else v.src=name==='liveHLS'?liveStream:name;
        await withTimeout(v.play().then(()=>new Promise((resolve,reject)=>{
          const check=()=>{if(v.error)return reject(Error(v.error.message)); if(v.currentTime>=0.25 && v.getVideoPlaybackQuality().totalVideoFrames>0)return resolve(); if(v.ended)return reject(Error('No decoded frame'));poll=setTimeout(check,60)};check();
        })),name==='liveHLS'?15000:8000);
        results.playback[name]={seconds:v.currentTime,frames:v.getVideoPlaybackQuality().totalVideoFrames-v.getVideoPlaybackQuality().droppedVideoFrames,width:v.videoWidth,audioBytes:v.webkitAudioDecodedByteCount,videoBytes:v.webkitVideoDecodedByteCount};
      } catch(e) { results.playback[name]={error:String(e),mediaError:v.error?.code,detail:v.error?.message}; }
      finally {clearTimeout(poll);v.pause();v.removeAttribute('src');v.load();v.remove();if(objectURL)URL.revokeObjectURL(objectURL)}
    }
    await fetch('/result',{method:'POST',body:JSON.stringify(results)});
  };
  const liveStream=process.env.BROWSER_MEDIA_TEST_HLS_URL || '';
  if(liveStream && new URL(liveStream).protocol!=='https:') throw Error('Live stream must use HTTPS');
  let finish; const report=new Promise(r=>{finish=r});
  server=createServer(async(req,res)=>{
    const name=new URL(req.url,'http://localhost').pathname.slice(1);
    if(req.method==='POST'&&name==='result'){
      let data=''; for await(const chunk of req)data+=chunk;
      res.end('ok');finish(JSON.parse(data));return;
    }
    if(!name){res.setHeader('Content-Type','text/html');res.end('<title>Arc media test</title><body><script>('+script.toString()+')('+JSON.stringify(liveStream).replaceAll('<','\\u003c')+','+matrix+')</script>');return}
    if(!/^((?:control|vp8|av1)\.webm|(?:sample|hevc(?:10)?|fragment|init)\.mp4|stream(?:\.m3u8|\d+\.m4s))$/.test(name)){res.writeHead(404).end();return}
    try{
      const data=await readFile(path.join(scratch,name));const range=req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
      const mime=name.endsWith('webm')?'video/webm':name.endsWith('m3u8')?'application/vnd.apple.mpegurl':'video/mp4';
      res.setHeader('Content-Type',mime);res.setHeader('Accept-Ranges','bytes');
      if(range){const start=Number(range[1]),end=Math.min(Number(range[2]||data.length-1),data.length-1);
        if(start>end){res.writeHead(416).end();return}res.setHeader('Content-Range',`bytes ${start}-${end}/${data.length}`);res.writeHead(206);res.end(data.subarray(start,end+1));}
      else res.end(data);
    }catch{res.writeHead(404).end()}
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
  await writeFile(path.join(profile,'session.json'),JSON.stringify({onboardingComplete:true,language:'fr',sidebarHidden:false,sidebarWidth:228,activeSpaceID:'space',profiles:[{id:'p',name:'Test'}],spaces:[{id:'space',profileID:'p',name:'Test',icon:'◈',color:'#8871C5',selectedTabID:'media'}],tabs:[{id:'media',spaceID:'space',url:origin,title:'Média',pinned:false,favorite:false}],folders:[],closedTabs:[]}));
  log=await open(path.join(scratch,'app.log'),'w');
  const bundle=process.env.BROWSER_SMOKE_APP || path.join(native,'build/development/Arc Reborn.app');
  app=spawn(path.join(bundle,'Contents/MacOS/Arc Reborn'),['--disable-component-update'],{env:{...process.env,BROWSER_NATIVE_TEST_DATA:profile,BROWSER_NATIVE_TEST_AUTOCLOSE:'55'},stdio:['ignore',log.fd,log.fd]});
  const result=await Promise.race([report,new Promise((_,reject)=>{app.once('error',reject);app.once('exit',(c)=>reject(Error('Browser exited: '+c)));timer=setTimeout(()=>reject(Error('No playback report')),50000)})]);
  console.log(JSON.stringify(result,null,2));
  assert.ok(result.fileSupport && result.mseSupport,'MP4/MSE support missing');
  for(const [name,p] of Object.entries(result.playback)){
    assert.ok(p.seconds>0 && p.frames>0 && p.width>0 && p.audioBytes>0,name+': '+JSON.stringify(p));
  }
} finally {clearTimeout(timer);if(app&&app.exitCode===null&&app.signalCode===null){const ended=new Promise(r=>app.once('exit',r));app.kill('SIGTERM');await ended}server?.closeAllConnections();server?.close();await log?.close();await rm(scratch,{recursive:true,force:true})}
