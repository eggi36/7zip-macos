# 7-Zip for macOS (unofficial port)

A native macOS version of the **7-Zip File Manager**: the real 7-Zip 26.06 engine with an AppKit
interface that looks and behaves like a Mac app and keeps everything the Windows app has — the
same two panels, menus, dialogs, keyboard map, settings and 93 languages — plus Finder
integration, Quick Look and disc images.

> **Unofficial.** This project is not affiliated with or endorsed by Igor Pavlov or the 7-Zip
> project. 7-Zip is Igor Pavlov's work ([7-zip.org](https://www.7-zip.org)). This repository is a
> fork of [yrambler2001/7zip-macos](https://github.com/yrambler2001/7zip-macos), itself a fork of
> [ip7z/7zip](https://github.com/ip7z/7zip) that adds the macOS app. Please report problems with
> the Mac app here, not to 7-Zip.

Current version: **7-Zip 26.06 for macOS 1.3.0**.

<p align="center">
  <img src="docs/images/window-main-light.avif" width="870" alt="The main window, light theme"><br>
  <img src="docs/images/window-main-dark.avif" width="870" alt="The main window, dark theme">
</p>

## Features

- **Browse and edit archives like folders** — 7z, ZIP, RAR, TAR, GZip, BZip2, XZ, Zstandard, CAB,
  ISO, DMG, WIM, MSI, RPM, DEB, APFS, VHD and the rest of 7-Zip's formats, including archives
  inside archives. Double-click or Enter opens any file 7-Zip can read inside the file manager —
  an `.epub`, `.docx` or `.jar` too — and hands everything else to its default application.
- **Disc images** — CUE/BIN (a `.bin` also on its own), CCD/IMG (CloneCD), MDS/MDF (Alcohol 120%),
  NRG (Nero), CDI (DiscJuggler), GDI (Dreamcast), CHD (MAME), CSO / ZSO / CISO, ISZ (UltraISO), ECM
  and zisofs, as the Iso7z plugin adds them to 7-Zip on Windows: data tracks open as ISO, audio
  tracks come out as WAV, multi-session discs show each session. **GameCube** (`.gcm`, GameCube
  `.iso`) and **Xbox / Xbox 360** images (XISO and whole disc images) open with the game's own
  file system.
- **Two panels**, four view modes, sortable columns with the sort direction shown, flat view,
  folder history, favorites and 7-Zip's keyboard map.
- **A Mac look**: the toolbar in the title bar with SF Symbols, Back / Forward / Up next to the
  folder's name, a Finder-style list, a path bar, tabs, sheets for dialogs, Undo for Move to
  Trash. The toolbar is customizable (right-click ▸ *Customize Toolbar…*): more commands and a
  Finder-style view switcher can be added.
- **Quick Look in the file manager** — Space previews the selected files, also files inside an
  archive (extracted to a temporary folder for the preview), and the preview follows the
  selection.
- **Extract** with every path and overwrite mode; **Add to archive** with the full set of
  compression options, AES-256 encryption (including file names), multi-volume and
  self-extracting archives.
- **Exclude Mac resource forks** — a checkbox in Add to archive (off by default) that leaves
  `._*` AppleDouble files, `.DS_Store` and `__MACOSX` folders out of the archive, so archives
  shared with Windows and Linux users contain only your files.
- **Test**, **checksums** (CRC32, CRC64, SHA-1, SHA-256, SHA-512, BLAKE2sp, XXH64 and more),
  **Benchmark**, **Split**, **Combine**, **Link**, Properties and comments.
- **Finder integration** — a 7-Zip submenu on Finder's right-click menu, Quick Actions, Services,
  and document icons for 53 archive and disc-image types.
- **Quick Look preview in Finder** — select an archive (or a one-file disc image) in Finder or
  press Space to see its summary and contents as 7-Zip lists them, without opening the app.
- **93 languages** — the official 7-Zip translations, switchable while the app runs.
- **Light and Dark** — the app follows the system by default (Options ▸ Settings ▸ Theme fixes it
  to Light or Dark), and its icon has a Dark-mode look too.
- **Native and offline**: Swift and AppKit on top of the unchanged C/C++ engine. No emulation, no
  third-party code, no network access — the app does not check for updates.
- The About box shows the exact build (number, time and commit), so every build can be told apart.

**Add to archive**

<p align="center"><img src="docs/images/window-add-to-archive.avif" width="724" alt="Add to archive"></p>

**Extract**

<p align="center"><img src="docs/images/window-extract.avif" width="612" alt="Extract"></p>

**Properties of an item inside an archive**

<p align="center"><img src="docs/images/window-properties.avif" width="863" alt="Properties of an item inside an archive"></p>

**Options ▸ Settings** (7-Zip's settings, with the theme, Quick Look and Reset All Settings below them)

<p align="center"><img src="docs/images/window-options-settings.avif" width="590" alt="Options ▸ Settings"></p>

**Finder's right-click menu with the 7-Zip submenu**

<p align="center"><img src="docs/images/window-finder-context-menu.avif" width="1125" alt="Finder's right-click menu with the 7-Zip submenu"></p>

## Install

Requires **macOS 14 (Sonoma) or newer**, on Apple Silicon or Intel (the release is a universal app).

### Disk image

Download `7-Zip-26.06-macOS-1.3.0.dmg` (the version in the name changes with each release) from
[Releases](https://github.com/eggi36/7zip-macos/releases), open it and drag **7-Zip** onto
**Applications**. The app is universal: one download for Apple Silicon and Intel Macs.

### From source

See [docs/building.md](docs/building.md). In short, with Xcode 26 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
Mac/scripts/build.sh --release      # or Mac/scripts/run.sh to build and launch a Debug build
Mac/scripts/package.sh              # the universal Release app as a disk image in Mac/build
```

## First launch: Gatekeeper

The app is **ad-hoc signed, not notarized** — there is no paid Apple Developer ID behind this
project. A copy installed from the disk image is therefore blocked the first time ("Apple could
not verify "7-Zip" is free of malware"). To allow it:

1. Open 7-Zip once and dismiss the warning.
2. Open **System Settings ▸ Privacy & Security**, scroll to **Security**, and click
   **Open Anyway** next to the message about 7-Zip.
3. Confirm with Touch ID or your password. Later launches open normally.

On macOS 15 and later the old right-click ▸ Open shortcut no longer bypasses this; use the steps
above. If you prefer the terminal, removing the quarantine attribute does the same:

```sh
xattr -dr com.apple.quarantine /Applications/7-Zip.app
```

Builds you make yourself are not quarantined and open directly.

## Finder integration

macOS does not switch extensions on by itself. After the first launch, either tick
**Options ▸ 7-Zip ▸ Integrate 7-Zip to shell context menu**, or open
**System Settings ▸ General ▸ Login Items & Extensions** and:

- under **File Providers** (Finder Sync), switch on **7-Zip** — the 7-Zip submenu on Finder's
  right-click menu and a toolbar button;
- under **Finder**, switch on **Extract with 7-Zip** and **Compress with 7-Zip** — the Quick
  Actions.

The five **7-Zip: …** Services need nothing; they are in every app's Services menu. Options ▸ 7-Zip
chooses which of the eleven menu entries Finder shows, as on Windows. If the menu never appears,
`pluginkit -m -p com.apple.FinderSync -v` shows whether the extension is enabled (`+`) and which
copy of 7-Zip it belongs to — with several copies of the app on the Mac (a build folder, an old
disk image), Finder may use the extension of another copy.

The **Quick Look preview** is on from the first launch: select an archive in Finder and look at the
preview pane, or press Space. Options ▸ Settings ▸ **Quick Look preview for archives** switches it
off (it is the same switch as System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look).
If Finder still shows the plain icon right after installing, run `qlmanage -r` or log out and back in.

The app itself is not sandboxed (it is a file manager), so macOS asks once for access to Desktop,
Documents, Downloads, removable and network volumes as you open them. The Finder extensions are
sandboxed and only see the files you selected.

## File associations

macOS keeps Apple's own apps as the default for many archive types (Archive Utility for `.zip`,
`.gz`, `.tar`, `.xz`, `.bz2`; DiskImageMounter for `.iso` and `.dmg`), so installing 7-Zip does not
change what a double-click opens in Finder. To open archives with 7-Zip — and to see 7-Zip's
archive icons in Finder — choose the types in **7-Zip ▸ Settings ▸ System**: click a type in the
column with your user name to associate it (or `+` to associate every type). macOS asks you to
confirm each change of default application. A single type can also be switched in Finder with
**Get Info ▸ Open with ▸ 7-Zip ▸ Change All…**.

## Updates

The app does not check for updates and makes no network request. New versions are on the
[releases page](https://github.com/eggi36/7zip-macos/releases).

## Differences from 7-Zip on Windows

The Mac app aims at parity with the Windows File Manager; the differences — Finder instead of
Explorer, the Trash, Command shortcuts, the quarantine attribute instead of Zone.Identifier, the
macOS additions — are summarised in [docs/parity.md](docs/parity.md). Known limitations:
right-to-left languages are not mirrored, and about a quarter of the upstream translations are
incomplete.

## Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md), and
[SECURITY.md](SECURITY.md) for vulnerabilities. Developer documentation:

- [docs/building.md](docs/building.md) — requirements, scripts, signing
- [docs/architecture.md](docs/architecture.md) — engine, bridge, app, extensions
- [docs/testing.md](docs/testing.md) — unit, app-hosted and UI tests
- [docs/upstream.md](docs/upstream.md) — following upstream 7-Zip and the patches to it
- [docs/releasing.md](docs/releasing.md) — CI, cutting a release, signing secrets

Problems in the archive engine itself (a format, compression, the command-line `7zz`) belong
upstream at [7-zip.org](https://www.7-zip.org).

## How this was built

Most of the port was written by AI agents (Claude Code) directed by the maintainers, one scoped
agent per feature, each checked against the Windows app. The plans, specifications and per-feature
reports are kept in [`ai/`](ai/README.md); commits written by an agent carry `Co-Authored-By` and
`Claude-Session` trailers.

## License

7-Zip is Copyright (C) 1999-2026 Igor Pavlov; the macOS port is Copyright (C) 2026 Yurii Synyshyn (yrambler2001).
Both are under the **GNU LGPL 2.1 or later**, with parts under the BSD 3-clause and 2-clause
licences and the RAR code under the unRAR license restriction — see [LICENSE](LICENSE),
[DOC/License.txt](DOC/License.txt) and [NOTICE](NOTICE) (bundled assets, trademarks, upstream
patches). Upstream's own readme is [DOC/readme.txt](DOC/readme.txt).
