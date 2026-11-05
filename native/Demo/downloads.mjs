// SPDX-License-Identifier: MPL-2.0
// Launch an isolated native browser after building: node native/Demo/downloads.mjs
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, mkdir, writeFile, utimes, open, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const native = fileURLToPath(new URL('../',import.meta.url));
const root = await mkdtemp(path.join(tmpdir(),'arc-essai-telechargements-'));
const folder = path.join(root,'Téléchargements d’essai');
await mkdir(folder);
await mkdir(path.join(root,'Autre dossier'));
const samples = ['Références.txt','Repérages.txt','Palette.txt','Carnet du jour.txt'];
const records = [];
for (const [index,name] of samples.entries()) {
  const file = path.join(folder,name);
  const data = Buffer.from('Fichier de démonstration : '+name+'\n');
  const date = new Date(Date.now()-(samples.length-index)*3600000);
  await writeFile(file,data); await utimes(file,date,date);
  records.push({id:'demo-'+index,name,path:file,source:'',profileID:'atelier',date:date.getTime()/1000-978307200,
    received:data.length,total:data.length,state:'complete',speed:0,unread:index === samples.length-1});
}
await writeFile(path.join(root,'library.json'),JSON.stringify({mediaEnabled:false,downloads:records}));
const page = `<!DOCTYPE html>
<html lang="fr"><meta charset="utf-8"><title>Essai des téléchargements</title>
<style>:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#211e29;color:#f2eff5;font:16px/1.55 system-ui}main{width:min(530px,86%);padding:32px 0}h1{font-size:clamp(28px,4vw,40px);line-height:1.15;letter-spacing:-.05em;margin:0 0 16px}p{color:#c8c1d1}nav{display:flex;gap:10px;flex-wrap:wrap;margin:22px 0 30px}a{padding:10px 15px;background:#65507f;color:white;border-radius:9px;text-decoration:none;font-weight:600}a:hover{background:#75608e}a:focus-visible{outline:2px solid #e4cef7;outline-offset:2px}ul{padding-left:20px;color:#d1cbd7}li+li{margin-top:10px}</style>
<main><h1>Essai des téléchargements</h1>
<p>Lance le transfert lent pour suivre la flèche jusqu’à la bibliothèque et essayer les commandes de pause et de reprise.</p>
<nav><a href="/rapide" download>Petit fichier</a><a href="/lent" download>Transfert lent</a></nav>
<ul><li>Survole le bouton en bas à gauche. Parmi les quatre fichiers préparés, <b>Carnet du jour.txt</b> est le plus récent.</li>
<li>Dans <b>Réglages → Général → Téléchargements</b>, choisis un autre dossier ou active la demande d’emplacement.</li>
<li>Active le masquage automatique de la barre latérale et lance un autre transfert pour essayer l’animation.</li></ul></main></html>`;
const chunk = Buffer.alloc(32*1024,65);
const server = createServer((req,res)=>{
  if (req.url === '/') { res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'}); res.end(page); return; }
  if (!['/rapide','/lent'].includes(req.url)) { res.writeHead(404); res.end(); return; }
  const slow = req.url === '/lent';
  const name = slow ? 'Transfert lent.txt' : 'Essai rapide.txt';
  let remaining = slow ? 120 : 1;
  res.writeHead(200,{'Content-Type':'text/plain','Content-Length':remaining*chunk.length,
    'Content-Disposition':'attachment; filename="'+name+'"'});
  function send() { if (--remaining===0) res.end(chunk); else res.write(chunk); }
  send();
  if (remaining) {
    const timer = setInterval(send,180);
    res.once('close',()=>clearInterval(timer));
  }
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url = 'http://127.0.0.1:'+server.address().port+'/';
const space = {id:'studio',name:'Atelier',profileID:'atelier',selectedTabID:'essai',icon:'sf:sparkles',color:'#786884'};
const tab = {id:'essai',title:'Essai des téléchargements',url,spaceID:space.id,pinned:false,favorite:false};
await writeFile(path.join(root,'session.json'),JSON.stringify({language:'fr',onboardingComplete:true,themeAppearance:'dark',
  activeSpaceID:space.id,profiles:[{id:'atelier',name:'Essai isolé'}],spaces:[space],tabs:[tab],folders:[],closedTabs:[],
  sidebarHidden:false,sidebarWidth:245}));
const log = await open(path.join(root,'app.log'),'w');
try {
  const env = {...process.env,BROWSER_NATIVE_TEST_DATA:root,BROWSER_NATIVE_TEST_DOWNLOADS:folder,BROWSER_NATIVE_TEST_BACKGROUND:'0'};
  delete env.BROWSER_NATIVE_TEST_AUTOCLOSE;
  const app = spawn(path.join(native,'build','Arc Reborn.app','Contents','MacOS','Arc Reborn'),[],{env,stdio:['ignore',log.fd,log.fd]});
  console.log(JSON.stringify({pid:app.pid,profile:root,url}));
  await new Promise((resolve,reject)=>{app.once('exit',resolve);app.once('error',reject);});
} finally { await log.close();server.closeAllConnections();server.close();await rm(root,{recursive:true,force:true}); }
