#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks
xcrun swiftc -O Sources/{ThemeState,NativeState,SplitState,SpaceContent,FolderTree,FavoritesState,SpaceNavigation,ActionButton,SpaceIconPicker,SpaceDock}.swift Tests/SpaceDockTests.swift -o build/checks/space-dock-tests
build/checks/space-dock-tests
xcrun swiftc -O Sources/{SidebarHoverTip,Localization}.swift Tests/SidebarTipTests.swift -o build/checks/sidebar-tip-tests
build/checks/sidebar-tip-tests
