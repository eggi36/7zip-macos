#!/bin/sh
# make-mac-icons.sh -- regenerate the macOS-style app and document icons (native-look).
#
# The shipped icons are drawn by Mac/scripts/make-mac-icons.swift with Core Graphics (no SF
# Symbols, no third-party art): the app icon in Assets.xcassets/AppIcon.appiconset, the 28
# document icons as Mac/Resources/Icons/doc-<name>.icns and the doc-<name>.imageset PNGs the
# Options > System page shows. The Windows .ico frames (Mac/Resources/Icons/fm-*.ico) stay: the
# Classic look's file list draws them.
#
#   Mac/scripts/make-mac-icons.sh       writes the assets and Mac/build/screenshots/icons-mac-sheet.png
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app}
swift "$REPO/Mac/scripts/make-mac-icons.swift" "$REPO"
