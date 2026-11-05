// Run from any directory after a native development build: node native/Demo/folder-peek.mjs
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdtemp, writeFile, open, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../',import.meta.url));
const data = await mkdtemp(path.join(tmpdir(),'arc-folder-peek-'));
const pages = [
  ['accueil','Essai des dossiers'], ['palette','Palette de couleurs'], ['lettres','Typographie'],
  ['lumiere','Étude de lumière'], ['icones','Icônes et symboles'],
  ...['La couleur en photographie','Carnet de voyage','Les îles du Nord','Portraits en studio','Croquis du matin',
      'Architecture à Lyon','Écrire pour le Web','Index des revues','Le jardin d’hiver','Les archives'].map((t,i)=>['article-'+i,t])
];
const titles = new Map(pages);
const soundDemo = process.argv.includes('--sound');
if (soundDemo) {
  titles.set('musique','Musique d’essai');
  titles.set('synthese','Synthétiseur d’essai');
}
const disclosure = process.argv.includes('--disclosure');
const instructions = disclosure
  ? 'Ouvre <b>Atelier</b>, puis <b>Références</b>. Reclique pendant le mouvement pour inverser l’animation. Essaie aussi le <b>Dossier vide</b>.'
  : 'Amène la souris au bord gauche, puis survole <b>Atelier</b>. Compare avec <b>Développement</b>, déjà déplié. Clique sur un dossier pour alterner entre les deux états.';
const server = createServer((req,res)=>{
  const route = new URL(req.url,'http://localhost').pathname.slice(1) || 'accueil';
  if (soundDemo && route==='note.wav') {
    const rate=16000, wav=Buffer.alloc(44+rate*2);
    wav.write('RIFF'); wav.writeUInt32LE(wav.length-8,4); wav.write('WAVEfmt ',8); wav.writeUInt32LE(16,16);
    wav.writeUInt16LE(1,20); wav.writeUInt16LE(1,22); wav.writeUInt32LE(rate,24); wav.writeUInt32LE(rate*2,28);
    wav.writeUInt16LE(2,32); wav.writeUInt16LE(16,34); wav.write('data',36); wav.writeUInt32LE(rate*2,40);
    for (let i=0;i<rate;i++) wav.writeInt16LE(Math.round(950*Math.sin(i*2*Math.PI*220/rate)),44+2*i);
    res.writeHead(200,{'Content-Type':'audio/wav','Content-Length':wav.length}); res.end(wav); return;
  }
  const title = titles.get(route);
  if (!title) { res.writeHead(404); res.end(); return; }
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});
  res.end(`<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="color-scheme" content="dark"><title>${title}</title>
  <style>*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(ellipse at 78% 20%,#302b46 0,transparent 49%),#18171e;color:#f6f2f7;font:16px/1.55 system-ui;display:grid;align-items:center}main{width:min(580px,72vw);margin:60px auto;padding:25px}h1{font-size:clamp(32px,4vw,54px);letter-spacing:-.055em;line-height:1.08;margin:0 0 20px;text-wrap:balance}p{color:#c4becd;margin:0 0 24px}aside{border-top:1px solid #ffffff26;display:flex;align-items:center;justify-content:space-between;padding:16px 0;color:#dfd9e4}output{font-size:26px;font-variant-numeric:tabular-nums;color:#d9bbff}a{color:#dec4ff}</style>
  <main><h1>${title}</h1>${route==='accueil'?'<p>'+instructions+'</p>'+ (soundDemo?'<p>Pour essayer le bouton de son, ouvre <b>Musique d’essai</b> ou <b>Synthétiseur d’essai</b> dans la barre latérale.</p>':'')
    :route==='musique'?'<p>Lance la lecture, puis clique sur le haut-parleur à côté du titre. Tu peux aussi ouvrir <b>Atelier</b> pour essayer le mouvement des dossiers.</p><audio controls loop src="/note.wav"></audio>'
    :route==='synthese'?'<p>Ce son est produit directement par la page.</p><button id="play">Écouter</button> <button id="stop">Arrêter</button><script>let ctx;document.getElementById("play").onclick=async()=>{if(!ctx){ctx=new AudioContext();const o=ctx.createOscillator(),g=ctx.createGain();o.frequency.value=330;g.gain.value=.025;o.connect(g).connect(ctx.destination);o.start()}await ctx.resume()};document.getElementById("stop").onclick=()=>ctx?.suspend()</script>'
    :'<p>Tu as ouvert ce lien depuis le dossier. La barre latérale reste disponible au bord gauche.</p>'}
  <aside>Clics reçus par la page <output id="clicks"></output></aside>${route==='accueil'?'':'<a href="/accueil">Retour à l’essai</a>'}</main>
  <script>const clicks=document.getElementById('clicks');clicks.value=localStorage.clicks||'0';document.addEventListener('click',()=>{localStorage.clicks=Number(localStorage.clicks||0)+1;clicks.value=localStorage.clicks;},true)</script></html>`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
const folders=[['atelier','Atelier'],['references','Références','atelier'],['lecture','À lire'],['dev','Développement'],['vide','Dossier vide']].map(([id,name,parentID],sidebarOrder)=>({id,name,parentID,sidebarOrder,spaceID:'studio',collapsed:id!=='dev'}));
const tabs=pages.map(([id,title],i)=>({id,title,url:origin+'/'+id,spaceID:'studio',pinned:i>0,favorite:false,sidebarOrder:i,
  folderID:i===0?undefined:i<3?'atelier':i<5?'references':'lecture'}));
if (soundDemo) for (const id of ['musique','synthese']) tabs.push({id,title:titles.get(id),url:origin+'/'+id,spaceID:'studio',pinned:false,favorite:false,sidebarOrder:tabs.length});
tabs.push(...[['mdn','MDN Web Docs','https://developer.mozilla.org/fr/'],['swift','Le langage Swift','https://www.swift.org/'],['w3c','Standards du Web','https://www.w3.org/']].map(([id,title,url],sidebarOrder)=>({id,title,url,sidebarOrder,spaceID:'studio',folderID:'dev',pinned:true,favorite:false})));
const session={language:'fr',onboardingComplete:true,themeAppearance:'dark',sidebarWidth:252,sidebarHidden:!disclosure,activeSpaceID:'studio',closedTabs:[],folders,tabs,
  profiles:[{id:'test',name:'Essai des dossiers'}],spaces:[{id:'studio',name:'Studio',icon:'sf:sparkles',color:'#75638E',profileID:'test',selectedTabID:soundDemo?'musique':'accueil'}]};
await writeFile(path.join(data,'session.json'),JSON.stringify(session));
const log=await open(path.join(data,'app.log'),'w');
const env={...process.env,BROWSER_NATIVE_TEST_DATA:data,BROWSER_NATIVE_TEST_DOWNLOADS:path.join(data,'Downloads'),BROWSER_NATIVE_TEST_BACKGROUND:'0'};
delete env.BROWSER_NATIVE_TEST_AUTOCLOSE;
const bundle=process.env.BROWSER_SMOKE_APP || path.join(root,'build','Arc Reborn.app');
const app=spawn(path.join(bundle,'Contents/MacOS/Arc Reborn'),[],{env,stdio:['ignore',log.fd,log.fd]});
console.log(JSON.stringify({pid:app.pid,data,origin}));
try { await new Promise((resolve,reject)=>{ app.on('error',reject); app.on('exit',resolve); }); }
finally { await log.close(); server.closeAllConnections(); server.close(); await rm(data,{recursive:true,force:true}); }
