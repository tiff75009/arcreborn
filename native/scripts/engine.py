#!/usr/bin/env python3
"""Portable CEF source build and verified binary distribution for contributors.

Source builds are opt-in; never start a Chromium build during a normal dev build.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

NATIVE = Path(__file__).resolve().parents[1]
ENGINE = NATIVE / 'Engine'
FRAMEWORK = 'Chromium Embedded Framework.framework'

def load_pin(use_passkeys):
    pin = json.loads((ENGINE / 'engine.lock.json').read_text())
    if use_passkeys and not any(p["file"] == "patches/appkit-passkey-window.patch" for p in pin["patches"]):
        variant = json.loads((ENGINE / 'passkeys.lock.json').read_text())
        if pin['version'] != variant['baseVersion']:
            raise ValueError('Rebase the passkey engine patch on the new base engine')
        pin['patches'].append(variant['patch'])
        pin.update(version=variant['version'], archive=variant['archive'])
    return pin

PIN = load_pin(os.environ.get('BROWSER_PASSKEY_PROFILE') or os.environ.get('BROWSER_PASSKEY_ENGINE') == '1')

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
    delta = PIN['archive'].get('delta')
    if delta and sha(ENGINE/delta['file']) != delta['sha256']:
        raise SystemExit('Engine binary delta failed SHA-256 verification')

def apply_archive_delta(stage, delta):
    # Produce the new framework from an immutable, already verified public archive.
    # bspatch ships with macOS. Both input and output identify exact engine builds.
    binary = (stage/FRAMEWORK/'Chromium Embedded Framework').resolve()
    patch = ENGINE/delta['file']
    provenance = stage/'engine.json'
    metadata = json.loads(provenance.read_text())
    if metadata['version'] != delta['baseVersion'] or sha(binary) != delta['baseBinarySHA256']:
        raise SystemExit('Engine delta input checksum or version mismatch')
    overrides = delta.get('gnOverrides', {})
    base_flags = dict(option.split('=', 1) for option in shlex.split(metadata['gnDefines']))
    target_flags = dict(option.split('=', 1) for option in shlex.split(PIN['gnDefines']))
    if base_flags | overrides != target_flags:
        raise SystemExit('Engine delta does not account for all changed GN flags')
    actual_args = metadata['build']['gnArgs']
    for name, value in overrides.items():
        if value not in ('true', 'false') or name not in base_flags or actual_args.get(name) != base_flags[name]:
            raise SystemExit('Unexpected base build argument for engine delta: '+name)
    output = binary.with_suffix('.new')
    run('/usr/bin/bspatch', binary, output, patch)
    if sha(output) != delta['binarySHA256']:
        raise SystemExit('Patched engine failed SHA-256 verification')
    output.chmod(binary.stat().st_mode)
    output.replace(binary)
    actual_args.update(overrides)
    metadata.update(version=PIN['version'], patches=PIN['patches'], gnDefines=PIN['gnDefines'])
    metadata['build'].update(binarySHA256=delta['binarySHA256'], baseEngineVersion=delta['baseVersion'])
    for entry in PIN['patches']:
        source = ENGINE/entry['file']
        shutil.copyfile(source, stage/'patches'/source.name)
    provenance.write_text(json.dumps(metadata, indent=2)+'\n')

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
            if delta := archive.get('delta'):
                apply_archive_delta(Path(stage), delta)
            try:
                Path(stage).rename(target)
            except OSError:
                # A concurrent build may have finished installing the same verified engine.
                if not target.is_dir():
                    raise
    metadata = json.loads((target/'engine.json').read_text())
    if metadata['version'] != PIN['version'] or metadata['patches'] != PIN['patches'] or metadata.get('gnDefines') != PIN['gnDefines']:
        raise SystemExit('Engine provenance mismatch')
    if not (target/FRAMEWORK/'Chromium Embedded Framework').is_file():
        raise SystemExit('Engine extraction incomplete')
    print(target/FRAMEWORK)

def prepare_release_tools(src, depot, env):
    """Fetch only the optimization profiles and tools pinned by this checkout."""
    py = depot / (depot / 'python3_bin_reldir.txt').read_text().strip() / 'python3'
    def tool(*args):
        run(*args, cwd=src, env=env)

    # An existing local checkout may never have run the release-only symbol hook.
    symbols = src/'tools/clang/dsymutil/bin'
    if not (symbols/'dsymutil').is_file():
        import urllib.request, tempfile
        expected = (symbols/'dsymutil.arm64.sha1').read_text().strip()
        if not re.fullmatch(r'[a-f0-9]{40}', expected):
            raise SystemExit('Invalid pinned dsymutil hash')
        with tempfile.NamedTemporaryFile(dir=symbols) as temp:
            with urllib.request.urlopen('https://storage.googleapis.com/chromium-browser-clang/' + expected, timeout=90) as response:
                shutil.copyfileobj(response, temp)
            temp.flush()
            if hashlib.sha1(Path(temp.name).read_bytes()).hexdigest() != expected:
                raise SystemExit('dsymutil checksum mismatch')
            os.chmod(temp.name, 0o755)
            os.link(temp.name, symbols/'dsymutil')

    # These are the profiles associated with this exact Chromium/V8 release.
    # Both hooks are idempotent; the V8 one also checks the revision in DEPS.
    pgo = (src/'chrome/build/mac-arm.pgo.txt').read_text().strip()
    if not (src/'chrome/build/pgo_profiles'/pgo).is_file():
        tool(py, 'tools/update_pgo_profiles.py', '--target', 'mac-arm', 'update',
             '--gs-url-base=chromium-optimization-profiles/pgo_profiles')
    tool(py, 'v8/tools/builtins-pgo/download_profiles.py', 'download', '--depot-tools', depot, '--check-v8-revision')

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
        stack_check = NATIVE/'scripts/check-engine-patches.py'
        for count in range(len(patches),0,-1):
            if subprocess.run(['/usr/bin/python3',str(stack_check),str(src),*map(str,patches[:count])],
                              stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0:
                break
        else:
            count = 0
        for patch in patches[count:]:
            run('git','apply','--check',patch,cwd=src)
            run('git','apply',patch,cwd=src)
        py = depot / (depot/'python3_bin_reldir.txt').read_text().strip() / 'python3'
        env['PATH'] = str(py.parent) + ':' + str(src/'buildtools/mac') + ':' + env['PATH']
        if 'is_official_build=true' in PIN['gnDefines'].split():
            prepare_release_tools(src, depot, env)
        run(py,'tools/gclient_hook.py',cwd=src/'cef',env=env)
    if args.command == 'build':
        run('/usr/bin/python3',NATIVE/'scripts/check-engine-patches.py',src,*patches)
        run(src/'third_party/ninja/ninja','-C',src/'out/Release_GN_arm64','-j',args.jobs,PIN['buildTarget'],env=env)
        print(src/'out/Release_GN_arm64'/FRAMEWORK)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['fetch','prepare','configure','build','version'])
    parser.add_argument('--root',help='Dedicated directory, never a browser profile')
    parser.add_argument('--jobs',type=int,default=4)
    args = parser.parse_args()
    if args.command == 'fetch': fetch()
    elif args.command == 'version': print(PIN['version'])
    else: source(args)
