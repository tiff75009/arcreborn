#!/usr/bin/env python3
"""Portable CEF source build and verified binary distribution for contributors.

Source builds are opt-in; never start a Chromium build during a normal dev build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

NATIVE = Path(__file__).resolve().parents[1]
ENGINE = NATIVE / 'Engine'
PIN = json.loads((ENGINE / 'engine.lock.json').read_text())
FRAMEWORK = 'Chromium Embedded Framework.framework'

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            digest.update(block)
    return digest.hexdigest()

def run(*args, **kwargs):
    subprocess.run(list(map(str,args)),check=True,**kwargs)

def verify_patches():
    for patch in PIN['patches']:
        if sha(ENGINE / patch['file']) != patch['sha256']:
            raise SystemExit('Engine patch changed. Update engine.lock.json and publish a new engine version.')

def fetch():
    verify_patches()
    archive = PIN['archive']
    if not archive['sha256']:
        raise SystemExit('Engine archive is not published yet. Build it from source or set BROWSER_ENGINE_FRAMEWORK.')
    vendor = NATIVE / 'vendor'; vendor.mkdir(exist_ok=True)
    target = vendor / ('engine-'+PIN['version'])
    package = vendor / archive['name']
    if not package.exists():
        with tempfile.NamedTemporaryFile(dir=vendor,suffix='.part') as pending:
            with urllib.request.urlopen(archive['url'],timeout=120) as response:
                shutil.copyfileobj(response,pending)
            pending.flush()
            if sha(Path(pending.name)) != archive['sha256']:
                raise SystemExit('Engine download failed SHA-256 verification')
            shutil.copyfile(pending.name,package)
    if sha(package) != archive['sha256']:
        raise SystemExit('Engine archive SHA-256 mismatch; file preserved for inspection')
    if not target.exists():
        with tempfile.TemporaryDirectory(dir=vendor) as stage:
            # The digest pins an audited artifact; bsdtar additionally prevents
            # traversal. Reject device files, absolute paths and parent links.
            with tarfile.open(package) as bundle:
                for member in bundle:
                    if Path(member.name).is_absolute() or '..' in Path(member.name).parts or member.isdev() or member.isfifo():
                        raise SystemExit('Unsafe engine archive member')
            run('/usr/bin/tar','-xf',package,'-C',stage)
            Path(stage).rename(target)
    metadata = json.loads((target/'engine.json').read_text())
    if metadata['version'] != PIN['version'] or metadata['patches'] != PIN['patches']:
        raise SystemExit('Engine provenance mismatch')
    if not (target/FRAMEWORK/'Chromium Embedded Framework').is_file():
        raise SystemExit('Engine extraction incomplete')
    print(target/FRAMEWORK)

def source(args):
    verify_patches()
    if not args.root:
        raise SystemExit('--root /path/on/a/large/local/disk is required (hundreds of GB)')
    root = Path(args.root).expanduser().resolve(); root.mkdir(parents=True,exist_ok=True)
    if shutil.disk_usage(root).free < 12*1024**3:
        raise SystemExit('Keep at least 12 GiB free throughout the engine build')
    src = root/'chromium_git/chromium/src'; depot = root/'depot_tools'
    env = os.environ.copy()
    env.update(DEPOT_TOOLS_UPDATE='0', GN_DEFINES=PIN['gnDefines'], GN_OUT_CONFIGS='Release_GN_arm64',
               PATH=str(depot)+':'+env['PATH'], PYTHONUNBUFFERED='1')
    if args.command == 'prepare':
        if not depot.exists(): run('git','clone','https://chromium.googlesource.com/chromium/tools/depot_tools.git',depot)
        run('git','-C',depot,'fetch','origin',PIN['depotToolsCommit'])
        run('git','-C',depot,'checkout','--detach',PIN['depotToolsCommit'])
        script = root/'automate-git.py'
        with urllib.request.urlopen('https://raw.githubusercontent.com/chromiumembedded/cef/'+PIN['cefCommit']+'/tools/automate/automate-git.py',timeout=60) as response:
            script.write_bytes(response.read())
        run('/usr/bin/python3',script,'--download-dir='+str(root/'chromium_git'),'--depot-tools-dir='+str(depot),
            '--branch='+PIN['branch'],'--checkout='+PIN['cefCommit'],'--arm64-build','--no-chromium-history','--no-build','--no-distrib',env=env)
    for directory,revision in [(src,PIN['chromiumCommit']),(src/'cef',PIN['cefCommit'])]:
        actual = subprocess.check_output(['git','-C',str(directory),'rev-parse','HEAD'],text=True).strip()
        if actual != revision: raise SystemExit('Unexpected source revision: '+str(directory))
    patches = [ENGINE/p['file'] for p in PIN['patches']]
    if args.command == 'configure':
        # Verify the entire stack in a scratch tree. Never reverse live sources.
        applied = subprocess.run(['/usr/bin/python3',str(NATIVE/'scripts/check-engine-patches.py'),str(src),*map(str,patches)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0
        if not applied:
            # git apply performs all checks before changing the source tree.
            run('git','apply','--check',*patches,cwd=src)
            run('git','apply',*patches,cwd=src)
        run('/usr/bin/python3','tools/gclient_hook.py',cwd=src/'cef',env=env)
    if args.command == 'build':
        run('/usr/bin/python3',NATIVE/'scripts/check-engine-patches.py',src,*patches)
        run(src/'third_party/ninja/ninja','-C',src/'out/Release_GN_arm64','-j',args.jobs,PIN['buildTarget'],env=env)
        print(src/'out/Release_GN_arm64'/FRAMEWORK)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['fetch','prepare','configure','build'])
    parser.add_argument('--root',help='Dedicated directory, never a browser profile')
    parser.add_argument('--jobs',type=int,default=4)
    args = parser.parse_args()
    if args.command == 'fetch': fetch()
    else: source(args)
