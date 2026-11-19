# Changelog

All notable changes to 7-Zip for macOS are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the port uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) for its own version; the engine version
is upstream 7-Zip's (for example *7-Zip 26.03 for macOS 1.0.0*).

## [1.3.2] — 2026-11-19

7-Zip 26.06 for macOS 1.3.2: the Finder menu on network volumes.

### Fixed

- The 7-Zip items in the Finder context menu and toolbar menu now also appear for files on network
  volumes (SMB, AFP, NFS). Finder only asks the extension about a network volume when the volume
  itself is registered, so every mounted volume is now registered, and the list follows volumes
  being mounted, unmounted and renamed.

## [1.3.1] — 2026-11-14

7-Zip 26.06 for macOS 1.3.1: fixes from a full review of the port.

### Changed

- View (F3) and Edit (F4) with an external viewer or editor set in Options ▸ Editor start that
  program directly, never through a shell: nothing in the setting is run as a command.
- The release workflow no longer updates a Homebrew tap.

### Fixed

- Disc images:
  - a CUE, GDI or CCD sheet can only name track files in its own folder; an absolute path, a
    drive letter or `..` is reduced to the file name;
  - an Xbox (XDVDFS) image whose directory tables point back at each other is refused instead of
    being walked without end, and its tables are capped in size;
  - an ISZ image with an impossible stored size is refused;
  - a CHD file whose metadata entry is skipped no longer stops the walk of the remaining entries;
  - opening a large GCM or Xbox image reports progress and can be cancelled.
- Link: a relative target is resolved against the link's folder, and an existing file or folder
  is only replaced when it is a link, an empty file or an empty folder; otherwise the error says
  it exists.
- Overwrite: *Auto Rename* leaves the new name to the engine's own rule ("name (2).ext") again
  instead of passing on a name the dialog worked out itself.
- Add to Archive and Extract: a path starting with `~` means the home folder.
- Extract: a path chosen from the history and then edited is used as edited, and the entry it
  came from stays in the history.
- Add to Archive: a memory-usage limit given in percent of the RAM no longer overflows.
- Quick Look of a file inside an archive: the temporary copies are removed when the panel closes
  or changes folder, and a file opened from an archive is written under a valid file name.

## [1.3.0] — 2026-11-14

