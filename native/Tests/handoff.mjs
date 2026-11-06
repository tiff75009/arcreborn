import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const profile = await mkdtemp(path.join(tmpdir(),'handoff-check-'));
const requests = new Map();
const server = createServer((req,res)=>{
  requests.set(req.url,(requests.get(req.url)??0)+1);
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});
  const title = req.url==='/cold' ? 'Reprise café' : req.url==='/incoming' ? 'Reprise reçue' : 'Page conservée';
  const script = req.url==='/cold' ? `<script>setTimeout(()=>{history.pushState({},'', '/details?fil=caf%C3%A9#lecture');document.title='Détails — café';},1400)</script>` : '';
  res.end(`<!doctype html><meta charset="utf-8"><title>${title}</title><h1>${title}</h1>${script}`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
try {
  const app = spawn(process.argv[2],[],{env:{...process.env,BROWSER_NATIVE_TEST_DATA:profile,BROWSER_NATIVE_TEST_BACKGROUND:'0',BROWSER_HANDOFF_TEST_URL:'http://127.0.0.1:'+server.address().port},stdio:['ignore','pipe','pipe']});
  let output=''; app.stdout.on('data',chunk=>{output+=chunk;process.stdout.write(chunk)}); app.stderr.on('data',chunk=>process.stderr.write(chunk));
  const timeout=setTimeout(()=>app.kill('SIGTERM'),90000);
  const result=await new Promise((resolve,reject)=>{app.once('error',reject);app.once('exit',(code,signal)=>resolve({code,signal}))});
  clearTimeout(timeout);
  assert.equal(result.code,0,JSON.stringify(result));
  assert.match(output,/Handoff native integration: \d+ checks passed/);
  assert.equal(requests.get('/cold'),1,'publishing Handoff must not reload the page');
  assert.equal(requests.get('/incoming'),1,'one incoming activity must open exactly one page');
  assert.equal(requests.get('/details?fil=caf%C3%A9'),undefined,'SPA metadata must not cause a new navigation');
  console.log('PASS HTTP requests: no page reload or duplicate navigation caused by Handoff');
} finally {
  server.closeAllConnections(); await new Promise(resolve=>server.close(resolve));
  await rm(profile,{recursive:true,force:true});
}
