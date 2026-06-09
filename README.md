# Immich in Finder

> Browse your self-hosted [Immich](https://immich.app) photo library as a native folder in the macOS Finder — like iCloud Drive or Dropbox, but for Immich.

Immich organizes photos by timeline, albums, people, and places — not by folders. This project bridges that gap with an Apple **File Provider** extension that presents your Immich library as a Finder location, with **on-demand download**: files appear as placeholders and only download when you open them.

**Status:** early, read-only. Your **albums show up as folders**; browsing, Finder thumbnails, and on-demand materialization of original files all work.

```
Immich/                      ← appears in the Finder sidebar
├── Sitges/                  ← an album
│   ├── 20181013-1513-000.jpg
│   └── ...
└── <other albums>/
```

## How it works

- A small **container app** (`ImmichDrive`) registers a File Provider _domain_ and stores your server URL + API key (App Group `UserDefaults` + Keychain).
- A **File Provider extension** (`NSFileProviderReplicatedExtension`) does the real work: enumerating albums and assets, serving thumbnails, and downloading originals on demand.
- Both talk to Immich's REST API (`/api/albums`, `/api/assets/{id}/original`, `/api/assets/{id}/thumbnail`, …) using the `x-api-key` header.

## Requirements

- macOS 13 or later
- Xcode (developed with 26.5)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated from `project.yml`, not committed
- A running Immich server and an API key (Immich → _Account Settings → API Keys_)
- An Apple Developer team (File Provider extensions require real signing — see [Signing](#signing))

## Setup

```bash
git clone git@github.com:Majorfi/immich-in-finder.git
cd immich-in-finder

# 1. configure your server (used by the probe CLI below)
cp .env.local.example .env.local
$EDITOR .env.local            # set IMMICH_BASE_URL and IMMICH_API_KEY

# 2. generate the Xcode project
brew install xcodegen
xcodegen generate

# 3. open, then run the ImmichDrive scheme (⌘R)
open ImmichDrive.xcodeproj
```

In the app window, enter your server URL + API key and click **Connect & Enable in Finder**. "Immich" appears in the Finder sidebar under _Locations_.

## Signing

File Provider extensions need a real provisioning profile (App Group + sandbox). `project.yml` is set up for team `QZSF4W9PK3` and bundle IDs `app.quub.immichdrive(.FileProvider)`. To build under your own account, change `DEVELOPMENT_TEAM`, the bundle identifiers, and the App Group id in `App/App.entitlements`, `FileProvider/FileProvider.entitlements`, and `Shared/AppGroup.swift`, then let Xcode's automatic signing register them.

## The probe CLI

`immich-probe` is a standalone SwiftPM tool that exercises the Immich API (auth, album enumeration, original + thumbnail download) without any File Provider machinery — handy for checking your server and key in isolation:

```bash
set -a; source .env.local; set +a
swift run immich-probe
```

## Project layout

```
App/                  # container app (SwiftUI): config UI + domain registration
FileProvider/         # the File Provider extension: enumeration, items, fetch
Shared/               # Immich API client + models, compiled into both targets
Sources/immich-probe/ # standalone API probe CLI
project.yml           # XcodeGen project spec
```

## Note for fellow File Provider implementers

The extension's `Info.plist` **must** include `NSExtensionFileProviderDocumentGroup` (set to your App Group) and `NSExtensionFileProviderSupportsEnumeration`. Without the DocumentGroup key, `NSFileProviderManager.add(domain:)` fails with `-2001` / underlying `-2014` ("no launchable extension for this domain's app bundle") and the extension never starts — even when signing, entitlements, and registration all look correct.

## Roadmap

- [x] Albums as folders (read-only, on-demand originals + thumbnails)
- [x] Filename / album-name collision handling
- [x] `Timeline/YYYY/MM` view (via `/api/search/metadata`)
- [x] Swift 6 strict-concurrency hardening of the extension
- [x] Write support, phase 1: upload into albums, create albums, delete to trash
- [x] Write support, phase 2: rename albums, move assets between albums
- [x] Refresh the affected container after a local write (`signalEnumerator`)
- [x] Settings toggle to choose which top-level folders show in Finder
- [x] `People/` view — named people as folders (facial recognition)
- [x] `Places/` view — `Country/City/` hierarchy (geocoding)
- [x] `Tags/` view — tags as folders (`tagIds`)
- [ ] Full two-way sync: pull remote changes via `enumerateChanges` + sync anchors
- [ ] Favorites
