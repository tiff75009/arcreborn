#!/usr/bin/env python3
"""Fetch Sparkle's pinned distribution. No signing key or account is required."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

VERSION = '2.10.1'
SHA256 = '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'
ROOT = Path(__file__).resolve().parents[1] / 'vendor'

def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    archive = ROOT / f'Sparkle-{VERSION}.tar.xz'
    destination = ROOT / f'sparkle-{VERSION}'
    if not archive.exists():
        with tempfile.NamedTemporaryFile(dir=ROOT, suffix='.part') as pending:
            with urllib.request.urlopen(f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/{archive.name}', timeout=120) as response:
                shutil.copyfileobj(response, pending)
            pending.flush()
            if hashlib.sha256(Path(pending.name).read_bytes()).hexdigest() != SHA256:
                raise SystemExit('Sparkle SHA-256 mismatch')
            shutil.copyfile(pending.name, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit('Sparkle SHA-256 mismatch; existing archive preserved')
    if not destination.exists():
        with tempfile.TemporaryDirectory(dir=ROOT) as stage:
            subprocess.run(['/usr/bin/tar','-xf',str(archive),'-C',stage],check=True)
            Path(stage).rename(destination)
    if not (destination / 'Sparkle.framework/Sparkle').is_file():
        raise SystemExit('Incomplete Sparkle distribution')
    print(destination)

if __name__ == '__main__':
    main()
