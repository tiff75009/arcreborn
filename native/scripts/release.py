#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Resumable Developer ID -> notarization -> DMG -> signed Sparkle feed -> draft.

Never publishes automatically. `draft` uploads only explicit release assets.
Use the same commands locally or in the protected GitHub release environment.
"""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT/'native'
REPO = 'tiff75009/arcreborn'

def run(*args, capture=False, **kwargs):
    result = subprocess.run(list(map(str,args)),check=True,text=True,
                            stdout=subprocess.PIPE if capture else None,**kwargs)
    return result.stdout.strip() if capture else None

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for data in iter(lambda: source.read(1024*1024),b''): value.update(data)
    return value.hexdigest()

def bundle_digest(path):
    value = hashlib.sha256()
    for entry in sorted(path.rglob('*')):
        value.update(str(entry.relative_to(path)).encode()+b'\0')
        if entry.is_symlink(): value.update(os.readlink(entry).encode())
        elif entry.is_file(): value.update(digest(entry).encode())
    return value.hexdigest()

def metadata():
    notes = json.loads((NATIVE/'Resources/ReleaseNotes.json').read_text())
    info = plistlib.loads((NATIVE/'Resources/Info.plist').read_bytes())
    if not re.fullmatch(r'\d+\.\d+\.\d+',notes['version']) or type(notes['build']) is not int or notes['build'] <= 0:
        raise ValueError('Stable version x.y.z and positive integer build required')
    if info['CFBundleShortVersionString'] != notes['version'] or info['CFBundleVersion'] != str(notes['build']):
        raise ValueError('Info.plist and ReleaseNotes.json versions differ')
    if not 1 <= len(notes['highlights']) <= 12: raise ValueError('Provide 1–12 curated release highlights')
    for item in [notes['title'],notes['subtitle'],*[t for row in notes['highlights'] for t in [row['title'],row['detail']]]]:
        if any(not isinstance(item.get(lang),str) or not item[lang].strip() for lang in ['fr','en']):
            raise ValueError('French and English release copy required')
    return notes,info

def authentication():
    env = os.environ
    if env.get('BROWSER_NOTARY_KEYCHAIN_PROFILE'): return ['--keychain-profile',env['BROWSER_NOTARY_KEYCHAIN_PROFILE']]
    args = ['--key',env['BROWSER_NOTARY_KEY'],'--key-id',env['BROWSER_NOTARY_KEY_ID']]
    if env.get('BROWSER_NOTARY_ISSUER'): args += ['--issuer',env['BROWSER_NOTARY_ISSUER']]
    return args

def notarize(package, directory):
    state = directory/(package.name+'.notary.json')
    checksum = digest(package)
    auth = authentication()
    if state.exists():
        receipt = json.loads(state.read_text())
        if receipt['sha256'] != checksum: raise ValueError('Archive changed after notarization submission')
    else:
        receipt = json.loads(run('xcrun','notarytool','submit',package,*auth,'--output-format','json',capture=True))
        receipt['sha256'] = checksum; state.write_text(json.dumps(receipt,indent=2)+'\n')
    for attempt in range(120):
        result = json.loads(run('xcrun','notarytool','info',receipt['id'],*auth,'--output-format','json',capture=True))
        print(package.name+': '+result['status'],flush=True)
        if result['status'] == 'Accepted': return
        if result['status'] != 'In Progress':
            run('xcrun','notarytool','log',receipt['id'],*auth,directory/(package.name+'.rejection.json'))
            raise ValueError('Apple rejected the archive; see rejection log')
        time.sleep(10)
    raise ValueError('Notarization still pending; rerun to resume the same submission')

def prepare(args,notes,info):
    out = Path(args.output).resolve(); out.mkdir(parents=True,exist_ok=True)
    source = Path(args.app).resolve()
    bundle_info = plistlib.loads((source/'Contents/Info.plist').read_bytes())
    for key in ['CFBundleVersion','CFBundleShortVersionString','CFBundleIdentifier','SUFeedURL','SUPublicEDKey',
                'SURequireSignedFeed','SUVerifyUpdateBeforeExtraction','SUEnableAutomaticChecks','SUAutomaticallyUpdate',
                'SUScheduledCheckInterval','SUScheduledImpatientCheckInterval']:
        if bundle_info.get(key) != info[key]: raise ValueError('Bundle metadata mismatch: '+key)
    if bundle_info.get('ArcRebornDevelopmentBuild'): raise ValueError('Cannot release a development bundle')
    if json.loads((source/'Contents/Resources/ReleaseNotes.json').read_text()) != notes:
        raise ValueError('Bundle release notes mismatch')
    provenance = out/'source.json'
    source_hash = bundle_digest(source)
    if provenance.exists() and json.loads(provenance.read_text())['sha256'] != source_hash:
        raise ValueError('Source bundle changed; use a new release output directory')
    provenance.write_text(json.dumps({'sha256':source_hash,'version':notes['version'],'build':notes['build']},indent=2)+'\n')
    app = out/'Arc Reborn.app'
    if not app.exists(): run(NATIVE/'scripts/sign-and-notarize.sh','sign',source,app)
    run('codesign','--verify','--deep','--strict',app)
    archive = out/'notarization.zip'
    if not archive.exists(): run('ditto','-c','-k','--keepParent',app,archive)
    notarize(archive,out)
    run('xcrun','stapler','staple',app); run('xcrun','stapler','validate',app)
    assets = out/'assets'; assets.mkdir(exist_ok=True)
    name = 'ArcReborn-'+notes['version']+'-macos-arm64'
    dmg = assets/(name+'.dmg')
    if not dmg.exists():
        with_stage = out/'disk-image'; with_stage.mkdir(exist_ok=True)
        if not (with_stage/'Arc Reborn.app').exists(): run('ditto',app,with_stage/'Arc Reborn.app')
        if not (with_stage/'Applications').is_symlink(): (with_stage/'Applications').symlink_to('/Applications')
        run('hdiutil','create','-volname','Arc Reborn','-srcfolder',with_stage,'-ov','-format','UDZO',dmg)
        identity = os.environ.get('BROWSER_SIGN_IDENTITY')
        if not identity:
            value = run('codesign','-d','--extract-certificates',str(out/'signer'),app,capture=True,stderr=subprocess.DEVNULL)
            identity = hashlib.sha1((out/'signer0').read_bytes()).hexdigest().upper()
        run('codesign','--force','--timestamp','--sign',identity,dmg)
    # Stapling mutates the DMG. Once validated, retain the exact notarized asset.
    valid = subprocess.run(['xcrun','stapler','validate',str(dmg)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0
    if not valid:
        notarize(dmg,out); run('xcrun','stapler','staple',dmg)
    run('xcrun','stapler','validate',dmg); run('codesign','--verify','--strict',dmg)
    body = '<h2>'+html.escape(notes['title']['fr'])+'</h2><p>'+html.escape(notes['subtitle']['fr'])+'</p><ul>'
    body += ''.join('<li><b>'+html.escape(row['title']['fr'])+'</b> — '+html.escape(row['detail']['fr'])+'</li>' for row in notes['highlights'])+'</ul>'
    (assets/(name+'.html')).write_text(body+'\n')
    sparkle = Path(run('/usr/bin/python3',NATIVE/'scripts/fetch-sparkle.py',capture=True))
    key = ['--ed-key-file',os.environ['SPARKLE_PRIVATE_KEY_FILE']] if os.environ.get('SPARKLE_PRIVATE_KEY_FILE') else ['--account','arc-reborn']
    run(sparkle/'bin/generate_appcast',*key,'--download-url-prefix',f'https://github.com/{REPO}/releases/download/v{notes["version"]}/',
        '--embed-release-notes','--maximum-deltas','0',assets)
    run('xcrun','swift',NATIVE/'scripts/verify-release.swift',NATIVE/'Resources/Info.plist',assets)
    release = {'version':notes['version'],'build':notes['build'],'engine':json.loads((NATIVE/'Engine/engine.lock.json').read_text())['version']}
    (assets/'release.json').write_text(json.dumps(release,indent=2)+'\n')
    markdown = '# Arc Reborn '+notes['version']+'\n\n'+notes['subtitle']['fr']+'\n\n'
    markdown += '\n'.join('- **'+row['title']['fr']+'** — '+row['detail']['fr'] for row in notes['highlights'])
    markdown += '\n\nmacOS 13+ · Apple Silicon · Developer ID · Notarisation Apple\n'
    (out/'CHANGELOG.md').write_text(markdown)
    paths = [dmg,assets/'appcast.xml',assets/'release.json']
    (assets/'SHA256SUMS').write_text(''.join(digest(p)+'  '+p.name+'\n' for p in paths))
    print('Prepared: '+str(assets))

def draft(args,notes):
    # Tags must already exist, pointing to precisely the reviewed sources.
    tag = 'v'+notes['version']
    head = run('git','rev-parse','HEAD',capture=True,cwd=ROOT)
    if run('git','rev-parse',tag+'^{commit}',capture=True,cwd=ROOT) != head: raise ValueError('Release tag must match HEAD')
    if run('git','status','--porcelain','--untracked-files=no',capture=True,cwd=ROOT): raise ValueError('Commit source changes before publishing')
    if os.environ.get('GITHUB_REF') and os.environ['GITHUB_REF'] != 'refs/tags/'+tag: raise ValueError('Wrong release tag')
    # Compare with every published browser release, not the engine prerelease.
    releases = json.loads(run('gh','api',f'repos/{REPO}/releases?per_page=100',capture=True))
    for release in releases:
        if not release['draft'] and release['tag_name'].startswith('v'):
            existing = release['tag_name'][1:]
            if re.fullmatch(r'\d+\.\d+\.\d+',existing) and tuple(map(int,existing.split('.'))) >= tuple(map(int,notes['version'].split('.'))):
                raise ValueError('Version must exceed published versions')
            # Sparkle orders by CFBundleVersion, independently of the display version.
            asset = next((a for a in release['assets'] if a['name'] == 'release.json'),None)
            if asset:
                old = json.loads(run('gh','api',f'repos/{REPO}/releases/assets/{asset["id"]}',
                                     '-H','Accept: application/octet-stream',capture=True))
                if notes['build'] <= old['build']: raise ValueError('Build must exceed every published build')
    out = Path(args.output).resolve(); assets = out/'assets'
    manifest = json.loads((assets/'release.json').read_text())
    if manifest['version'] != notes['version'] or manifest['build'] != notes['build']: raise ValueError('Stale release assets')
    for line in (assets/'SHA256SUMS').read_text().splitlines():
        expected,name = line.split('  ',1)
        if Path(name).name != name or digest(assets/name) != expected: raise ValueError('Release checksum mismatch')
    run('gh','release','create',tag,'--repo',REPO,'--verify-tag','--draft','--title','Arc Reborn '+notes['version'],
        '--notes-file',out/'CHANGELOG.md',assets/('ArcReborn-'+notes['version']+'-macos-arm64.dmg'),assets/'appcast.xml',assets/'release.json',assets/'SHA256SUMS')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['check','prepare','draft'])
    parser.add_argument('--app',default=str(NATIVE/'build/Arc Reborn.app'))
    parser.add_argument('--output',default=str(NATIVE/'build/release'))
    args = parser.parse_args()
    notes,info = metadata()
    if args.command == 'prepare': prepare(args,notes,info)
    elif args.command == 'draft': draft(args,notes)
    else: print('Release metadata valid: '+notes['version']+' ('+str(notes['build'])+')')
