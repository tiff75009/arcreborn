// SPDX-License-Identifier: MPL-2.0
// Launch an isolated native browser after building: node native/Demo/downloads.mjs
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, mkdir, writeFile, copyFile, utimes, open, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const native = fileURLToPath(new URL('../',import.meta.url));
const updateDemo = process.argv.includes('--update');
const mediaDemo = process.argv.includes('--media') || updateDemo;
const root = await mkdtemp(path.join(tmpdir(),'arc-essai-telechargements-'));
const folder = path.join(root,'Téléchargements d’essai');
await mkdir(folder);
await mkdir(path.join(root,'Autre dossier'));
const samples = ['Présentation Arc Reborn.jpg','Capture du navigateur.jpg','Notes de repérage.txt','Carnet du jour.txt'];
const records = [];
for (const [index,name] of samples.entries()) {
  const file = path.join(folder,name);
  const data = Buffer.from('Fichier de démonstration : '+name+'\n');
  const date = new Date(Date.now()-(samples.length-index)*3600000);
  if (index < 2) {
    const source = index === 0 ? '../../docs/showcase/welcome.jpg' : '../../docs/showcase/capture.jpg';
    await copyFile(fileURLToPath(new URL(source,import.meta.url)),file);
  } else { await writeFile(file,data); }
  await utimes(file,date,date);
  records.push({id:'demo-'+index,name,path:file,source:'',profileID:'atelier',date:date.getTime()/1000-978307200,
    received:data.length,total:data.length,state:'complete',speed:0,unread:index === samples.length-1});
}
await writeFile(path.join(root,'library.json'),JSON.stringify({mediaEnabled:false,downloads:records}));
const instructions = updateDemo
  ? '<p>Survole <b>Nouvelle version disponible</b>, en bas de la barre latérale. La carte se déplie au-dessus des onglets. Essaie de sortir puis de revenir rapidement, de défiler tout en bas de la liste, et de changer entre les espaces <b>Bleu</b>, <b>Rose</b> et <b>Vert</b>.</p><p>Active aussi le masquage automatique. La carte doit rester accessible tant que la souris est dedans. Le bouton <b>Redémarrer et mettre à jour</b> simule uniquement son état pendant une seconde : aucun téléchargement ni redémarrage dans cet essai.</p>'
  : mediaDemo
  ? '<p>Clique sur le panier en bas à gauche, choisis <b>Téléchargements</b>, puis reviens sur <b>Médias</b> : les deux cartes prennent leur élan et sautent à tour de rôle. Repasse ensuite sur <b>Téléchargements</b> pour voir la flèche et le cercle rebondir indépendamment. Choisis aussi <b>Espaces</b> : les deux pages se rejoignent, se repoussent puis reviennent au repos.</p><p>Un clic sur une section déjà active ne relance pas son animation. Essaie aussi les espaces <b>Bleu</b>, <b>Rose</b> et <b>Vert</b> pour comparer la couleur des cartes.</p>'
  : '';
