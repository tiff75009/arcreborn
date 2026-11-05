#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$NATIVE_ROOT/build/checks"
cd "$NATIVE_ROOT"
xcrun swiftc -O Sources/ThemeState.swift Sources/NativeState.swift Sources/SplitState.swift Sources/SpaceContent.swift Sources/FolderTree.swift Sources/FavoritesState.swift Sources/SpaceNavigation.swift Sources/DeletionUndo.swift Tests/StateTests.swift -o build/checks/state-tests
build/checks/state-tests
xcrun swiftc -O Sources/{ThemeState,NativeState,SplitState,SpaceContent,FolderTree,FavoritesState,TabSoundButton,FavoritesGrid,FavoriteUnread,FaviconPixels,FaviconCache}.swift Tests/FaviconCacheTests.swift -o build/checks/favicon-cache-tests
build/checks/favicon-cache-tests
xcrun swiftc -O Sources/TabSoundButton.swift Tests/TabSoundButtonTests.swift -o build/checks/tab-sound-tests
build/checks/tab-sound-tests
xcrun clang++ -fobjc-arc -framework Foundation Tests/TestKeychainPolicyTests.mm -o build/checks/test-keychain-policy
build/checks/test-keychain-policy
/usr/bin/python3 scripts/release.py check
/usr/bin/python3 Tests/release-tools-test.py
bash Tests/update-preferences.sh
