#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import argparse, http.server, threading, tempfile, json, os, socket, subprocess, time, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description="Verify isolated Chromium startup and mock-keychain cookie encryption.")
parser.add_argument('--app',type=Path,default=ROOT/'native/build/development/Arc Reborn.app')
args=parser.parse_args()
with socket.socket() as probe:
    probe.bind(('127.0.0.1',0)); debug_port=probe.getsockname()[1]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Set-Cookie','isolation=mock-storage-check; Max-Age=3600; Path=/'); self.end_headers()
        self.wfile.write(b'<!doctype html><title>Arc Reborn rename check</title><h1>Chromium is ready</h1>')
    def log_message(self,*args): pass
server=http.server.HTTPServer(('127.0.0.1',0),Handler); threading.Thread(target=server.serve_forever,daemon=True).start()
data=Path(tempfile.mkdtemp(prefix='arc-reborn-keychain-test-')); origin='http://127.0.0.1:'+str(server.server_port)
state={'language':'fr','onboardingComplete':True,'sidebarWidth':250,'sidebarHidden':False,'profiles':[{'id':'test-profile','name':'Test'}],'spaces':[{'id':'test-space','name':'Test','color':'#B5AED9','icon':'◈','profileID':'test-profile','selectedTabID':'test-tab'}],'tabs':[{'id':'test-tab','spaceID':'test-space','url':origin,'title':'Test','pinned':False,'favorite':False}],'folders':[],'closedTabs':[],'activeSpaceID':'test-space'}
(data/'session.json').write_text(json.dumps(state))
log=(data/'launch.log').open('w')
proc=subprocess.Popen([str((args.app/'Contents/MacOS/Arc Reborn').resolve())],env={**os.environ,'BROWSER_NATIVE_TEST_DATA':str(data),'BROWSER_NATIVE_TEST_BACKGROUND':'1','BROWSER_NATIVE_DEBUG_PORT':str(debug_port),'BROWSER_NATIVE_TEST_AUTOCLOSE':'12'},stdout=log,stderr=log)
try:
    found=False
    last=None
    client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for _ in range(350):
        if proc.poll() is not None: break
        try:
            targets=json.load(client.open('http://127.0.0.1:'+str(debug_port)+'/json/list',timeout=1))
            last=[(t.get('title'), t.get('url')) for t in targets]
            found=any(t.get('title')=='Arc Reborn rename check' for t in targets)
            if found: break
        except Exception: pass
        time.sleep(.1)
    assert found, 'Local Chromium page failed to load: '+str(last)
    print('PASS: Chromium renders a local page under the renamed executable.',flush=True)
    processes=subprocess.check_output(['ps','-axo','command'],text=True)
    helpers=[line for line in processes.splitlines() if '/Arc Reborn Helper' in line]
    assert any('--type=renderer' in line for line in helpers), 'Renamed renderer missing'
    print('PASS: Renamed renderer is running.',flush=True)
    assert proc.wait(timeout=55)==0, 'Unclean exit'
    restored=json.loads((data/'session.json').read_text())
    assert restored['tabs'][0]['title']=='Arc Reborn rename check'
    print('PASS: Clean CEF shutdown and isolated session saved.',flush=True)
    import sqlite3, hashlib
    database=data/'Chromium/MockKeychain/Profile-test-profile/Network/Cookies'
    if not database.exists(): database=data/'Chromium/MockKeychain/Profile-test-profile/Cookies'
    with sqlite3.connect(database) as db:
        encrypted=db.execute("select encrypted_value from cookies where name='isolation'").fetchone()[0]
    assert encrypted.startswith(b'v10')
    key=hashlib.pbkdf2_hmac('sha1',b'mock_password',b'saltysalt',1003,16)
    plain=subprocess.check_output(['/usr/bin/openssl','enc','-d','-aes-128-cbc','-K',key.hex(),'-iv',(b' '*16).hex()],input=encrypted[3:])
    assert plain.endswith(b'mock-storage-check')
    print('PASS: Cookie uses Chromium mock encryption; no macOS Keychain key.',flush=True)
    events=''.join(f.read_text() for f in (data/'Chromium/Diagnostics').glob('*/events.jsonl'))
    assert 'test.mock-keychain.enabled' in events

finally:
    if proc.poll() is None: proc.terminate(); proc.wait(timeout=10)
    log.close(); server.shutdown()
