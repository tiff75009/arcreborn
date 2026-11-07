// Run with node native/Tests/page-translation.mjs after playwright install chromium.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';
const script=await readFile(new URL('../Resources/PageTranslation.js',import.meta.url),'utf8');
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_BINARY});
try {
  const page=await browser.newPage();
  await page.setContent('<html lang="en"><body><button id="action"> Next </button><p>Hello</p><p>Hello</p><p id="live">Old</p><input value="secret"><textarea>draft</textarea><div contenteditable>my edits</div><p translate="no">protected</p><p hidden>hidden</p><pre>code</pre><iframe srcdoc="<p>Embedded</p>"></iframe><div id="host"></div>');
  await page.evaluate(()=>{window.count=0;action.onclick=()=>window.count++; document.querySelector('#host').attachShadow({mode:'open'}).innerHTML='<span>Shadow</span>'});
  const run=(...args)=>page.evaluate('('+script+')(...'+JSON.stringify(args)+')');
  const {strings,lang}=await run('collect','a',null);
  assert.deepEqual([...strings].sort(),['Next','Hello','Old','Embedded','Shadow'].sort());assert.equal(lang,'en');
  await page.locator('#live').evaluate(el=>el.textContent='Changed by the site');
  assert.equal(await run('apply','a',strings.map(s=>'TR '+s)),true);
  assert.equal(await page.locator('#action').textContent(),' TR Next ');
  await page.locator('#action').click(); assert.equal(await page.evaluate(()=>window.count),1);
  assert.equal(await page.locator('#live').textContent(),'Changed by the site');
  assert.equal(await page.locator('input').inputValue(),'secret');
  assert.equal(await run('restore','a',null),true);
  assert.equal(await page.locator('#action').textContent(),' Next ');
  await run('collect','b',null); await page.goto('about:blank');
  assert.equal(await run('apply','b',strings),false);
  console.log('PASS: translation, restore, deduplication, live edits, whitespace, frames, shadow DOM, navigation and form privacy');
} finally { await browser.close() }
