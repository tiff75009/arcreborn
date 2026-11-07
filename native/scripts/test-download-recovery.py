#!/usr/bin/env python3
"""Exercise both recovery buttons across native process restarts and verify the HTTP bytes."""
# SPDX-License-Identifier: MPL-2.0
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import threading
import time

native = Path(__file__).resolve().parents[1]
build = Path(os.environ.get('BROWSER_BUILD_ROOT', native / 'build/development')).resolve()
payload = bytes(range(251)) * 32768
initial_bytes = 2 * 1024 * 1024
requests = []
second_launch = False


class Downloads(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        if self.path == '/page':
            self.send_response(200)
            self.send_header('Connection', 'close')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Set-Cookie', 'session=recovery; Path=/; Max-Age=600; HttpOnly')
            self.end_headers()
            self.wfile.write(b'<title>Restored fixture</title>' if second_launch else b'<title>Download fixture</title>')
            return
        if self.path not in ('/range', '/full', '/legacy', '/crash', '/changed') or 'session=recovery' not in self.headers.get('Cookie', ''):
            self.send_error(403)
            return
        offset = self.headers.get('Range', '')
        first = not any(path == self.path for path, _ in requests)
        requests.append((self.path, offset))
        start = int(re.fullmatch(r'bytes=(\d+)-', offset)[1]) if offset else 0
        changed = self.path == '/changed' and not first
        if changed or self.path == '/full':
            start = 0
        self.send_response(206 if start else 200)
        self.send_header('Accept-Ranges', 'bytes' if self.path != '/full' else 'none')
        self.send_header('ETag', '"recovery-v2"' if changed else '"recovery-v1"')
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Disposition', 'attachment; filename="fixture.txt"')
        self.send_header('Content-Length', str(len(payload) - start))
        if start:
            self.send_header('Content-Range', f'bytes {start}-{len(payload)-1}/{len(payload)}')
        self.end_headers()
        if first:
            self.wfile.write(b'x' * initial_bytes if self.path == '/changed' else payload[:initial_bytes])
            time.sleep(55)  # The first browser exits with a real partial on disk.
        else:
            self.wfile.write(payload[start:])

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(prefix='download-recovery-check-', dir=build) as temp, ThreadingHTTPServer(('127.0.0.1', 0), Downloads) as server:
    root = Path(temp)
    app = root / 'Arc Reborn.app'
    subprocess.run(['cp', '-cR', build / app.name, app], check=True)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleIdentifier'] = 'local.browser.download-recovery-test'
    plist.write_bytes(plistlib.dumps(info))
    exe = app / 'Contents/MacOS/Arc Reborn'
    sources = sorted(path for path in (native/'Sources').glob('*.swift') if path.name != 'main.swift')
    subprocess.run(['xcrun', 'swiftc', '-j', '6', '-Onone', '-swift-version', '5', '-target', 'arm64-apple-macosx13.0',
                    '-import-objc-header', native/'Bridge/BrowserBridge.h', *sources, native/'Tests/DownloadRecoveryHarness.swift',
                    build/'cmake/libBrowserBridge.a', build/'cmake/libcef_dll_wrapper/libcef_dll_wrapper.a', '-lc++',
                    '-framework', 'Cocoa', '-framework', 'IOSurface', '-framework', 'Security', '-framework', 'SecurityInterface',
                    '-F', native/'vendor/sparkle-2.10.1', '-framework', 'Sparkle', '-Xlinker', '-rpath',
                    '-Xlinker', '@executable_path/../Frameworks', '-Xlinker', '-ObjC', '-o', exe], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', app], check=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for mode in ('range', 'full', 'legacy', 'crash', 'changed'):
        profile = root / mode
        folder = profile / 'Downloads'
        folder.mkdir(parents=True)
        env = {**os.environ, 'BROWSER_NATIVE_TEST_DATA':str(profile), 'BROWSER_NATIVE_TEST_DOWNLOADS':str(folder),
               'BROWSER_NATIVE_TEST_BACKGROUND':'0', 'RECOVERY_ORIGIN':f'http://127.0.0.1:{server.server_port}', 'RECOVERY_MODE':mode}
        def rows():
            return json.loads((profile/'library.json').read_text())['downloads']
        second_launch = False
        subprocess.run([exe], check=True, timeout=65, env={**env, 'RECOVERY_PHASE':'first'})
        original, = rows()
        if mode == 'legacy':
            metadata = profile/'library.json'
            library = json.loads(metadata.read_text())
            for field in ('guid', 'originalURL', 'canContinue', 'runtimeID'):
                library['downloads'][0].pop(field, None)
            metadata.write_text(json.dumps(library))
        second_launch = True
        subprocess.run([exe], check=True, timeout=65, env={**env, 'RECOVERY_PHASE':'second'})
        final, = rows()
        assert final['id'] == original['id'] and final['profileID'] == original['profileID']
        assert Path(final['path']).read_bytes() == payload
        offsets = [offset for path, offset in requests if path == '/'+mode]
        if mode == 'full':
            assert offsets == ['', ''], offsets
        elif mode == 'changed':
            assert offsets[:2] == ['', f'bytes={initial_bytes}-'] and all(not offset for offset in offsets[2:]), offsets
        else:
            assert offsets == ['', f'bytes={initial_bytes}-'], offsets
        print('PASS', mode, offsets, 'and byte-for-byte complete file', flush=True)