7-Zip 26.06 for macOS 1.3.0: the engine updated to
[7-Zip 26.06](https://github.com/ip7z/7zip/releases/tag/26.06) (2026-11-06), which includes 26.05
(2026-10-21).

### Added

- **A Mac look replaces the Windows look.** The same window, panels, menus, keys and commands,
  drawn with macOS's own chrome: the toolbar in the title bar with SF Symbols and Back /
  Forward / Up next to the title, the folder's
  name as the window title with a proxy icon, a Finder-style list (system font,
  24 pt striped rows, the system selection and column header, overlay scroll bars, the system's
  file icons), a rounded address field and a quiet status bar. The theme follows the system's
  Light / Dark until one is chosen (Options ▸ Settings ▸ Theme); this applies to everyone who kept the
  Light default of 1.1.2–1.2.x, while an explicit choice of Light is kept. The pixel-exact copy of the Windows window ("Classic") and
  its switch in Options ▸ macOS are gone.
  - The dialogs look like Mac dialogs: the system font at its regular size, AppKit's own pop-up
    menus, combo boxes and text fields, groups as titled rounded boxes, a macOS progress bar,
    Cancel left of OK and Help as the round "?" button at the left. Every control stays where
    the Windows layout puts it, so nothing moves out of reach.
  - Dialogs about a window's content open as sheets of that window, as the HIG asks: Add to
    Archive, Extract, Copy, Move, Rename, Create Folder, Split, Link, the password and overwrite
    questions and every message box -- while a progress window, the benchmark or a 7zG command
    owns them, or another dialog is open, they stay windows of their own, in front. Each still answers the code that asked, so nothing
    else changes. The one-field dialog (Rename, Create Folder, Comment, Select) shows its caption
    as a bold heading, since a sheet has no title bar.
  - The menus use the Mac's names and shortcuts: *Settings…* (Cmd+,) and *About* in the 7-Zip
    menu; *New Window* Cmd+N, *New Folder* Shift+Cmd+N, *New File*
    Option+Cmd+N, *Open* Cmd+O, *Move to Trash* with *Delete Immediately…* under Option, *Get
    Info* Cmd+I, *Close Window*; Cut, Copy and Paste first in Edit; a *Sort By* submenu with
    Finder's Control+Option+Cmd+1-5, *Show Toolbar* and *Customize Toolbar…* in View; Finder's
    **Go** menu with Back, Forward, *Enclosing Folder*, Open Root Folder and Folders History;
    *7-Zip Help* with Cmd+?. Comment moves to Option+Cmd+K so Cmd+Z is left for Undo. 7-Zip's
    Windows keys (F1, F7, Alt+Enter, Cmd+F3 ...) keep working. The new names exist in English and
    German; other languages keep their translation of the Windows name.
  - *Edit ▸ Undo Move to Trash* (Cmd+Z) puts trashed files and folders back where they were, and
    *Redo* (Shift+Cmd+Z) trashes them again, as in the Finder.
  - Windows can be tabs: *File ▸ New Tab* (Cmd+T), the tab bar's **+** and the Window menu's tab
    commands (*Merge All Windows*, *Move Tab to New Window* ...); a new tab starts from the saved
    settings like a new window. System Settings' "Prefer tabs" is followed.
  - A Finder path bar under each panel's list (*View ▸ Show / Hide Path Bar*, Option+Cmd+P): the
    folder's chain from its volume down with icons, archive folders included; a click opens that
    folder with the one you came from selected. The editable address field stays above.
  - Form labels are right-aligned against the control they name ("Archive format:", "Update
    mode:" ...), in every dialog and settings pane; labels above their field and label/value
    pairs keep their place.
  - Options is a Mac Settings window: a toolbar of panes with symbols, the pane's name as the
    window title, the window fitting each pane's height, and every change taking effect at once
    -- no OK, Cancel or Apply (a text field commits when you leave it; an invalid value keeps the
    window on its pane with the message). Help is the "?" at the bottom right.
  - Messages and questions are Mac alerts laid out like NSAlert: no title bar, the app icon at the
    top (a caution sign badged with it for errors and warnings), the first line as the bold
    message and the rest as the informative text, equal-width buttons -- side by side with the
    default rightmost, or stacked with the default on top when there are three -- centred over
    their window. The answers, keys and Esc behaviour are unchanged.
  - View ▸ Large Icons shows Finder's 64 pt icons with names on up to two lines and Finder's
    selection; Small Icons and List get the Mac row height. The address bar's history list opens
    as a macOS menu. About 7-Zip shows the app icon with the version and credits centred.
  - Space opens Quick Look for the selected files and folders, as in Finder, and an open
    preview follows the selection -- the arrow keys move through the list while it is open -- (F3 still calculates a folder's size; items inside an archive
    are not previewed).
  - The Quick Look preview of an archive in Finder matches: its list has the system font, striped rows, the native header and selection and the system's file
    icons.
- **Disc images, as the Iso7z plugin adds them to 7-Zip on Windows**: CUE/BIN, CCD/IMG
  (CloneCD), MDS/MDF (Alcohol 120%), NRG (Nero), CDI (DiscJuggler), GDI (Dreamcast), CHD v3 / v4
  (MAME), CSO / ZSO and CISO (compressed ISO, PSP and Wii), ISZ (UltraISO), ECM and zisofs. A disc
  opens as its tracks -- a data track as *TrackNN.iso*, which opens in turn as ISO 9660 / UDF, an
  audio track as *TrackNN.wav* -- and a compressed image straight into the files it holds. A
  multi-session disc also shows *SessionN.iso*, the disc up to the end of each session, so every
  session's file system opens as it was burnt. A CD-ROM XA disc (Video CD, PlayStation) also
  shows a *TrackNN* folder with its files decoded; a Form 2 file (a Video CD's .DAT, a .STR
  movie) comes out as Windows shows it, a RIFF CDXA file of its raw sectors that players open. The
  sector data is read in place (the 2048 bytes of a raw Mode 1 / Mode 2 Form 1 sector; ECM
  rebuilds each sector's EDC / ECC), nothing is unpacked to disk first. An ISZ split into .i01,
  .i02 ... segments opens from its first file. The descriptor extensions can be associated with
  7-Zip in Settings > System. Quick Look previews the one-file images (NRG, CDI, CHD, CSO, CISO,
  ZSO, ISZ, ECM); CUE, CCD, MDS and GDI keep their data in files next to them, which the
  sandboxed preview cannot read. Not supported: encrypted MDS 2.x and ISZ, CHD v5 and diff CHDs.
- **New app and document icons in the macOS style.** Archives in Finder show macOS's own
  archive icon -- the grey sheet with the zipper -- with their type written under the zipper the
  way macOS labels a ZIP file (7Z, RAR, TAR, ISO, ...). The app icon is a light tile in the style
  of Apple's utilities with the same grey zipper, its pull in 7-Zip blue, and no lettering (as the
  HIG asks of app icons). `Mac/scripts/make-mac-icons.sh` regenerates them from the Mac it runs on.
  - A click anywhere on a row selects it, as in Finder.
  - A fresh install shows the toolbar's symbols without labels, as Mac apps do (the toolbar's
    right-click menu adds them).
  - The toolbar is customizable (right-click ▸ *Customize Toolbar…*), with Up, Refresh, Create
    Folder, Rename, Split, Combine, Flat View, 2 Panels, Folders History and Benchmark to add; the
    arrangement is saved. Up One Level can go next to Back / Forward. A Finder-style view switcher (Large Icons, Small Icons, List,
    Details) can be added too; it shows and sets the focused panel's view. The View ▸ Toolbars submenu is
    gone: Customize Toolbar… adds and removes buttons, Large Buttons has no Mac counterpart, and
    the toolbar's right-click menu (Icon and Text / Icon Only) replaces Show Buttons Text.

### Changed

- **The app icon has a Dark-mode look** (and the tinted and clear looks of macOS 26): the same
  zipper on a dark tile when the system is dark. macOS 14 and 15 show the light icon as before.
- **The update check is removed**, until further notice: no Check for Updates… menu item, no
  "Check for updates at startup" option, and the app makes no network request at all.
- Options has no macOS tab any more: the theme, "Quick Look preview for archives" and Reset All
  Settings… are on the Settings page, under its Windows controls; "Show grid lines" is there once.
- The About box shows the build: its number, when it was built and from which commit
  ("Build 402 (2026-11-13 21:50:07 1faab4b0c2)", "+" for uncommitted changes), so every compile
  can be told apart.
- Opening a file in the file manager (double-click, Enter) opens it inside whenever 7-Zip can read
  it -- an .epub, .docx or .jar too, which 7-Zip on Windows hands to their applications -- and only
  otherwise with the system's default application. Open Outside (Shift-Enter) still starts any file.
- View ▸ Show Buttons Text is gone; the toolbar's right-click menu switches the labels.
- **Quick Look inside archives**: Space on files inside an archive previews them, as Finder does;
  they are extracted to a temporary folder, which is removed when you leave the archive or quit.
- An open Quick Look panel follows the selection in every view: in Large Icons, Small Icons and
  List it kept showing the first file, and after switching the view, the panel or the window
  (Mission Control, Cmd-Tab) it could stay on the previous one.
- **A raw .bin opens without its .cue**: its data track as Track01.iso (the cue sheet stays the way
  to see the separate tracks).
- **GameCube disc images** (.gcm, and GameCube .iso files) open: the files of the disc under
  files/, its system data (boot.bin, bi2.bin, apploader.img, main.dol, fst.bin) under sys/, as
  Dolphin extracts a disc. Wii discs are encrypted and are not opened.
- **Xbox and Xbox 360 disc images** open: an XISO (.iso / .xiso, the game partition alone) and a
  whole disc image (Redump), whose game partition follows a DVD-video partition -- 7-Zip opens
  the game's file system (XDVDFS), not the video partition.
- The address field has no Up button of its own any more: Up One Level is in the toolbar next to
  Back / Forward (Backspace and Go ▸ Enclosing Folder still work).
- The sorted column's header shows the sort direction, as in Finder (7-Zip on Windows shows none).
- The leftovers of the Windows look are gone: the old 7-Zip logo, the Windows toolbar bitmaps, the
  `.ico` document icons and the scripts that converted them. The address bar's history list now
  shows the system icon for an archive and highlights in the accent colour, and the selection
  rectangle dragged over the file list is drawn as in Finder.
- Updated the engine to 7-Zip 26.06. Upstream's summary: improved support for split files created
  by the Linux `split` utility (`file.aa`, `file.ab`, …), improved unpacking of Z archives and
  Mach-O files, and "some bugs and vulnerabilities were fixed" — among others the CAB, MSLZ, MUB,
  Split, PE, UDF and Z handlers and the Quantum, Shrink and Z decoders were reworked or hardened
  against malformed archives. No extension, menu item or dialog control was added or removed.
- **Combine files** recognises the parts the Linux/macOS `split` tool makes (`file.aa`,
  `file.ab`, …, including the longer names GNU split uses after `yz`, and `split -d`'s
  `file.00`, `file.01`, …), as 7-Zip File Manager 26.06 does. The dialog now names the file it
  will create above the list of parts. A first part named `….000` is accepted too; a name ending in
  digits without a dot before them (`data001`) is no longer taken for a split file, and only one
  trailing dot is removed from the proposed name.
- **Split file** refuses more than 536 870 911 parts, as 7-Zip 26.06 does.
- The bundled assets come from the official 7-Zip 26.06 Windows release (`7z2606-x64.exe`): new
  `7z.sfx` and `7zCon.sfx` self-extracting modules and the 26.06 help pages.

### Changed in upstream sources

- Upstream moved `GetNumberOfVolumes` from `SplitUtils.cpp` into `PanelSplitFile.cpp`; the
  `SplitUtils.cpp` patch now only guards the Win32 combo-box code. All other guarded macOS patches
  carry over unchanged ([Mac/docs/upstream-patches.md](Mac/docs/upstream-patches.md)).

## [1.2.1] — 2026-10-08

7-Zip 26.04 for macOS 1.2.1: Quick Look preview fix.

### Fixed

- **Quick Look preview:** the summary at the top showed as an empty grey block in Finder's Quick
  Look window (the list below was fine). A one-point divider line drew its colour over the area
  macOS asked it to repaint, which in Quick Look was the whole summary.
- After replacing 7-Zip in place and launching it right away, its Finder menu, Quick Actions and
  Quick Look preview could stay unregistered until the next launch; 7-Zip now checks again a few
  seconds after launch.

### Changed

- **Quick Look preview:** the file name, icon and *Open in 7-Zip* button are gone — Quick Look's
  own title bar already shows the name and *Open with 7-Zip*. The summary is one line on the
  list's background ("7z · LZMA2:12 · Solid · Files: 2 · 209 829 → 172 759 bytes (82%)"), with
  any note (encrypted, too many items, part of a multi-volume set) on the line below.

## [1.2.0] — 2026-10-08

7-Zip 26.04 for macOS 1.2.0: Quick Look preview for archives.

### Added

- **Quick Look preview for archives.** Selecting an archive in Finder (the preview pane, or the
  space bar) shows its type, method, file and folder counts, sizes and compression ratio, and its
  contents as a tree with 7-Zip's Name, Size, Packed Size and Modified columns, icons and font,
  folders first. **Open in 7-Zip** opens it in the app. Every archive type 7-Zip registers is
  covered, compressed tarballs (`.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, …) included.
  The preview never asks for a password (an archive with encrypted file names says so), stops
  after about 2 seconds or 10 000 entries ("…and N more — open in 7-Zip"), and never writes
  anything. Options ▸ macOS ▸ **Quick Look preview for archives** turns it off and on; it is on
  by default and Reset All Settings turns it back on. The document icons Finder shows are
  unchanged.

### Fixed

- After an update that replaces 7-Zip in place (`brew upgrade`, dragging a new copy over the old
  one), the Finder menu, the two Quick Actions and the Quick Look preview could disappear until
  they were switched on again. 7-Zip now registers its missing extensions at launch. It never
  switches one on that you turned off.

## [1.1.3] — 2026-10-07

7-Zip 26.04 for macOS 1.1.3: security hardening of the Finder integration.

### Security

- Commands that the Finder extension and the Quick Actions hand to 7-Zip are now authenticated:
  each carries a secret that only 7-Zip and its own extensions can read, created on first launch
  and renewed by Options ▸ macOS ▸ Reset All Settings. Other applications and web pages can no
  longer start 7-Zip commands through the `sevenzip:` / `x-7zip:` link schemes.
- 7-Zip also checks every such command against the commands its Finder menu actually offers:
  extract into the archive's own folder, test, add next to the selected items, compress and email,
  checksums and open. Anything else, including targets inside `~/Library` (other than iCloud Drive
  and cloud storage folders) or system folders and symbolic links that lead there, is refused with
  a message. The Services menu items apply the same target checks. The full command line
  (`7-Zip.app/Contents/MacOS/7-Zip a …`) is unchanged.
- The update check's **Download** button opens only this project's release pages on GitHub.

### Changed

- **Propagate Zone.Id** (Options ▸ 7-Zip) is **Yes** by default, on a fresh install and after
  Reset All Settings: files extracted from a downloaded (quarantined) archive keep the quarantine
  flag, as with Archive Utility. A value you chose is kept; *No* is now stored when you pick it.
- If you choose a Finder or Quick Action command before 7-Zip has ever been opened, 7-Zip opens,
  finishes setting up and asks you to choose the command again.

## [1.1.2] — 2026-10-07

7-Zip 26.04 for macOS 1.1.2.

### Fixed

- Clicking a column header did not sort when **Show ".." item** (Options ▸ Settings) was on. The
  click was saved as the new sort, but the list kept its order, in every folder and inside every
  archive: the ".." row was counted as an item of the folder, so the sort looked stale and was
  dropped. Sorting from the header, View ▸ Arrange By and Ctrl+F3…F7 work with ".." shown.
- A column layout saved by another version, or damaged, is cleaned up when it is read: unknown,
  duplicate or missing columns, a sort on a column the folder does not have, out-of-range widths
  and values of the wrong type no longer lose the layout or affect sorting.

### Added

- **Options ▸ macOS ▸ Reset All Settings…** asks for confirmation, then puts every 7-Zip setting
  back to its default — options, window and panel layout, column layouts and sorts, histories,
  favorites — and restarts the app. Your files, archives and the Finder extension's on/off state
  are not touched.

### Changed

- The theme is **Light** by default, on a fresh install and after Reset All Settings. A theme you
  chose (Light or Dark) is kept. Before 1.1.2 *System* was the default and was not stored, so
  *System* chosen explicitly cannot be told apart from never chosen: pick *System* again in
  Options ▸ macOS if you want it; it is stored from now on.
- The Homebrew cask removes the quarantine flag after installing or upgrading, so a Homebrew
  install opens without *Open Anyway*. The disk image still needs it.

## [1.1.1] — 2026-10-07

7-Zip 26.04 for macOS 1.1.1: fixes for problems reported against 1.0.0.

### Fixed

- Opening an application bundle or another package as a folder (for example a Chrome web-app
  shim in `~/Applications/Chrome Apps.localized/`) showed "E_FAIL Unspecified error". Enter on any
  folder now opens it, as 7-Zip File Manager does; Open Outside (Shift+Return) still launches an
  app. A directory tried as an archive is reported as "not an archive" instead of failing.
- File names with an emoji or any other character outside the Basic Multilingual Plane showed
  as empty rows, both in folders and inside archives.
- A name with a control character, such as the Finder's `Icon\r` file, was drawn higher than
  the other rows. Every row now draws its text on the same baseline whatever characters the name
  holds (emoji, Arabic, Thai, Tibetan, combining marks), and the name column draws nothing for a
  control character, as the Windows list does. Other columns show line breaks as spaces.
- The status bar's first text no longer runs into the window's rounded bottom-left corner: it
  moves in by the corner's reach (8 pt on macOS 26, 4 pt on earlier versions), so it clears the
  frame as 7-Zip File Manager's does. The other parts keep the Windows inset of 2 px.
- View > Arrange By checks Name when the list is sorted by a column that has no item of its own
  (Created, Packed Size, ...), as 7-Zip File Manager does; it used to check nothing.

## [1.1.0] — 2026-10-07

7-Zip 26.04 for macOS 1.1.0: the engine updated to
[7-Zip 26.04](https://github.com/ip7z/7zip/releases/tag/26.04) (2026-10-05).

### Changed

- Updated the engine to 7-Zip 26.04. Upstream's summary is "some bugs and vulnerabilities were
  fixed": the NTFS, VHD and WIM handlers were largely rewritten, and the ISO, NSIS, Zip, APM, Cab,
  DMG, Ext and other readers were hardened against malformed archives. Auxiliary items that a
  handler marks as such are now left out of extraction and of checksum calculation. No format,
  extension, command-line switch, menu item or dialog control was added or removed.
- The bundled assets come from the official 7-Zip 26.04 Windows release (`7z2604-x64.exe`): new
  `7z.sfx` and `7zCon.sfx` self-extracting modules, an updated Slovak translation, and the 26.04
  help pages.

### Fixed

- **CRC SHA** on items inside an archive now counts the folders and includes their names in
  "checksum for data and names", as 7-Zip File Manager 26.04 does, so the sum equals the one for the
  same tree on disk (earlier versions skipped folders). Extracting with checksums
  (`-scrc`) gets the matching fix from the 26.04 engine.

### Changed in upstream sources

- The guarded macOS patches carry over to 26.04 unchanged and are all still needed
  ([Mac/docs/upstream-patches.md](Mac/docs/upstream-patches.md)).

## [1.0.0] — 2026-10-07

First public release: a native macOS port of the 7-Zip File Manager on the 7-Zip 26.03 engine.

### Added

- The 7-Zip File Manager in AppKit: two panels, large icons / small icons / list / details views,
  sortable columns, flat view, folder history, favorites, Back / Forward, and the 7zFM keyboard map.
- Archives browsed and edited like folders, including nested archives with write-back, for every
  format the engine supports.
- Extract, Add to archive (all compression options, AES-256 encryption, multi-volume archives,
  Windows self-extracting archives), Test, checksums with every hash method, Benchmark, Split,
  Combine, Link, Properties and comments.
- Options with the seven Windows pages plus a macOS page (theme: System / Light / Dark, grid lines).
- The 93 official 7-Zip translations, switchable live; the 7-Zip help pages, bundled.
- Finder integration: a Finder Sync extension with the 7-Zip submenu, two Quick Actions, five
  Services, document icons for 40 archive types, the `sevenzip://` URL scheme and the 7zG
  command-line grammar.
- Quarantine propagation on extraction (the macOS counterpart of Zone.Identifier), Dock-tile
  progress, drag and drop with Finder and between panels.
- A universal app (Apple Silicon and Intel): the arm64 slice keeps upstream's ARM64 assembler
  LZMA decoder, the x86_64 slice uses 7-Zip's C code paths, as upstream's clang builds do.
- Distribution as an ad-hoc signed disk image, `7-Zip-26.03-macOS-1.0.0.dmg`, and a Homebrew cask
  (`brew install --cask yrambler2001/tap/7zip-macos`).
- An update check against GitHub Releases: at File Manager startup at most once a day (off in
  Options ▸ macOS ▸ Check for updates at startup) and from Help ▸ Check for Updates…, with
  Download / Later / Skip This Version. Nothing is downloaded or installed automatically.
- Versioning: one source of truth, `Mac/VERSION`; the build number is the commit count;
  `Mac/scripts/bump-version.sh` raises the version and opens a changelog section.
- GitHub Actions: CI on every push and pull request (hygiene checks, universal build and disk image,
  unit tests on Apple silicon and under Rosetta), and a release workflow that turns
  a `v<version>` tag into a tested GitHub Release with the disk image and its SHA-256, ready to sign
  and notarize once a Developer ID exists, and updates the Homebrew cask
  ([docs/releasing.md](docs/releasing.md)).

### Changed in upstream sources

- A small set of guarded patches to the engine sources so the file-manager layer builds and
  behaves correctly on macOS; Windows behaviour is unchanged. See
  [Mac/docs/upstream-patches.md](Mac/docs/upstream-patches.md).

[1.3.2]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.3.2
[1.3.1]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.3.1
[1.3.0]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.3.0
[1.2.1]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.2.1
[1.2.0]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.2.0
[1.1.3]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.1.3
[1.1.2]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.1.2
[1.1.1]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.1.1
[1.1.0]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.1.0
[1.0.0]: https://github.com/yrambler2001/7zip-macos/releases/tag/v1.0.0
