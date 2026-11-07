// SPDX-License-Identifier: MPL-2.0
// Isolated drag-and-drop playground: node native/Demo/tab-movement.mjs
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,writeFile,open,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const native=fileURLToPath(new URL('../',import.meta.url));
const pageSplitTest=process.argv.includes('--page-split');
const handoffTest=process.argv.includes('--handoff');
const profile=await mkdtemp(path.join(tmpdir(),'arc-deplacements-'));
const server=createServer((req,res)=>{
  if(req.url.startsWith('/favicon.svg')) {res.writeHead(200,{'Content-Type':'image/svg+xml'});res.end('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="9" fill="#8773ed"/><path d="M8 16h16m-5-5 5 5-5 5" fill="none" stroke="white" stroke-width="3"/></svg>');return;}
  const current = tabs.find(tab=>new URL(tab.url).pathname === req.url.split('?')[0]);
  const isCarnet = current?.id === 'carnet';
  const title = (current?.title ?? 'Suite · Navigation conservée').replaceAll('&','&amp;').replaceAll('<','&lt;');
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});
  res.end(`<!doctype html><html lang="fr"><meta charset="utf-8"><title>${title}</title><link rel="icon" href="/favicon.svg"><style>:root{color-scheme:dark}body{margin:0;display:grid;place-items:center;min-height:100vh;background:${isCarnet?'#133b3b':'#211e2e'};color:#f4efff;font:16px/1.65 system-ui}main{max-width:560px;padding:40px}h1{font-size:36px;line-height:1.15;letter-spacing:-1px}li{margin:12px 0;color:#d1c8e4}a{color:#baa4ff}small{color:#a69bb8}</style><main><small>ARC REBORN · ESSAI ISOLÉ</small><h1>${title}</h1><ol>${pageSplitTest ? '<li>Glisse <b>Carnet de voyage à deux</b> depuis la barre latérale vers la page. Passe de gauche à droite en traversant le centre, puis relâche du côté choisi.</li><li>Pour annuler, reviens au centre ou appuie sur Échap. Le lien en bas permet de tester le geste après avoir navigué.</li><li>Visite le carnet, reviens sur cet onglet puis survole le carnet. Tu peux changer l’aperçu dans <b>Réglages → Interface</b>.</li>' : ''}<li>Deux groupes sont prêts : <b>01 + 02</b> et <b>04 + 05 + 06</b>. Attrape n’importe quel volet et dépose-le entre deux lignes. Tout le groupe doit suivre. Pour séparer un volet, utilise le menu de la vue partagée.</li><li>Survole le groupe inactif pour voir sa croix. Clique sur un de ses onglets, puis survole-le à nouveau pour voir les croix individuelles.</li><li>Déplace un onglet entre deux lignes : les autres doivent glisser pour lui faire de la place.</li><li>Dépose-le sur <b>Lectures</b>, puis ressors-le du dossier.</li><li>Déplace un onglet vers les favoris, puis redescends-le dans la liste.</li><li>Essaie le menu contextuel : épingler, déplacer dans un dossier ou dans l’espace <b>Voyages</b>.</li><li>Pour une vue partagée, marque une courte pause sur la moitié gauche ou droite d’un onglet. La place arrondie indique le côté ; déplace la souris à gauche ou à droite avant de relâcher.</li><li>Teste plusieurs déplacements rapides et le masquage automatique.</li></ol><p><a href="/suite">Naviguer vers une autre page avant de déplacer l’onglet →</a></p><small id="navigation"></small><script>const n=Number(sessionStorage.visites||0)+1;sessionStorage.visites=n;document.querySelector('#navigation').textContent='Page : '+location.pathname+' · Chargements : '+n;</script></main></html>`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url='http://127.0.0.1:'+server.address().port;
const spaces=[{id:'atelier',name:'Atelier',profileID:'essai',selectedTabID:pageSplitTest?'guide':'tab-1',color:'#78618c',icon:'sf:sparkles'},
{id:'voyages',name:'Voyages',profileID:'essai',selectedTabID:'voyage',color:'#477e9c',icon:'sf:airplane'}];
const folders=[{id:'lectures',spaceID:'atelier',name:'Lectures',collapsed:pageSplitTest,sidebarOrder:1},
{id:'idees',spaceID:'atelier',name:'Idées & café',collapsed:true,sidebarOrder:4},
{id:'projets',spaceID:'atelier',name:'Projets',collapsed:false,parentID:'lectures',sidebarOrder:1}];
const tab=(id,title,extra={})=>({id,title,url:url+'/'+id,spaceID:'atelier',pinned:false,favorite:false,...extra});
const tabs=[tab('guide','Essai des déplacements'),tab('favori-a','Favori A',{favorite:true,pinned:true}),tab('favori-b','Favori B',{favorite:true,pinned:true}),
tab('epingle','À déplacer · épinglé',{pinned:true,sidebarOrder:0}),tab('lecture-a','Lecture A',{pinned:true,folderID:'lectures',sidebarOrder:0}),
tab('projet-a','Projet A',{pinned:true,folderID:'projets',sidebarOrder:0}),tab('lecture-b','Lecture B',{pinned:true,folderID:'lectures',sidebarOrder:2}),
tab('idee-a','Idée A',{pinned:true,folderID:'idees'}),tab('voyage','Carnet de voyage',{spaceID:'voyages'})];
if(pageSplitTest) tabs.splice(1,0,tab('carnet','Carnet de voyage à deux'));
for(let i=1;i<=20;i++)tabs.push(tab('tab-'+i,'Onglet '+String(i).padStart(2,'0')+' · Café & idées'));
if(handoffTest) {
  spaces.push({id:'handoff',name:'Reprise iPhone',profileID:'essai',selectedTabID:'handoff-a',color:'#477e9c',icon:'sf:iphone'});
  tabs.push(tab('handoff-a','Example Domain',{url:'https://example.com/',spaceID:'handoff'}),tab('handoff-b','Apple France',{url:'https://www.apple.com/fr/',spaceID:'handoff'}));
}
await writeFile(path.join(profile,'session.json'),JSON.stringify({language:'fr',onboardingComplete:true,themeAppearance:'dark',tabPreviewsEnabled:pageSplitTest,activeSpaceID:handoffTest?'handoff':'atelier',
profiles:[{id:'essai',name:'Essai isolé'}],spaces,tabs,folders,splitGroups:[{id:'paire',tabIDs:['tab-1','tab-2'],vertical:false,weights:[]},{id:'trio',tabIDs:['tab-4','tab-5','tab-6'],vertical:false,weights:[]}],closedTabs:[],sidebarHidden:false,sidebarWidth:260}));
const log=await open(path.join(profile,'app.log'),'w');
try {
  const env={...process.env,BROWSER_NATIVE_TEST_DATA:profile,BROWSER_NATIVE_TEST_BACKGROUND:'0',BROWSER_NATIVE_HOST_DIAGNOSTICS:path.join(profile,'windows.snapshot.json')};
  delete env.BROWSER_NATIVE_TEST_AUTOCLOSE;delete env.BROWSER_NATIVE_TEST_UPDATE;
  const app=spawn(path.join(native,'build/Arc Reborn.app/Contents/MacOS/Arc Reborn'),[],{env,stdio:['ignore',log.fd,log.fd]});
  console.log(JSON.stringify({pid:app.pid,profile,url}));
  await new Promise((resolve,reject)=>{app.once('exit',resolve);app.once('error',reject);});
} finally {await log.close();server.closeAllConnections();server.close();await rm(profile,{recursive:true,force:true});}
