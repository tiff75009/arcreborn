#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Build the optimized arm64 CEF candidate from an already configured, pinned checkout.

Uses its own Ninja graph. Does not install an app, edit a profile or repoint a release.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import signal
import subprocess
import time
from engine import prepare_release_tools


NATIVE = Path(__file__).resolve().parents[1]
ENGINE = NATIVE / 'Engine'
PIN = json.loads((ENGINE / 'engine.lock.json').read_text())
FLAGS = ENGINE / 'performance-candidate.gn'


def run(*args, **kw):
    subprocess.run([str(arg) for arg in args], check=True, **kw)


def args_gn(text):
    options = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, value = line.split('=', 1)
        options[key.strip()] = value.strip()
    return options


def build(root, jobs):
    src = root / 'chromium_git/chromium/src'
    depot = root / 'depot_tools'
    out = src / 'out/Arc_Performance_arm64'
    baseline = src / 'out/Release_GN_arm64/args.gn'
    if not baseline.is_file():
        raise SystemExit('Configure the pinned CEF source with engine.py configure first.')
    options = args_gn(baseline.read_text())
    options.update(args_gn('\n'.join(shlex.split(PIN['gnDefines'], posix=False))))
    options.update(args_gn(FLAGS.read_text()))
    if options.get('target_cpu') != '"arm64"':
        raise SystemExit('Expected an arm64 CEF configuration.')
    for tree, rev in [(src, PIN['chromiumCommit']), (src / 'cef', PIN['cefCommit'])]:
        if subprocess.check_output(['git', '-C', tree, 'rev-parse', 'HEAD'], text=True).strip() != rev:
            raise SystemExit('Wrong source revision: ' + str(tree))
    patches = [ENGINE / p['file'] for p in PIN['patches']]
    for patch, spec in zip(patches, PIN['patches']):
        if hashlib.sha256(patch.read_bytes()).hexdigest() != spec['sha256']:
            raise SystemExit('Changed engine patch: ' + str(patch))
    run('/usr/bin/python3', NATIVE / 'scripts/check-engine-patches.py', src, *patches)
    py = depot / (depot / 'python3_bin_reldir.txt').read_text().strip() / 'python3'
    env = dict(os.environ, DEPOT_TOOLS_UPDATE='0', PYTHONDONTWRITEBYTECODE='1',
               PATH=os.pathsep.join(map(str, [py.parent, src/'buildtools/mac', depot])) + os.pathsep + os.environ['PATH'],
               NINJA_STATUS='[%f/%t %e] ', PYTHONUNBUFFERED='1')
    def tool(*args):
        run(*args, cwd=src, env=env)

    prepare_release_tools(src, depot, env)
    pgo = (src/'chrome/build/mac-arm.pgo.txt').read_text().strip()
    out.mkdir(exist_ok=True)
    args_path = out/'args.gn'
    serialized = ''.join(f'{k} = {v}\n' for k, v in sorted(options.items()))
    if not args_path.exists() or args_path.read_text() != serialized or not (out/'build.ninja').exists():
        args_path.write_text(serialized)
        tool(src/'buildtools/mac/gn', 'gen', out, '--fail-on-unused-args')
    base = out/'obj/v8/v8_base_without_compiler.ninja'
    if not re.search(r'-fprofile-use=\S*' + re.escape(pgo), base.read_text()):
        raise SystemExit('Expected the release PGO profile in the V8 compiler flags.')
    if (out/'.siso_deps').exists():
        raise SystemExit('Refusing to mix Ninja and Siso output.')
    paths = {out, NATIVE}
    if os.path.ismount(root):
        image = subprocess.check_output(['hdiutil', 'info', '-plist'])
        for item in plistlib.loads(image).get('images', []):
            if any(v.get('mount-point') == str(root) for v in item.get('system-entities', [])):
                paths.add(Path(item['image-path']).parent)
    def free_space():
        for path in paths:
            if not path.exists() or shutil.disk_usage(path).free < 12 * 1024 ** 3:
                raise RuntimeError(f'Build paused: keep 12 GiB free on {path}')
    free_space()
    ninja = src/'third_party/ninja/ninja'
    # Emit the V8 config explicitly (not normally a framework dependency).
    tool(ninja, '-C', out, 'v8_build_config.json')
    v8 = json.loads((out/'v8_build_config.json').read_text())
    required = dict(official_build=True, dcheck_always_on=False, DEBUG_defined=False,
                    debug_code=False, sandbox=True, has_maglev=True, has_turbofan=True)
    if any(v8.get(k) != v for k, v in required.items()):
        raise SystemExit('Unexpected V8 build flags: ' + str({k:v8.get(k) for k in required}))
    print('V8 configuration verified. Building the patched framework:', out, flush=True)
    worker = subprocess.Popen([ninja, '-C', out, '-j', str(jobs), PIN['buildTarget']],
                              env=env, cwd=src, start_new_session=True)
    try:
        while worker.poll() is None:
            free_space()
            try:
                worker.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
        if worker.returncode != 0:
            raise SystemExit(worker.returncode)
    finally:
        if worker.poll() is None:
            os.killpg(worker.pid, signal.SIGTERM)
            worker.wait()
    print(out/'Chromium Embedded Framework.framework')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--jobs', type=int, default=4, choices=range(1, 65), metavar='N')
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    if not (root/'chromium_git/chromium/src/out').is_dir():
        parser.error('Missing pinned Chromium checkout')
    def interrupt(*_):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupt)
    with (root/'chromium_git/chromium/src/out/.arc-performance.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        build(root, args.jobs)
