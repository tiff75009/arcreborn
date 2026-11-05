// node native/Demo/space-dock.mjs — isolated development session, removed on quit.
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, writeFile, open, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const data = await mkdtemp(path.join(tmpdir(),'arc-space-dock-'));
const examples = [
  ['Orbite','🪐','#666484'], ['Détente','😊','#685770'],
  ['Lecture','none','#775264'], ['Atelier','sf:paintpalette.fill','#80594D'],
  ['Écriture','none','#6E6558'], ['Jardin','🌿','#4C705F'], ['Études','none','#4F667E'],
  ['Musique','sf:music.note','#635887'], ['Archives','none','#655E78'],
];
const spaces = examples.map(([name,icon,color],i)=>({id:'s'+i,name,icon,color,profileID:'essai'}));
const pages = [
  ['orbite','Résultats détaillés — Observatoire des étoiles','Survole les titres dans la barre latérale, puis la rangée des neuf espaces en bas.'],
  ['couleurs','Étude des couleurs et de la lumière','Renomme cet onglet en cliquant sur son titre après l’avoir sélectionné.'],
  ['musique','Écouter les sons du jardin','Tu peux annuler un renommage avec Échap.'],
];
const server = createServer((req,res)=>{
  const page = pages.find(([route])=>'/'+route === req.url);
  if (!page) { res.writeHead(404); res.end(); return; }
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});
  res.end(`<!doctype html><html lang="fr"><meta charset="utf-8"><title>${page[1]}</title>
    <style>html{color-scheme:dark}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#1d1b26;color:#f2eef7;font:16px/1.6 system-ui}main{max-width:36rem;padding:3rem}h1{line-height:1.1;letter-spacing:-.035em}p{color:#c3becf}</style>
    <main><h1>${page[1]}</h1><p>${page[2]}</p></main></html>`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
const tabs=pages.map(([id,title],sidebarOrder)=>({id,title,sidebarOrder,url:origin+'/'+id,spaceID:'s0',favorite:false,pinned:false}));
spaces[0].selectedTabID=tabs[0].id;
await writeFile(path.join(data,'session.json'),JSON.stringify({language:'fr',onboardingComplete:true,themeAppearance:'dark',
  interfaceStyle:'classic',sidebarWidth:228,sidebarHidden:false,activeSpaceID:spaces[0].id,
  profiles:[{id:'essai',name:'Essai des espaces'}],spaces,tabs,folders:[],closedTabs:[]}));
const bundle = fileURLToPath(new URL('../build/Arc Reborn.app/',import.meta.url));
const log = await open(path.join(data,'app.log'),'w');
const env = {...process.env,BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_TEST_DOWNLOADS:path.join(data,'Downloads'),BROWSER_NATIVE_TEST_BACKGROUND:'0'};
delete env.BROWSER_NATIVE_TEST_AUTOCLOSE;
try {
  const app = spawn(path.join(bundle,'Contents/MacOS/Arc Reborn'),[],{env,stdio:['ignore',log.fd,log.fd]});
  console.log(JSON.stringify({pid:app.pid,data}));
  await new Promise((ok,fail)=>{ app.on('error',fail); app.on('exit',ok); });
} finally { server.closeAllConnections(); server.close(); await log.close(); await rm(data,{recursive:true,force:true}); }
