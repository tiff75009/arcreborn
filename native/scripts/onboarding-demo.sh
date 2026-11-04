#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/demo/Arc Reborn Onboarding.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sources=(Sources/{ActionButton,WelcomeIntro,WelcomeChapterControls,WelcomeWindow,BrowserImport,BrowserImportProfiles,ArcAccount,ArcSync,ArcSyncSettingsView,ArcSyncState,BrowserWindowState,NativeState,ThemeState,SplitState,FavoritesState,SpaceContent,SpaceNavigation,DeletionUndo,FolderTree}.swift)
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 "${sources[@]}" Demo/OnboardingDemo.swift -o "$app/Contents/MacOS/OnboardingDemo"
scripts/welcome-assets.sh "$app/Contents/Resources/Welcome"
cp Resources/ArcReborn.icns "$app/Contents/Resources/"
cp Demo/Info.plist "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
open "$app"
