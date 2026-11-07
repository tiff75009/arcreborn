// Run with node native/Tests/page-translation.mjs after playwright install chromium.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const script = await readFile(new URL('../Resources/PageTranslation.js', import.meta.url), 'utf8');
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BINARY });
try {
  const page = await browser.newPage();
  await page.setContent('<html lang="en"><body><button id="action"> Next </button><p>Hello</p><p>Hello</p><p id="live">Old</p><input value="secret"><textarea>draft</textarea><div contenteditable>my edits</div><p translate="no">protected</p><p hidden>hidden</p><pre>code</pre><iframe srcdoc="<p>Embedded</p>"></iframe><div id="host"></div>');
  await page.evaluate(() => {
    window.count = 0;
    document.querySelector('#action').onclick = () => window.count++;
    document.querySelector('#host').attachShadow({mode:'open'}).innerHTML = '<span>Shadow</span>';
  });
  const run = (...args) => page.evaluate('(' + script + ')(...' + JSON.stringify(args) + ')');
  const { strings, lang } = await run('collect', 'a', null);
  assert.deepEqual([...strings].sort(), ['Next','Hello','Old','Embedded','Shadow'].sort());
  assert.equal(lang, 'en');
  const index = text => strings.indexOf(text);
  await page.locator('#live').evaluate(el => el.textContent = 'Changed by the site');
  assert.equal(await run('apply', 'a', [[index('Hello'), 'Bonjour']]), true);
  assert.equal(await page.getByText('Bonjour', {exact:true}).count(), 2);
  assert.equal(await page.locator('#action').textContent(), ' Next ');
  assert.equal(await run('apply', 'a', [[index('Shadow'),'Ombre'], [index('Old'),'Ancien'], [index('Next'),'Suivant'], [index('Embedded'),'Inclus']]), true);
  assert.equal(await page.locator('#action').textContent(), ' Suivant ');
  await page.locator('#action').click();
  assert.equal(await page.evaluate(() => window.count), 1);
  assert.equal(await page.locator('#live').textContent(), 'Changed by the site');
  assert.equal(await page.locator('input').inputValue(), 'secret');
  assert.equal(await page.locator('textarea').inputValue(), 'draft');
  assert.equal(await page.frameLocator('iframe').getByText('Inclus').count(), 1);
  assert.equal(await page.getByText('Ombre').count(), 1);
  await page.getByText('Bonjour').first().evaluate(el => el.firstChild.data = 'Latest update');
  assert.equal(await run('restore', 'a', null), true);
  assert.equal(await page.getByText('Latest update').count(), 1);
  assert.equal(await page.locator('#action').textContent(), ' Next ');

  const rows = Array.from({length:170}, (_,i) => '<p style="height:60px">Paragraph ' + i + '</p>').join('');
  await page.setContent('<main>' + rows + '</main>');
  await page.locator('p').nth(80).evaluate(el => el.scrollIntoView({block:'start'}));
  const offset = await page.evaluate(() => scrollY);
  const { strings: ordered } = await run('collect', 'b', null);
  assert.equal(ordered[0], 'Paragraph 80');
  await run('apply', 'b', [[0, 'Paragraphe 80']]);
  assert.equal(await page.locator('p').nth(80).textContent(), 'Paragraphe 80');
  assert.equal(await page.locator('p').first().textContent(), 'Paragraph 0');
  assert.equal(await page.evaluate(() => scrollY), offset);
  assert.equal(await run('restore', 'b', null), true);
  assert.equal(await run('apply', 'b', [[1, 'Réponse tardive']]), false);
  assert.equal(await page.locator('p').nth(80).textContent(), 'Paragraph 80');
  await run('collect', 'c', null);
  await page.goto('about:blank');
  assert.equal(await run('apply', 'c', [[0, 'Réponse tardive']]), false);
  console.log('PASS: progressive updates, viewport priority, cancellation, restore, live edits, forms, handlers, frames, shadow DOM and navigation.');
} finally {
  await browser.close();
}