const page = `<!DOCTYPE html>
<html lang="fr"><meta charset="utf-8"><title>Essai des téléchargements</title><link rel="icon" href="/favicon.svg" type="image/svg+xml">
<style>:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#211e29;color:#f2eff5;font:16px/1.55 system-ui}main{width:min(530px,86%);padding:32px 0}h1{font-size:clamp(28px,4vw,40px);line-height:1.15;letter-spacing:-.05em;margin:0 0 16px}p{color:#c8c1d1}nav{display:flex;gap:10px;flex-wrap:wrap;margin:22px 0 30px}a{padding:10px 15px;background:#65507f;color:white;border-radius:9px;text-decoration:none;font-weight:600}a:hover{background:#75608e}a:focus-visible{outline:2px solid #e4cef7;outline-offset:2px}ul{padding-left:20px;color:#d1cbd7}li+li{margin-top:10px}</style>
<main><h1>${mediaDemo ? "Essai des icônes de la bibliothèque" : "Essai des téléchargements"}</h1>${instructions}${mediaDemo ? '<p>Ouvre aussi <b>Onglets archivés</b> : la corbeille, son trait blanc et son couvercle rebondissent séparément. Pour rejouer le mouvement, passe d’abord sur une autre rubrique.</p><p>Choisis <b>Médias</b>, <b>Téléchargements</b>, <b>Espaces</b> ou <b>Onglets archivés</b>, ferme le panneau avec sa flèche de retour, puis rouvre le panier : tu dois retrouver la rubrique choisie.</p>' : ''}
<p>Lance le transfert lent pour suivre la flèche jusqu’à la bibliothèque et essayer les commandes de pause et de reprise.</p>
<nav><a href="/rapide" download>Petit fichier</a><a href="/lent" download>Transfert lent</a></nav>
<ul><li>Survole le panier en bas à gauche : seuls ses petits objets grossissent, puis les quatre fichiers apparaissent de bas en haut, sans cadre.  <b>Carnet du jour.txt</b> est le plus récent et reste en bas.</li>
<li>Fais défiler la liste loin de l’onglet actif : la flèche du haut ramène cet onglet en haut de la liste. Choisis ensuite un onglet en bas, remonte la liste et essaie la flèche du bas. Reprends le défilement pendant le retour pour interrompre son animation.</li>
<li>Dans <b>Réglages → Général → Téléchargements</b>, choisis un autre dossier ou active la demande d’emplacement.</li>
<li>Active le masquage automatique de la barre latérale et lance un autre transfert pour essayer l’animation.</li></ul></main></html>`;
const chunk = Buffer.alloc(32*1024,65);
const server = createServer((req,res)=>{
  if (req.url === '/favicon.svg') {
    res.writeHead(200,{'Content-Type':'image/svg+xml'});
    res.end('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#7657ff"/><path d="M8 25 14 7h4l6 18h-4l-1-4h-6l-1 4zm6-8h4l-2-6z" fill="white"/></svg>'); return;
  }
  if (req.url === '/' || req.url.startsWith('/?')) { res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'}); res.end(page); return; }
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
const spaces = mediaDemo ? [['Bleu',updateDemo ? '#3024FF' : '#555599'],['Rose','#9B537D'],['Vert','#4C8268']].map(([name,color],index)=>({
  id:'couleur-'+index,name,color,profileID:'atelier',selectedTabID:'essai-'+index,icon:'sf:circle.fill'
})) : [space];
const tabs = spaces.map(item=>({id:item.selectedTabID,title:mediaDemo ? 'Essai des icônes de la bibliothèque' : 'Essai des téléchargements',url,spaceID:item.id,pinned:false,favorite:false}));
if (updateDemo) {
  for (const item of spaces) for (let index=1;index<=36;index++) tabs.push({id:item.id+'-tab-'+index,title:'Onglet d’essai '+String(index).padStart(2,'0')+' · Café & idées',url:url+'?onglet='+index,spaceID:item.id,pinned:false,favorite:false});
}
const closedTabs = mediaDemo ? [false,true].map((automatic,index)=>({
  id:'archive-'+index,spaceID:spaces[0].id,url:url+'?archive='+index,title:automatic ? 'Archive automatique · Café & idées' : 'Archive manuelle · Café & idées',
  pinned:false,favorite:false,...(automatic ? {autoArchivedAt:Date.now()/1000-978307200} : {})
})) : [];
await writeFile(path.join(root,'session.json'),JSON.stringify({language:'fr',onboardingComplete:true,themeAppearance:'dark',
  activeSpaceID:spaces[0].id,profiles:[{id:'atelier',name:'Essai isolé'}],spaces,tabs,folders:[],closedTabs,
  sidebarHidden:false,sidebarWidth:245}));
const log = await open(path.join(root,'app.log'),'w');
try {
  const env = {...process.env,BROWSER_NATIVE_TEST_DATA:root,BROWSER_NATIVE_TEST_DOWNLOADS:folder,BROWSER_NATIVE_TEST_BACKGROUND:'0',BROWSER_NATIVE_HOST_DIAGNOSTICS:path.join(root,'windows.snapshot.json')};
  delete env.BROWSER_NATIVE_TEST_AUTOCLOSE;
  if (updateDemo) env.BROWSER_NATIVE_TEST_UPDATE = '1';
  else delete env.BROWSER_NATIVE_TEST_UPDATE;
  const app = spawn(path.join(native,'build','Arc Reborn.app','Contents','MacOS','Arc Reborn'),[],{env,stdio:['ignore',log.fd,log.fd]});
  console.log(JSON.stringify({pid:app.pid,profile:root,url}));
  await new Promise((resolve,reject)=>{app.once('exit',resolve);app.once('error',reject);});
} finally { await log.close();server.closeAllConnections();server.close();await rm(root,{recursive:true,force:true}); }
