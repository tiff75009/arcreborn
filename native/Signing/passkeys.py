#!/usr/bin/env python3
"""Prepare and verify the browser-only Apple Passwords entitlement for Developer ID."""
import argparse
import datetime
import hashlib
from pathlib import Path
import plistlib
import subprocess

CAPABILITY = 'com.apple.developer.web-browser.public-key-credential'
APP_ID = 'com.apple.application-identifier'
TEAM_ID = 'com.apple.developer.team-identifier'


def profile_entitlements(profile, bundle, team, certificate):
    grants = profile['Entitlements']
    app_id = grants.get(APP_ID)
    if (team not in profile['TeamIdentifier'] or grants.get(TEAM_ID) != team
            or app_id not in {prefix + '.' + bundle for prefix in profile['ApplicationIdentifierPrefix']}):
        raise ValueError('Passkey profile does not match the signing team and explicit bundle ID')
    if (not {'OSX', 'macOS'}.intersection(profile['Platform'])
            or profile.get('ProvisionsAllDevices') is not True
            or grants.get('com.apple.security.get-task-allow') or grants.get('get-task-allow')):
        raise ValueError('A macOS Developer ID distribution profile is required')
    if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError('Expired passkey provisioning profile')
    if grants.get(CAPABILITY) is not True:
        raise ValueError('Apple has not authorized browser passkeys in this profile')
    if certificate not in {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}:
        raise ValueError('The Developer ID signing certificate is not listed in the passkey profile')
    return {CAPABILITY: True, APP_ID: app_id, TEAM_ID: team}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('profile', type=Path)
    parser.add_argument('team')
    parser.add_argument('certificate', help='Developer ID certificate SHA-1')
    parser.add_argument('--prepare', type=Path, metavar='ENTITLEMENTS')
    args = parser.parse_args()
    contents = args.app / 'Contents'
    bundle = plistlib.loads((contents/'Info.plist').read_bytes())['CFBundleIdentifier']
    profile_data = args.profile.read_bytes()
    decoded = subprocess.check_output(['/usr/bin/security', 'cms', '-D'], input=profile_data)
    grants = profile_entitlements(plistlib.loads(decoded), bundle, args.team, args.certificate)
    framework = contents/'Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework'
    if '_browser_webauthn_window_v1' not in subprocess.check_output(['/usr/bin/nm', '-gjU', framework], text=True).splitlines():
        raise ValueError('Build with the AppKit passkey engine before signing this app')
    embedded = contents/'embedded.provisionprofile'
    if args.prepare:
        policy = plistlib.loads(Path(__file__).with_name('app.entitlements').read_bytes())
        args.prepare.write_bytes(plistlib.dumps({**policy, **grants}))
        embedded.write_bytes(profile_data)
    else:
        signed = plistlib.loads(subprocess.check_output(['/usr/bin/codesign', '-d', '--entitlements', '-', '--xml', args.app]))
        if (embedded.read_bytes() != profile_data or signed.get(CAPABILITY) is not True
                or signed.get(APP_ID) != grants[APP_ID] or signed.get(TEAM_ID) != args.team):
            raise ValueError('Signed browser or embedded profile does not match the requested passkey capability')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
