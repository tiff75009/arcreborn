#!/usr/bin/env python3
"""Read-only, loopback-only dashboard for the existing engine build."""
import argparse
from collections import deque
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
LOGS = ROOT / 'native/build/engine'
PAGE = ROOT / 'native/Engine/monitor.html'
STEP = re.compile(r'^\[(\d+)/(\d+) \| ([\d.]+) s\]\s+(.*)')


class Progress:
    def __init__(self):
        self.lock = threading.Lock()
        self.offset = 0
        self.identity = None
        self.pending = b''
        self.reset()

    def reset(self):
        self.started = None
        self.rows = deque(maxlen=20000)
        self.lines = deque(maxlen=12)
        self.error = None

    def read_lines(self, path):
        try:
            with path.open('rb') as stream:
                stat = os.fstat(stream.fileno())
                identity = (stat.st_dev, stat.st_ino)
                if identity != self.identity or stat.st_size < self.offset:
                    self.offset = 0
                    self.pending = b''
                    self.reset()
                self.identity = identity
                stream.seek(self.offset)
                data = self.pending + stream.read()
                self.offset = stream.tell()
            chunks = data.split(b'\n')
            self.pending = chunks.pop()
            for chunk in chunks:
                yield chunk.decode('utf-8', errors='replace').strip()
        except FileNotFoundError:
            return

    def snapshot(self):
        with self.lock:
            for line in self.read_lines(LOGS / 'build.log'):
                if line.startswith('--- Framework build '):
                    self.reset()
                    try:
                        self.started = datetime.strptime(line[20:39], '%Y-%m-%d %H:%M:%S').timestamp()
                    except ValueError:
                        pass
                match = STEP.match(line)
                if match:
                    done, total, elapsed, task = match.groups()
                    self.rows.append((int(done), int(total), float(elapsed), task))
                if line.startswith(('FAILED:', 'ninja: error:')):
                    self.error = line
                if line and not line.startswith('--- Framework build '):
                    self.lines.append(line)
            try:
                status = json.loads((LOGS / 'build-status.json').read_text())
            except (OSError, ValueError):
                status = {}
            now = time.time()
            # Avoid carrying a stopped state over from a previous launch.
            if self.started and status.get('timestamp', 0) < self.started:
                status = {}
            state = status.get('state', 'unknown')
            heartbeat_age = now - status.get('timestamp', 0)
            alive = False
            if state == 'building-framework':
                try:
                    os.kill(int(status['child_pid']), 0)
                    alive = True
                except (ProcessLookupError, PermissionError, KeyError, ValueError):
                    pass
                if not alive or heartbeat_age > 30:
                    state = 'unavailable'
            elapsed = max(0, (now if state == 'building-framework' else status.get('timestamp', now)) - self.started) if self.started else 0
            done, total, last_elapsed, task = self.rows[-1] if self.rows else (0, 0, 0, '')
            rate = None
            if len(self.rows) > 1:
                first = next((row for row in self.rows if row[2] >= last_elapsed - 300), self.rows[0])
                duration = last_elapsed - first[2]
                if duration >= 30 and elapsed - last_elapsed < 90:
                    rate = (done - first[0]) * 60 / duration
            eta = (total - done) / rate * 60 if rate and state == 'building-framework' else None
            return dict(state=state, done=done, total=total, elapsed=elapsed, rate=rate,
                        eta=eta, task=task, error=self.error or status.get('error'),
                        free_bytes=status.get('free_bytes'), jobs=status.get('jobs'),
                        started=self.started, updated=now, heartbeat_age=heartbeat_age,
                        lines=list(self.lines), complete=state == 'built-not-installed')


