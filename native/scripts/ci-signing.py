#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Only for ephemeral GitHub-hosted runners; never mutates a user's keychain."""
import base64
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys

if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
    raise SystemExit('This command only supports ephemeral GitHub-hosted runners')
root = Path(os.environ['RUNNER_TEMP'])/'arc-signing'
keychain = root/'release.keychain-db'

def run(*args): subprocess.run(list(map(str,args)),check=True,stdout=subprocess.DEVNULL)

if sys.argv[1] == 'cleanup':
    if keychain.exists(): run('security','delete-keychain',keychain)
    if root.exists(): shutil.rmtree(root)
elif sys.argv[1] == 'setup':
    root.mkdir(mode=0o700)
    for name,secret in [('certificate.p12','APPLE_CERTIFICATE_P12'),('notary.p8','APPLE_NOTARY_KEY'),('sparkle.key','SPARKLE_PRIVATE_KEY')]:
        data = os.environ[secret]
        if not data: raise SystemExit('Missing release secret: '+secret)
        path = root/name
        path.write_bytes(base64.b64decode(data,validate=True) if name.endswith('.p12') else data.encode())
        path.chmod(0o600)
    password = secrets.token_hex(32)
    run('security','create-keychain','-p',password,keychain)
    run('security','set-keychain-settings','-lut','3600',keychain)
    run('security','unlock-keychain','-p',password,keychain)
    run('security','import',root/'certificate.p12','-k',keychain,'-P',os.environ['APPLE_CERTIFICATE_PASSWORD'],'-T','/usr/bin/codesign','-T','/usr/bin/security')
    run('security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,keychain)
    run('security','list-keychains','-d','user','-s',keychain)
    with open(os.environ['GITHUB_ENV'],'a') as output:
        if os.environ.get('APPLE_PASSKEY_PROFILE'):
            profile = root/'browser.provisionprofile'
            profile.write_bytes(base64.b64decode(os.environ['APPLE_PASSKEY_PROFILE'],validate=True))
            profile.chmod(0o600)
            output.write('BROWSER_PASSKEY_PROFILE='+str(profile)+'\n')
        output.write('BROWSER_NOTARY_KEY='+str(root/'notary.p8')+'\nSPARKLE_PRIVATE_KEY_FILE='+str(root/'sparkle.key')+'\n')
