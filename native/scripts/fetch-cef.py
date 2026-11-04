#!/usr/bin/env python3
"""Fetch the pinned official CEF archive, verify it, and reuse a local extraction."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'vendor'
PIN = json.loads((ROOT / 'Resources' / 'cef-version.json').read_text())
ARCHIVE = PIN['archive']
NAME = ARCHIVE['name']
if Path(NAME).name != NAME or not NAME.endswith('_macosarm64.tar.bz2'):
    raise SystemExit('Unexpected CEF archive name')
VENDOR.mkdir(parents=True, exist_ok=True)
archive_path = VENDOR / NAME

def verify(p):
    if not p.is_file() or p.stat().st_size != ARCHIVE['size']:
        return False
    digest = hashlib.sha1()
    with p.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest() == ARCHIVE['sha1']

if archive_path.exists() and not verify(archive_path):
    raise SystemExit('Existing CEF archive failed its pinned size/SHA-1 check; preserved for inspection')
if not archive_path.exists():
    url = 'https://cef-builds.spotifycdn.com/' + urllib.parse.quote(NAME)
    descriptor, temporary = tempfile.mkstemp(prefix='cef-download-', suffix='.part', dir=VENDOR)
    os.close(descriptor)
    try:
        print('Downloading pinned CEF from ' + url, flush=True)
        with urllib.request.urlopen(url, timeout=120) as response, open(temporary, 'wb') as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
        if not verify(Path(temporary)):
            raise SystemExit('Downloaded CEF failed pinned size/SHA-1 verification')
        os.replace(temporary, archive_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

folder = VENDOR / NAME.removesuffix('.tar.bz2')
if not folder.exists():
    # Validate paths before delegating extraction of the hash-pinned official
    # archive to macOS bsdtar (which also enforces extraction traversal checks).
    with tarfile.open(archive_path, 'r:bz2') as archive:
        for member in archive:
            name = Path(member.name)
            if name.is_absolute() or '..' in name.parts or name.parts[0] != folder.name:
                raise SystemExit('Unsafe archive member: ' + member.name)
            if member.isdev() or member.isfifo():
                raise SystemExit('Unsupported special archive member')
    subprocess.run(['/usr/bin/tar', '-xjf', str(archive_path), '-C', str(VENDOR)], check=True)
required = [folder / 'include/cef_app.h', folder / 'cmake/FindCEF.cmake', folder / 'Release/Chromium Embedded Framework.framework/Chromium Embedded Framework', folder / 'Release/Chromium Embedded Framework.framework/Libraries/libcef_sandbox.dylib']
if not all(p.is_file() for p in required):
    raise SystemExit('CEF extraction is incomplete; files preserved, no automatic overwrite')
(VENDOR / 'cef-path.txt').write_text(str(folder) + '\n')
(VENDOR / 'cef-version.json').write_text(json.dumps(PIN, indent=2) + '\n')
print('Verified CEF ' + PIN['version'])