class CandidateProgress(Progress):
    step = re.compile(r'^\[(\d+)/(\d+) ([\d.]+)\]\s+(.*)')
    marker = re.compile(r'^@arc-build (\d+) (\d+) (\d+) (engine|app|media|extensions|speedometer|complete|stopped)$')
    prefix = 'V8 configuration verified. Building the patched framework: '

    def __init__(self, path):
        self.path = path
        super().__init__()

    def reset(self):
        super().reset()
        self.phase = 'waiting'
        self.stopped = self.pid = self.jobs = self.out = None
        self.graph = False
        self.graph_total = self.last_write = 0

    def consume(self, line):
        marker = self.marker.fullmatch(line)
        if marker:
            timestamp, pid, jobs, phase = marker.groups()
            if phase == 'engine':
                self.started, self.pid, self.jobs = int(timestamp), int(pid), int(jobs)
                self.error = self.stopped = None
                self.graph = False
                self.lines.clear()
            if phase == 'stopped':
                self.stopped = int(timestamp)
            else:
                self.phase = phase
                if phase == 'complete':
                    self.stopped = int(timestamp)
            return
        if line.startswith(self.prefix):
            out = Path(line[len(self.prefix):])
            if self.out != out:
                self.graph_total = 0
            self.out = out
            self.graph = True
            self.phase = 'engine'
            self.rows.clear()
            self.error = None
        match = self.step.match(line) if self.graph and self.phase == 'engine' else None
        if match:
            done, total, elapsed, task = match.groups()
            self.rows.append((int(done), int(total), float(elapsed), task))
            self.graph_total = max(self.graph_total, int(total))
        if line.startswith(('FAILED:', 'error:', 'ninja: error:', 'RuntimeError:', 'AssertionError')):
            self.error = line[:600]
        if line.startswith(('Stopped at line ', 'ninja: build stopped:')):
            self.stopped = self.last_write
            self.graph = False
        if line:
            self.lines.append(line[:1200])

    def snapshot(self):
        with self.lock:
            for line in self.read_lines(self.path):
                self.consume(line)
            try:
                self.last_write = self.path.stat().st_mtime
            except FileNotFoundError:
                pass
            now = time.time()
            state = self.phase
            if state == 'complete':
                state = 'built-not-installed'
            elif self.stopped is not None:
                state = 'stopped'
            elif self.pid:
                try:
                    os.kill(self.pid, 0)
                except ProcessLookupError:
                    state = 'unavailable'
                if state == 'engine':
                    state = 'building-framework'
            elif self.phase != 'waiting':
                state = 'unavailable'
            done, total, elapsed, task = self.rows[-1] if self.rows else (0, 0, 0, '')
            cached = max(0, self.graph_total - total) if total else 0
            done += cached
            if self.phase in ('app', 'media', 'extensions', 'speedometer', 'complete'):
                done = self.graph_total
            rate = eta = None
            if state == 'building-framework' and self.graph and self.rows and now-self.last_write < 90:
                first = next(row for row in self.rows if row[2] >= elapsed - 300)
                span = elapsed - first[2]
                if span >= 30:
                    rate = (done - cached - first[0]) * 60 / span
                    # The early graph is mostly fast code generation. Wait for
                    # a longer sample before offering even a rough projection.
                    if elapsed >= 300 and rate > 0:
                        eta = (self.graph_total - done) * 60 / rate
            try:
                free = shutil.disk_usage(self.out).free if self.out else None
            except OSError:
                free = None
            end = self.stopped or (self.last_write if state == 'unavailable' else now)
            return dict(monitor='arc-candidate', state=state, phase=self.phase, done=done,
                        total=self.graph_total, cached=cached, task=task, jobs=self.jobs,
                        elapsed=max(0, end-self.started) if self.started else None,
                        started=self.started, rate=rate, eta=eta, updated=now, free_bytes=free,
                        lines=list(self.lines), error=self.error, complete=self.phase == 'complete')


PROGRESS = Progress()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get('Host') not in {f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}'}:
            self.send_error(403)
            return
        if self.path == '/api/status':
            body = json.dumps(PROGRESS.snapshot(), ensure_ascii=False).encode()
            mime = 'application/json; charset=utf-8'
        elif self.path in ('/', '/index.html'):
            body = PAGE.read_bytes()
            mime = 'text/html; charset=utf-8'
        elif self.path == '/favicon.ico':
            self.send_response(204)
            self.end_headers()
            return
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int)
    parser.add_argument('--candidate', action='store_true', help='Follow the optimized engine and subsequent checks')
    parser.add_argument('--open', action='store_true', help='Open the dashboard on macOS')
    args = parser.parse_args()
    port = args.port or (8770 if args.candidate else 8769)
    if args.candidate:
        work = Path(os.environ.get('ARC_PERF_WORK', ROOT/'native/build/perf-check'))
        PROGRESS = CandidateProgress(work/'candidate.log')
    url = f'http://127.0.0.1:{port}'
    try:
        server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    except OSError:
        # Reopening this monitor must not create a second server or build.
        if args.open and args.candidate:
            from urllib.request import urlopen
            try:
                with urlopen(url + '/api/status', timeout=1) as r:
                    same = json.load(r).get('monitor') == 'arc-candidate'
            except (OSError, ValueError):
                same = False
            if same:
                subprocess.run(['open', url], check=True)
                raise SystemExit(0)
        raise
    print('Arc Reborn — suivi du moteur : ' + url, flush=True)
    if args.open:
        subprocess.run(['open', url], check=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
