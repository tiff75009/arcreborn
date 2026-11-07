#!/usr/bin/env python3
"""Check a locally built engine before packaging it, without loading its code."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys


def fingerprint(framework, reference):
    binary = framework / 'Chromium Embedded Framework'
    with (framework / 'Resources/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    with (reference / 'Resources/Info.plist').open('rb') as stream:
        expected = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != 'org.cef.framework':
        raise ValueError('Not a CEF framework')
    # Require the same Chromium revision as the pinned distribution. The private
    # patches change internal code only, not the CEF public API used by the wrapper.
    revision = info.get('SCMRevision', '').split('-')[0]
    if not revision or revision != expected.get('SCMRevision', '').split('-')[0]:
        raise ValueError('Engine Chromium revision differs from the pinned CEF distribution')
    arch = subprocess.check_output(['/usr/bin/lipo', '-archs', str(binary)], text=True).split()
    if 'arm64' not in arch:
        raise ValueError('The engine does not contain arm64 code')
    exports = set(subprocess.check_output(['/usr/bin/nm', '-gjU', str(binary)], text=True).split())
    required = {'_browser_native_navigation_version_v1', '_browser_execute_extension_action_v1', '_browser_close_extension_popup_v1',
                '_browser_set_extension_tab_creator_v1', '_browser_set_extension_install_notice_v1',
                '_browser_extension_popup_state_v1', '_browser_set_extension_dialog_bounds_v1', '_browser_attach_native_view_v1', '_browser_native_view_visibility_v1',
                '_browser_download_info_v1', '_browser_recover_download_v1', '_browser_suspend_downloads_v1',
                '_browser_observe_tab_sound_v1', '_browser_snapshot_tab_history_v1', '_browser_restore_tab_history_v1', '_cef_api_hash', '_cef_initialize'}
    missing = required - exports
    if missing:
        raise ValueError('Engine exports missing: ' + ', '.join(sorted(missing)))
    for path in ('Libraries/libcef_sandbox.dylib', 'Resources/icudtl.dat',
                 'Resources/resources.pak'):
        if not (framework / path).is_file():
            raise ValueError('Incomplete framework: ' + path)
    digest = hashlib.sha256()
    # Include resources and helper libraries as well as the executable. A new
    # resource-only build must not accidentally reuse the old app framework.
    for path in sorted(framework.rglob('*')):
        relative = path.relative_to(framework)
        if '_CodeSignature' in relative.parts:
            continue
        if path.is_file():
            digest.update(str(relative).encode() + b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
    return 'private-' + digest.hexdigest()


if __name__ == '__main__':
    try:
        print(fingerprint(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
