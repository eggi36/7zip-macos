#!/bin/sh
# make-mac-icons.sh -- regenerate the macOS-style app and document icons (native-look).
#
# The shipped icons are drawn by Mac/scripts/make-mac-icons.swift with Core Graphics (no SF
# Symbols, no third-party art): the app icon as the Icon Composer icon Resources/AppIcon.icon
# (light, dark and tinted; Xcode makes the AppIcon.icns for macOS 14 and 15) and the 28
# document icons as Mac/Resources/Icons/doc-<name>.icns (the Finder's document icons and the
# Settings > System list). They are the only icon assets; the Windows-derived ones (and the
# make-icons.sh pipeline that converted 7-Zip's .ico files) are gone.
#
#   Mac/scripts/make-mac-icons.sh       writes the assets and Mac/build/screenshots/icons-mac-sheet.png
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app}
swift "$REPO/Mac/scripts/make-mac-icons.swift" "$REPO"
