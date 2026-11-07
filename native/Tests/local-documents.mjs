// Launch Services integration on macOS. Operates only on an isolated clone and profile.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

const built = path.resolve(process.argv[2] ?? 'native/build/Arc Reborn.app');
const root = await mkdtemp(path.join(os.tmpdir(),'arc-finder-check-'));
const bundleFolder = await mkdtemp(path.join(path.dirname(built),'finder-check-'));
const app = path.join(bundleFolder,'Arc Finder Check.app'), profile = path.join(root,'Profile');
const bundleID = 'local.browser.native.findercheck.p' + process.pid;
const wsRegister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';
const cmd = (exe,args) => execFileSync(exe,args,{encoding:'utf8'});
async function until(label, probe, seconds=22) {
  let error;
  for (const finish=Date.now()+seconds*1000; Date.now()<finish;) {
    try { const result = await probe(); if(result) return result; } catch(e) { error=e; }
    await delay(150);
  }
  throw Error(label + ': ' + (error?.message ?? 'timed out'));
}
async function rpc(target, method, params={}) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  try {
    return await new Promise((ok,no)=>{
      const timer = setTimeout(()=>no(Error(method+' timed out')),5000);
      ws.onopen=()=>ws.send(JSON.stringify({id:1,method,params}));
      ws.onerror=e=>{clearTimeout(timer);no(Error(e.message))};
      ws.onmessage=event=>{const m=JSON.parse(event.data); if(m.id!==1)return; clearTimeout(timer);m.error?no(Error(m.error.message)):ok(m.result)};
    });
  } finally {ws.close()}
}
const listen = s => new Promise(resolve=>s.listen(0,'127.0.0.1',resolve));
const server=createServer((req,res)=>res.end('<title>Destination du raccourci</title>'));
await listen(server); const web='http://127.0.0.1:'+server.address().port+'/destination#lecture';
const portProbe=createServer();await listen(portProbe);const port=portProbe.address().port;await new Promise(resolve=>portProbe.close(resolve));
const targets=async()=>(await fetch('http://127.0.0.1:'+port+'/json/list',{signal:AbortSignal.timeout(1200)})).json();
const target=async name=>until(name,async()=>(await targets()).find(t=>t.type==='page' && (name===web?t.url===web:t.url.startsWith('file:') && path.basename(fileURLToPath(t.url)).normalize()===name.normalize())));
const session=async()=>JSON.parse(await readFile(path.join(profile,'session.json'),'utf8'));
const file=name=>path.join(root,name);
const html='Café #1.html', svg='Schéma à lire.svg', pdf='Épreuve.pdf', link='Mon raccourci.webloc';
const open=(...files)=>cmd('/usr/bin/open',['-a',app,...files.map(file)]);
try {
  cmd('/bin/cp',['-cR',built,app]);
  cmd('/usr/libexec/PlistBuddy',['-c','Set :CFBundleIdentifier '+bundleID,path.join(app,'Contents/Info.plist')]);
  cmd('/usr/bin/codesign',['--force','--sign','-',app]);cmd(wsRegister,['-f',app]);
  await mkdir(profile);
  const state={language:'fr',onboardingComplete:true,sidebarWidth:250,sidebarHidden:false,profiles:[{id:'person',name:'Personnel'}],spaces:[{id:'space',name:'Personnel',color:'#564FC9',icon:'◈',profileID:'person',selectedTabID:'original'}],tabs:[{id:'original',spaceID:'space',url:'about:blank',title:'Onglet conservé',pinned:false,favorite:false}],folders:[],closedTabs:[],activeSpaceID:'space'};
  await writeFile(path.join(profile,'session.json'),JSON.stringify(state));
  await writeFile(file(svg),'<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><title>Schéma été</title><rect width="120" height="80" fill="teal"/></svg>');
  await writeFile(file(html),'<meta charset="utf-8"><title>Page du café</title><img src="'+svg+'">');
  await writeFile(file(link),'<?xml version="1.0"?><plist version="1.0"><dict><key>URL</key><string>'+web+'</string></dict></plist>');
  // A full-page green rectangle lets us verify Chromium actually painted the PDF.
  const stream='0 1 0 rg 0 0 300 360 re f\n';
  const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 360] /Resources << >> /Contents 4 0 R >>','<< /Length '+stream.length+' >>\nstream\n'+stream+'endstream'];
  let source='%PDF-1.4\n';const offsets=[0];for(const [i,obj] of objects.entries()){offsets.push(source.length);source+=(i+1)+' 0 obj\n'+obj+'\nendobj\n'}
  const start=source.length;source+='xref\n0 5\n0000000000 65535 f \n'+offsets.slice(1).map(o=>String(o).padStart(10,'0')+' 00000 n \n').join('')+'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n'+start+'\n%%EOF\n';
  await writeFile(file(pdf),source);
  cmd('/usr/bin/open',['-n','-a',app,'--env','BROWSER_NATIVE_TEST_DATA='+profile,'--env','BROWSER_NATIVE_DEBUG_PORT='+port,'--env','BROWSER_NATIVE_TEST_AUTOCLOSE=180','--stderr',file('app.log'),file(html)]);
  const page=await target(html);
  const candidates = cmd('/usr/bin/swift',['-e','import AppKit; for file in CommandLine.arguments.dropFirst(2) { let apps=NSWorkspace.shared.urlsForApplications(toOpen:URL(fileURLWithPath:file)); print(URL(fileURLWithPath:file).pathExtension,apps.contains { Bundle(url:$0)?.bundleIdentifier == CommandLine.arguments[1] }) }',bundleID,...[html,svg,pdf,link].map(file)]);
  assert.equal(candidates.trim().split('\n').filter(s=>s.endsWith(' true')).length,4,candidates);
  console.log('PASS macOS lists the test browser as a viewer for all four document types');
  const evaluate=async(t,expression)=>(await rpc(t,'Runtime.evaluate',{expression,returnByValue:true})).result.value;
  await until('HTML and relative SVG',()=>evaluate(page,"document.title==='Page du café' && document.images[0]?.naturalWidth === 120"));
  console.log('PASS cold Finder open: HTML and its relative SVG rendered');
  open(svg);const drawing=await target(svg);
  await until('standalone SVG',()=>evaluate(drawing,"document.contentType==='image/svg+xml' && document.querySelector('rect')?.getBBox().width===120"));
  console.log('PASS warm open: standalone SVG rendered');
  open(pdf);const print=await target(pdf);
  await until('PDF painted',async()=>{
    const shot=await rpc(print,'Page.captureScreenshot',{format:'png'});
    await writeFile(file('page.png'),Buffer.from(shot.data,'base64'));
    return cmd('/usr/bin/swift',['-e','import AppKit; let p = NSBitmapImageRep(data:try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))!; var n=0; for x in stride(from:0,to:p.pixelsWide,by:16){ for y in stride(from:0,to:p.pixelsHigh,by:16){if let c=p.colorAt(x:x,y:y)?.usingColorSpace(.sRGB), c.greenComponent>0.85 && c.greenComponent-c.redComponent>0.35 && c.greenComponent-c.blueComponent>0.35 {n+=1}}};print(n)',file('page.png')]).trim()>30;
  });
  console.log('PASS warm open: page pixels verified in the Chromium PDF viewer');
  open(html,link);await target(web);
  await until('ordered selection',async()=>{const saved=await session();return saved.tabs.length===6 && saved.tabs[0].id==='original' && saved.tabs.at(-2).url.startsWith('file:') && saved.tabs.at(-1).url===web && saved.spaces[0].selectedTabID===saved.tabs.at(-1).id});
  console.log('PASS batch open: two new tabs, .webloc destination selected, original tab preserved');
  if (process.argv.includes('--try-open-panel')) {
    const name='Choisi avec le menu.htm';
    await writeFile(file(name),'<meta charset="utf-8"><title>Ouvert avec ⌘O</title>');
    console.log('Essai interactif ⌘O :',app,'→',file(name));
    await until('⌘O',async()=>(await targets()).some(t=>t.url.startsWith('file:') && path.basename(fileURLToPath(t.url))===name && t.title==='Ouvert avec ⌘O'),90);
    console.log('PASS ⌘O: document selected in native panel and loaded in Chromium');
  }
} finally {
  cmd('/usr/bin/swift',['-e','import AppKit; let apps=NSRunningApplication.runningApplications(withBundleIdentifier:CommandLine.arguments[1]);apps.forEach{ _ = $0.terminate() }; let end=Date().addingTimeInterval(12); while apps.contains(where:{!$0.isTerminated}) && Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) };precondition(apps.allSatisfy(\u005c.isTerminated))',bundleID]);
  try { cmd(wsRegister,['-u',app]); } catch {}
  await new Promise(resolve=>server.close(resolve));
  await rm(root,{recursive:true,force:true});
  await rm(bundleFolder,{recursive:true,force:true});
}
