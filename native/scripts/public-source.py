#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Explicit public-source export; never recursively copies the private workspace.

audit is also run on pull requests. It is a guardrail, not a substitute for review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
DIRECTORIES = ['native/Sources','native/Bridge','native/Tests','native/Resources','native/Signing',
               'native/Demo','native/Engine/patches','native/Engine/licenses','design/app-icon/ArcReborn.icon',
               '.github/workflows','.github/ISSUE_TEMPLATE','docs/development']
FILES = ['README.md','LICENSE','NOTICE.md','CONTRIBUTING.md','SECURITY.md','.gitignore','Makefile',
         '.github/pull_request_template.md','native/CMakeLists.txt','native/Engine/engine.lock.json','native/Engine/performance-candidate.gn','native/Engine/monitor.html']
SCRIPTS = ['test-extension-placement.sh','build.sh','dev.sh','check.sh','fetch-cef.py','fetch-sparkle.py','make-icon.sh',
           'engine.py','performance-engine.py','monitor-engine.py','check-performance-candidate.sh','engine-framework-fingerprint.py','check-engine-patches.py',
           'welcome-assets.sh','onboarding-demo.sh','sign-and-notarize.sh','sign-sparkle.sh','release.py','verify-release.swift','ci-signing.py','public-source.py']
FILES += ['native/scripts/'+name for name in SCRIPTS]
FORBIDDEN = {'server','node_modules','vendor','build','dist','.env','profile','Chromium','.DS_Store','__pycache__'}
SUFFIXES = {'.p8','.p12','.pfx','.pem','.key','.dmg','.zip','.log','.pyc','.certSigningRequest','.mobileprovision'}
PATTERNS = [rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
            rb'postgres(?:ql)?://[^\s/:]+:[^\s/@]+@',rb'gh[pousr]_[A-Za-z0-9]{30,}',
            rb'\bre_[A-Za-z0-9]{30,}',rb'\bAKIA[0-9A-Z]{16}\b']

def audit(root):
    failures = []
    for path in root.rglob('*'):
        relative = path.relative_to(root)
        if '.git' in relative.parts: continue
        if path.is_symlink(): failures.append(str(relative)+' (symlink)'); continue
        if not path.is_file(): continue
        if any(part in FORBIDDEN or part.endswith(('.app','.framework','.sparsebundle')) for part in relative.parts) or path.suffix in SUFFIXES or path.name.startswith('.env'):
            failures.append(str(relative)+' (private/generated file)'); continue
        if path.stat().st_size > 5*1024*1024: failures.append(str(relative)+' (large binary)'); continue
        data = path.read_bytes()
        if any(re.search(pattern,data) for pattern in PATTERNS): failures.append(str(relative)+' (potential credential)')
    if failures: raise ValueError('Public-source audit failed:\n'+'\n'.join(failures))
    print('Public-source boundary verified; no known secret patterns found.')

def export(destination):
    if destination.exists(): raise ValueError('Destination must not exist')
    destination.mkdir(parents=True)
    for name in FILES:
        source = ROOT/name
        if not source.is_file(): raise ValueError('Missing source: '+name)
        target = destination/name; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,target)
    for name in DIRECTORIES:
        for source in (ROOT/name).rglob('*'):
            if source.is_symlink(): raise ValueError('Unexpected symlink: '+str(source))
            if source.is_file() and source.name != '.DS_Store' and '__pycache__' not in source.parts:
                target = destination/source.relative_to(ROOT); target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,target)
    audit(destination)
    entries = {str(p.relative_to(destination)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(destination.rglob('*')) if p.is_file()}
    (destination.parent/(destination.name+'-manifest.json')).write_text(json.dumps(entries,indent=2)+'\n')
    print(str(len(entries))+' files exported to '+str(destination))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['audit','export']); parser.add_argument('path',type=Path)
    args = parser.parse_args()
    if args.command == 'audit': audit(args.path.resolve())
    else: export(args.path.resolve())
