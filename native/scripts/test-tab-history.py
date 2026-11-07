#!/usr/bin/env python3
"""Reopen a tab in the native app, then repeat after restarting its isolated profile."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import threading

native = Path(__file__).resolve().parents[1]
build = Path(os.environ.get('BROWSER_BUILD_ROOT', native / 'build/development')).resolve()


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        page = self.path[1:] if self.path in ('/a', '/b', '/c', '/d') else 'other'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        if self.path == '/spa':
            self.wfile.write(b"<title>opening</title><script>onload=()=>{history.pushState({chapter:2},'',"
                             b"'/spa?chapter=2');document.title='chapter ready'}</script>")
        elif self.path == '/spa?chapter=2':
            self.wfile.write(b"<script>onload=()=>document.title=history.state?.chapter===2?'chapter restored':'missing state'</script>")
        else:
            self.wfile.write(f'<title>{page}</title>'.encode())

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(prefix='tab-history-check-', dir=build) as temp, ThreadingHTTPServer(('127.0.0.1', 0), Pages) as server:
    root = Path(temp)
    app = root / 'Arc Reborn.app'
    subprocess.run(['cp', '-cR', build / app.name, app], check=True)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleIdentifier'] = 'local.browser.tab-history-test'
    plist.write_bytes(plistlib.dumps(info))
    exe = app / 'Contents/MacOS/Arc Reborn'
    sources = sorted(path for path in (native/'Sources').glob('*.swift') if path.name != 'main.swift')
    subprocess.run(['xcrun', 'swiftc', '-j', '6', '-Onone', '-swift-version', '5', '-target', 'arm64-apple-macosx13.0',
                    '-import-objc-header', native/'Bridge/BrowserBridge.h', *sources, native/'Tests/TabHistoryHarness.swift',
                    build/'cmake/libBrowserBridge.a', build/'cmake/libcef_dll_wrapper/libcef_dll_wrapper.a', '-lc++',
                    '-framework', 'Cocoa', '-framework', 'IOSurface', '-framework', 'Security', '-framework', 'SecurityInterface',
                    '-F', native/'vendor/sparkle-2.10.1', '-framework', 'Sparkle', '-Xlinker', '-rpath',
                    '-Xlinker', '@executable_path/../Frameworks', '-Xlinker', '-ObjC', '-o', exe], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', app], check=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for restart in ('0', '1'):
        subprocess.run([exe], check=True, timeout=100, env={**os.environ, 'BROWSER_NATIVE_TEST_DATA':str(root/'profile'),
                       'BROWSER_HISTORY_ORIGIN':f'http://127.0.0.1:{server.server_port}', 'BROWSER_HISTORY_RESTART':restart})
