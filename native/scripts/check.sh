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
xcrun swiftc Sources/{ThemeState,NativeState,SplitState,SpaceContent,FolderTree,FavoritesState,TabSoundButton,FavoritesGrid,ActionButton,FolderDisclosureIcon,SidebarTabCell}.swift Tests/SidebarTabHoverTests.swift -o build/checks/sidebar-tab-hover-tests
build/checks/sidebar-tab-hover-tests
xcrun swiftc Sources/SidebarRowMotion.swift Tests/SidebarRowMotionTests.swift -o build/checks/sidebar-row-motion-tests
build/checks/sidebar-row-motion-tests
xcrun swiftc Sources/SidebarSplitDropPreview.swift Tests/SidebarSplitDropPreviewTests.swift -o build/checks/sidebar-split-drop-preview-tests
build/checks/sidebar-split-drop-preview-tests
xcrun swiftc -O Sources/{ThemeState,NativeState,SplitState,SpaceContent,FolderTree,FavoritesState,SpaceNavigation}.swift Tests/SplitStateTests.swift -o build/checks/split-state-tests
build/checks/split-state-tests
xcrun swiftc -O Sources/{ThemeState,NativeState,SplitState,SpaceContent,FolderTree,FavoritesState,SpaceNavigation,BrowserHandoff}.swift Tests/BrowserHandoffTests.swift -o build/checks/handoff-tests
build/checks/handoff-tests Resources/Info.plist
xcrun swiftc Sources/SidebarScrollView.swift Tests/SidebarScrollerTests.swift -o build/checks/sidebar-scroller-tests
build/checks/sidebar-scroller-tests
xcrun swiftc Sources/SidebarTabReturn.swift Tests/SidebarTabReturnTests.swift -o build/checks/sidebar-tab-return-tests
build/checks/sidebar-tab-return-tests
xcrun swiftc -O Sources/{LibraryStore,Localization,ActionButton,DownloadCard,RecentMediaPeek,FooterControlArtwork}.swift Tests/DownloadShelfTests.swift -o build/checks/download-shelf-tests
build/checks/download-shelf-tests
xcrun swiftc -O Sources/LibraryMediaIcon.swift Tests/LibraryMediaIconTests.swift -o build/checks/library-media-icon-tests
build/checks/library-media-icon-tests
xcrun swiftc -O Sources/{LibraryMediaIcon,LibraryDownloadIcon}.swift Tests/LibraryDownloadIconTests.swift -o build/checks/library-download-icon-tests
build/checks/library-download-icon-tests
xcrun swiftc -O Sources/{LibraryMediaIcon,LibrarySpacesIcon}.swift Tests/LibrarySpacesIconTests.swift -o build/checks/library-spaces-icon-tests
build/checks/library-spaces-icon-tests
xcrun swiftc -O Sources/{LibraryMediaIcon,LibraryArchiveIcon}.swift Tests/LibraryArchiveIconTests.swift -o build/checks/library-archive-icon-tests
build/checks/library-archive-icon-tests
xcrun swiftc -O Sources/LibraryStore.swift Tests/LibraryTests.swift -o build/checks/library-tests
build/checks/library-tests
xcrun swiftc Sources/{LibraryView,LibraryStore,LibraryMediaIcon,LibraryDownloadIcon,LibrarySpacesIcon,LibraryArchiveIcon,ThemeState,ThemeRendering,NativeState,SplitState,SpaceContent,FolderTree,FavoritesState,SpaceNavigation,DeletionUndo,Localization,SpaceIconPicker,DownloadCard,ActionButton}.swift Tests/LibraryViewTests.swift -o build/checks/library-view-tests
build/checks/library-view-tests
xcrun clang++ -fobjc-arc -framework Foundation Tests/TestKeychainPolicyTests.mm -o build/checks/test-keychain-policy
build/checks/test-keychain-policy
/usr/bin/python3 scripts/release.py check
/usr/bin/python3 Tests/release-tools-test.py
xcrun swiftc Sources/{SidebarUpdateSession,SidebarUpdateCard,SidebarListChrome,LibraryStore,Localization,ActionButton,DownloadCard,RecentMediaPeek}.swift Tests/SidebarUpdateTests.swift -o build/checks/sidebar-update-tests
build/checks/sidebar-update-tests
bash Tests/update-preferences.sh
