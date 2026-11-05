// SPDX-License-Identifier: MPL-2.0
// Usage: node native/Tests/speedometer.mjs "/path/to/Arc Reborn.app" [iterations] > results.json
// Run on an idle Mac, with the page visible. A whole run takes several minutes.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, open, rm, writeFile, access } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const iterations = Number(process.argv[3] ?? 10);
assert.ok(Number.isInteger(iterations) && iterations > 0 && iterations <= 100, 'Invalid iteration count');
const exe = path.join(path.resolve(process.argv[2]), 'Contents/MacOS/Arc Reborn');
await access(exe);
const site = new URL('https://browserbench.org/Speedometer3.1/');
site.searchParams.set('iterationCount', String(iterations));

const socket = createServer();
await new Promise((resolve, reject) => socket.once('error', reject).listen(0, '127.0.0.1', resolve));
const { port } = socket.address();
await new Promise(resolve => socket.close(resolve));
const profile = await mkdtemp(path.join(tmpdir(), 'browser-native-test-speedometer-'));
let app, ws, log, exited;

try {
    await writeFile(path.join(profile, 'session.json'), JSON.stringify({
        onboardingComplete:true, language:"fr", sidebarHidden:true, sidebarWidth:228, activeSpaceID:'space',
        profiles:[{ id:'p', name:'Benchmark' }],
        spaces:[{ id:'space', profileID:'p', name:'Benchmark', icon:'◈', color:'#8871C5', selectedTabID:'bench' }],
        tabs:[{ id:'bench', spaceID:'space', url:site.href, title:'Speedometer', pinned:false, favorite:false }],
        folders:[], closedTabs:[]
    }));
    log = await open(path.join(profile, 'app.log'), 'w');
    app = spawn(exe, ['--disable-component-update'], {
        env:{ ...process.env, BROWSER_NATIVE_TEST_DATA:profile, BROWSER_NATIVE_DEBUG_PORT:String(port) },
        stdio:['ignore', log.fd, log.fd]
    });
    exited = new Promise(resolve => { app.once('error', resolve); app.once('exit', resolve); });
    let target;
    for (let i = 0; i < 200 && !target; ++i) {
        if (app.exitCode !== null || app.signalCode) throw Error('Arc Reborn exited before opening the benchmark');
        try {
            const list = await (await fetch(`http://127.0.0.1:${port}/json/list`, { signal:AbortSignal.timeout(1000) })).json();
            target = list.find(t => t.type === 'page' && t.url.split('#')[0] === site.href);
        } catch { /* Debug endpoint starts after CEF. */ }
        if (!target) await delay(200);
    }
    assert.ok(target, 'Speedometer did not open in the disposable profile');
    ws = new WebSocket(target.webSocketDebuggerUrl);
    await Promise.race([
        new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; }),
        delay(10000, null, {ref:false}).then(() => { throw Error('CDP connection timeout'); })
    ]);
    let seq = 0;
    const pending = new Map();
    ws.onmessage = ({data}) => {
        const msg = JSON.parse(data);
        const found = pending.get(msg.id);
        if (!found) return;
        clearTimeout(found.timer);
        pending.delete(msg.id);
        if (msg.error) found.reject(Error(msg.error.message));
        else found.resolve(msg.result);
    };
    ws.onclose = () => {
        for (const p of pending.values()) { clearTimeout(p.timer); p.reject(Error('Benchmark tab closed')); }
        pending.clear();
    };
    const call = (method, params = {}) => new Promise((resolve, reject) => {
        const id = ++seq;
        const timer = setTimeout(() => { pending.delete(id); reject(Error('CDP timeout: ' + method)); }, 30000);
        pending.set(id, {resolve, reject, timer});
        ws.send(JSON.stringify({id, method, params}));
    });
    const evaluate = async expression => {
        const reply = await call('Runtime.evaluate', {expression, awaitPromise:true, returnByValue:true, userGesture:true});
        if (reply.exceptionDetails) throw Error(reply.exceptionDetails.exception?.description ?? reply.exceptionDetails.text);
        return reply.result.value;
    };
    await call('Page.bringToFront');
    let ready = false;
    for (let i = 0; i < 150 && !ready; ++i) {
        ready = await evaluate('document.readyState === "complete" && typeof document.querySelector(".start-tests-button")?.onclick === "function"');
        if (!ready) await delay(200);
    }
    assert.ok(ready, 'Benchmark failed to initialize');
    const viewport = await evaluate('({ width:innerWidth, height:innerHeight, visible:!document.hidden })');
    assert.ok(viewport.visible && viewport.width >= 850 && viewport.height >= 650, 'Speedometer requires a visible 850 × 650 viewport');
    console.error('Speedometer 3.1:', iterations, 'iterations;', viewport.width, '×', viewport.height);
    await evaluate(`document.addEventListener("visibilitychange", () => { if (document.hidden) window.__arcBenchHidden = true; });
                   document.querySelector(".start-tests-button").click();`);
    const deadline = Date.now() + 20 * 60 * 1000;
    let done = false;
    while (Date.now() < deadline && !done) {
        await delay(2000);
        const state = await evaluate('({hidden:!!window.__arcBenchHidden, section:document.documentElement.dataset.visibleSection})');
        assert.ok(!state.hidden, 'Benchmark was backgrounded; discard this run');
        done = state.section === 'summary';
    }
    assert.ok(done, 'Benchmark timed out');
    const metrics = await evaluate('(async () => (await fetch(document.querySelector("#download-full-json").href)).json())()');
    assert.ok(metrics.Score?.mean > 0 && metrics.Score.values.length === iterations, 'Incomplete benchmark');
    const suites = Object.keys(metrics).filter(name => !name.includes('/') && metrics[name].unit === 'ms' && Object.keys(metrics).some(key => key.startsWith(name + '/')));
    assert.equal(suites.length, 20, 'Expected all 20 standard Speedometer 3.1 workloads');
    console.error('Speedometer 3.1:', metrics.Score.mean.toFixed(2), '±', metrics.Score.delta?.toFixed(2));
    console.log(JSON.stringify(metrics));
} finally {
    ws?.close();
    if (app?.pid && app.exitCode === null && !app.signalCode) {
        app.kill('SIGTERM');
        await Promise.race([exited, delay(4000, null, {ref:false})]);
        if (app.exitCode === null && !app.signalCode) { app.kill('SIGKILL'); await exited; }
    }
    await log?.close();
    await rm(profile, {recursive:true, force:true});
}
