#!/usr/bin/env python3
"""Boundary tests: reject private files, mismatched versions and modified patches."""
import importlib.util
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def module(name):
    spec = importlib.util.spec_from_file_location(name,ROOT/'scripts'/(name+'.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value

release = module('release'); public = module('public-source'); engine = module('engine')
spec = importlib.util.spec_from_file_location('passkeys',ROOT/'Signing/passkeys.py')
passkeys = importlib.util.module_from_spec(spec)
spec.loader.exec_module(passkeys)

class ReleaseTests(unittest.TestCase):
    def test_phone_passkey_bluetooth_purpose_in_every_app_language(self):
        _, info = release.metadata()
        key = 'NSBluetoothAlwaysUsageDescription'
        for language in info['CFBundleLocalizations']:
            localized = subprocess.check_output(['plutil','-extract',key,'raw',ROOT/'Resources'/(language+'.lproj')/'InfoPlist.strings'],text=True)
            self.assertIn('Bluetooth',localized)
            self.assertIn('Bluetooth',info[key])

    def test_passkeys_require_exact_apple_grant_and_distribution_signer(self):
        team, bundle = 'TESTTEAM', 'test.browser'
        grants = {passkeys.APP_ID:'PREFIX.'+bundle, passkeys.TEAM_ID:team, passkeys.CAPABILITY:True}
        certificate = hashlib.sha1(b'test certificate').hexdigest().upper()
        profile = dict(Platform=['OSX'],TeamIdentifier=[team],ApplicationIdentifierPrefix=['PREFIX'],
                       ProvisionsAllDevices=True,DeveloperCertificates=[b'test certificate'],
                       Entitlements={**grants,'unrelated':True},ExpirationDate=datetime.datetime(2099,1,1))
        check = lambda p: passkeys.profile_entitlements(p,bundle,team,certificate)
        self.assertEqual(check(profile),grants)
        for override in [dict(Platform=['iOS']),dict(TeamIdentifier=['other']),dict(DeveloperCertificates=[]),
                         dict(ExpirationDate=datetime.datetime(2000,1,1)),dict(ProvisionsAllDevices=False),
                         *[dict(Entitlements={**grants,k:v}) for k,v in [
                             (passkeys.APP_ID,'PREFIX.*'),(passkeys.APP_ID,'PREFIX.other'),
                             (passkeys.CAPABILITY,False),(passkeys.CAPABILITY,1),(passkeys.TEAM_ID,'other'),
                             ('com.apple.security.get-task-allow',True)]]]:
            with self.subTest(override=override), self.assertRaises(ValueError):
                check({**profile,**override})

    def test_github_notes_keep_both_complete_translations(self):
        notes,_ = release.metadata()
        self.assertEqual(release.github_notes(dict(notes,showOnLaunch=False)),'')
        notes = dict(notes,showOnLaunch=True)
        english,french = release.github_notes(notes).split('<summary>Français</summary>')
        for lang,section in [('en',english),('fr',french)]:
            self.assertIn(notes['subtitle'][lang],section)
            for row in notes['highlights']:
                self.assertIn(row['title'][lang],section)
                self.assertIn(row['detail'][lang],section)

    @unittest.skipUnless((ROOT/'vendor/sparkle-2.10.1/bin/generate_appcast').exists(), 'requires the pinned Sparkle tools')
    def test_language_feeds_share_one_signed_archive(self):
        # Test-only bundle and signing seed: no network, production keys or Keychain.
        notes,info = release.metadata()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); app = root/'Notes.app'; contents = app/'Contents'
            (contents/'MacOS').mkdir(parents=True); assets = root/'assets'; assets.mkdir()
            subprocess.run(['swift','-e',
                'import Foundation; import CryptoKit; let k = Curve25519.Signing.PrivateKey(); '
                'try k.rawRepresentation.base64EncodedData().write(to:URL(fileURLWithPath:CommandLine.arguments[1])); '
                'try k.publicKey.rawRepresentation.base64EncodedData().write(to:URL(fileURLWithPath:CommandLine.arguments[2]))',
                root/'key',root/'public'],check=True)
            info.update(CFBundleIdentifier='local.arcreborn.test.release-notes',CFBundleExecutable='Notes',
                        SUPublicEDKey=(root/'public').read_text())
            (contents/'Info.plist').write_bytes(plistlib.dumps(info))
            shutil.copy('/usr/bin/true',contents/'MacOS/Notes')
            subprocess.run(['codesign','--force','--sign','-',app],check=True)
            archive = assets/'Notes.zip'
            subprocess.run(['ditto','-ck','--keepParent',app,archive],check=True)
            release.prepare_feeds(notes,archive,ROOT/'vendor/sparkle-2.10.1',['--ed-key-file',root/'key'])
            subprocess.run(['xcrun','swift',ROOT/'scripts/verify-release.swift',contents/'Info.plist',assets],check=True)
            legacy = ET.parse(assets/'appcast.xml').find('./channel/item')
            translations = {n.attrib['{http://www.w3.org/XML/1998/namespace}lang']:n.text for n in legacy.findall('description')}
            self.assertEqual(set(translations),set() if notes.get('showOnLaunch') is False else {'en','fr'})
            for lang in ('en','fr'):
                item = ET.parse(assets/f'appcast-{lang}.xml').find('./channel/item')
                self.assertEqual(item.find('enclosure').attrib,legacy.find('enclosure').attrib)
                if notes.get('showOnLaunch') is False: self.assertIsNone(item.find('description'))
            for lang in translations:
                item = ET.parse(assets/f'appcast-{lang}.xml').find('./channel/item')
                self.assertEqual(item.find('enclosure').attrib,legacy.find('enclosure').attrib)
                self.assertEqual(item.findtext('description'),translations[lang])
                self.assertIn(release.html.escape(notes['subtitle'][lang]),translations[lang])

    def test_bundle_and_changelog_versions_must_match(self):
        original = release.NATIVE
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root/'Resources').mkdir()
            notes = json.loads((original/'Resources/ReleaseNotes.json').read_text())
            info = plistlib.loads((original/'Resources/Info.plist').read_bytes())
            (root/'Resources/ReleaseNotes.json').write_text(json.dumps(notes))
            info['CFBundleVersion'] = str(notes['build']+1)
            (root/'Resources/Info.plist').write_bytes(plistlib.dumps(info))
            release.NATIVE = root
            try:
                with self.assertRaises(ValueError): release.metadata()
            finally: release.NATIVE = original

    def test_private_files_cannot_enter_public_tree(self):
        for name in ['server/config.txt','.env.production','native/vendor/engine.bin','certificate.p12','app.provisionprofile']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder); path = root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_text('private')
                with self.assertRaises(ValueError): public.audit(root)

    def test_embedded_database_credentials_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'config.swift').write_text('postgres'+'ql://user:'+ 'credential'+'@example.invalid/db')
            with self.assertRaises(ValueError): public.audit(root)

    def test_symlink_cannot_escape_export(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root/'outside').symlink_to('/tmp')
            with self.assertRaises(ValueError): public.audit(root)

    def test_only_verified_engine_deltas_can_exceed_the_export_size_limit(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            delta = root/'native/Engine/deltas/test.bsdiff'
            delta.parent.mkdir(parents=True)
            data = b'BSDIFF40' + bytes(5*1024*1024)
            delta.write_bytes(data)
            with self.assertRaises(ValueError): public.audit(root)
            lock = {'archive': {'delta': {'file':'deltas/test.bsdiff', 'sha256':hashlib.sha256(data).hexdigest()}}}
            (delta.parent.parent/'engine.lock.json').write_text(json.dumps(lock))
            public.audit(root)
            with delta.open('ab') as stream: stream.write(b'x')
            with self.assertRaises(ValueError): public.audit(root)

    def test_modified_patch_invalidates_binary_pin(self):
        original = engine.ENGINE
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            first = engine.PIN['patches'][0]['file']; path = root/first
            path.parent.mkdir(parents=True); path.write_text('changed patch')
            engine.ENGINE = root
            try:
                with self.assertRaises(SystemExit): engine.verify_patches()
            finally: engine.ENGINE = original

    def test_current_metadata_and_patch_set_valid(self):
        release.metadata(); engine.verify_patches()
        base = engine.load_pin(False)
        candidate = engine.load_pin(True)
        if any(p['file'] == 'patches/appkit-passkey-window.patch' for p in base['patches']):
            self.assertEqual(candidate,base)
        else:
            self.assertEqual(candidate['patches'][:-1],base['patches'])
            self.assertEqual(candidate['patches'][-1]['file'],'patches/appkit-passkey-window.patch')
        for patch in candidate['patches']:
            self.assertEqual(engine.sha(engine.ENGINE/patch['file']),patch['sha256'])
        self.assertRegex(candidate['archive']['sha256'],r'^[a-f0-9]{64}$')

if __name__ == '__main__': unittest.main()
