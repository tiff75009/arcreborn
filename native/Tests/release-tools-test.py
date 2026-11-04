#!/usr/bin/env python3
"""Boundary tests: reject private files, mismatched versions and modified patches."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

def module(name):
    spec = importlib.util.spec_from_file_location(name,ROOT/'scripts'/(name+'.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value

release = module('release'); public = module('public-source'); engine = module('engine')

class ReleaseTests(unittest.TestCase):
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
        for name in ['server/config.txt','.env.production','native/vendor/engine.bin','certificate.p12']:
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

if __name__ == '__main__': unittest.main()
