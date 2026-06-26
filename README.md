# Findich

> **Findich** is an Immich drive. Browse your self-hosted [Immich](https://immich.app) photo library as a native folder in the macOS Finder, like iCloud Drive or Dropbox, but for Immich.

<img width="1543" height="869" alt="findich-cover 1" src="https://github.com/user-attachments/assets/16debed7-1b12-4140-bd71-ba06726b4ddc" />

Immich organizes photos by timeline, albums, people, and places, not by folders. This project bridges that gap with an Apple **File Provider** extension that presents your Immich library as a Finder location, with **on-demand download**: files appear as placeholders and only download when you open them.

**Status:** working and read-write. Albums, timeline, people, places, tags, and favorites show up as folders, with on-demand downloads and Finder thumbnails. Uploads, renames, moves, and deletes sync back to Immich.

```
Findich/                     ← appears in the Finder sidebar
├── Albums/                  ← each Immich album, a folder of originals
├── Timeline/2024/03/        ← every photo, by year and month
├── People/                  ← named faces
├── Places/France/Paris/     ← country / city
├── Tags/
└── Favorites/
```

## Getting Findich

Build it from source (see [Setup](#setup)) for free, or download a ready-to-run, signed and notarized build from [Gumroad](https://withquub.gumroad.com/l/grbwny). It's pay-what-you-want, and zero is a valid price.

### Homebrew

```bash
brew tap majorfi/tap && brew trust majorfi/tap && brew install --cask findich
```

`brew trust` is a one-time confirmation Homebrew 6+ asks for any third-party tap. This installs the same signed, notarized build from GitHub Releases; the app updates itself (Sparkle), so `brew upgrade` leaves it alone.

Why pay-what-you-want? Shipping a Mac app outside the App Store needs an Apple Developer Program membership ($99/year), plus Developer-ID signing and Apple notarization so Gatekeeper doesn't block it on first launch. The source is open and free to build yourself; the paid build just saves you the Xcode round-trip and helps cover those running costs.

## How it works

- A small **container app** (`ImmichDrive`) registers a File Provider _domain_ and stores your server URL + API key (App Group `UserDefaults` + Keychain). Its **Options** tab controls how large folders appear and reclaims disk:
  - **Split large folders**: a folder over the chosen size is shown as sub-folders so each loads on its own. _Pages_ makes numbered slices (`0001-1000`, …); _Year & month_ groups by capture date (Places and Timeline months always use pages). Takes effect on the next Update.
  - **Free up space**: reverts downloaded originals back to placeholders to reclaim disk; they re-download when next opened, and files in use are kept.
- A **File Provider extension** (`NSFileProviderReplicatedExtension`) does the real work: enumerating albums and assets, serving thumbnails, and downloading originals on demand.
- Both talk to Immich's REST API (`/api/albums`, `/api/assets/{id}/original`, `/api/assets/{id}/thumbnail`, `/api/search/statistics`, …) using the `x-api-key` header.

Note: photos Immich indexes from an **external library** are read-only. Findich browses and downloads them like any other asset, but it can't write them back; Immich owns those files and refreshes them from the source itself. Findich doesn't single them out in Finder yet, so a delete or move you try there just won't take.

## Servers behind an auth proxy

If your Immich server sits behind an authenticating reverse proxy (Cloudflare Access, basic-auth, a WAF), add the headers it expects under **Options → Custom request headers** (a shortcut link sits in the Setup tab); they ride along on every request, the same as Immich's own "custom proxy headers". For a Cloudflare Access service token, add `CF-Access-Client-Id` and `CF-Access-Client-Secret`. Those values can be bearer tokens, so they're stored in the Keychain alongside the API key, not in the App Group preferences.

## Requirements

- macOS 13 or later
- Xcode (developed with 26.5)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): the `.xcodeproj` is generated from `project.yml`, not committed
- A running Immich server and an API key (Immich → _Account Settings → API Keys_)
- An Apple Developer team (File Provider extensions require real signing; see [Signing](#signing))

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

In the app window, enter your server URL + API key and click **Connect & Enable**. "Findich" appears in the Finder sidebar under _Locations_.

## API key permissions

Immich scopes each API key to a set of permissions (Account Settings → API Keys). The simplest choice is a key with all permissions, since Findich reads most of your library and writes back to it. To scope it instead, here is exactly what it uses.

Read (browsing, thumbnails, downloads):

- `asset.read`: timeline, places, and album search
- `asset.view`: thumbnails
- `asset.download`: opening a photo (the original)
- `album.read`: the Albums folder
- `person.read`: the People folder
- `tag.read`: the Tags folder

Write (drag-in, rename, move, delete):

- `asset.upload`: drop a file in to upload it
- `asset.delete`: delete to trash
- `album.create`: create an album (a new folder under Albums)
- `album.update`: rename an album
- `album.delete`: delete an album
- `albumAsset.create`: add a photo to an album
- `albumAsset.delete`: remove a photo from an album

A key with only the read permissions still works for browsing and downloading. The write actions then fail cleanly in Finder instead of syncing back, which is a fine setup if you only want Findich for browsing.

## Signing

File Provider extensions need a real provisioning profile (App Group + sandbox). `project.yml` is set up for team `QZSF4W9PK3` and bundle IDs `app.quub.immichdrive(.FileProvider)`. To build under your own account, change `DEVELOPMENT_TEAM`, the bundle identifiers, and the App Group id in `App/App.entitlements`, `FileProvider/FileProvider.entitlements`, and `Shared/AppGroup.swift`, then let Xcode's automatic signing register them.

## The probe CLI

`immich-probe` is a standalone SwiftPM tool that exercises the Immich API (auth, album enumeration, original + thumbnail download) without any File Provider machinery, handy for checking your server and key in isolation:

```bash
set -a; source .env.local; set +a
swift run immich-probe
```

## Tests

The `ImmichDriveTests` target holds unit tests for the pure logic (identifier
grammar, asset-location mappings, filename disambiguation, model decoding),
which run with no server and no signing:

```bash
xcodebuild test -scheme ImmichDriveTests -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

The same target also has live API integration tests. They skip
unless a server is configured, so set it first (the key is never committed):

```bash
set -a; source .env.local; set +a   # IMMICH_BASE_URL + IMMICH_API_KEY
xcodebuild test -scheme ImmichDriveTests -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Project layout

```
App/                  # container app (SwiftUI): config UI + domain registration
FileProvider/         # the File Provider extension: enumeration, items, fetch
Shared/               # Immich API client + models, compiled into both targets
Tests/                # unit tests + live API integration tests
Sources/immich-probe/ # standalone API probe CLI
project.yml           # XcodeGen project spec
```

## Note for fellow File Provider implementers

The extension's `Info.plist` **must** include `NSExtensionFileProviderDocumentGroup` (set to your App Group) and `NSExtensionFileProviderSupportsEnumeration`. Without the DocumentGroup key, `NSFileProviderManager.add(domain:)` fails with `-2001` / underlying `-2014` ("no launchable extension for this domain's app bundle") and the extension never starts, even when signing, entitlements, and registration all look correct.

## Roadmap

- [x] Albums as folders (on-demand originals + thumbnails)
- [x] Filename / album-name collision handling
- [x] `Timeline/YYYY/MM` view (via `/api/search/metadata`)
- [x] Swift 6 strict-concurrency hardening of the extension
- [x] Write support, phase 1: upload into albums, create albums, delete to trash
- [x] Write support, phase 2: rename albums, move assets between albums
- [x] Refresh the affected container after a local write (`signalEnumerator`)
- [x] Settings toggle to choose which top-level folders show in Finder
- [x] `People/` view: named people as folders (facial recognition)
- [x] `Places/` view: `Country/City/` hierarchy (geocoding)
- [x] `Tags/` view: tags as folders (`tagIds`)
- [x] `Favorites/` view: favorited assets, flat (`isFavorite`)
- [x] Options tab: split large folders into pages or year/month groups
- [x] Free up space: evict downloaded originals back to placeholders
- [x] Custom request headers: reach a server behind Cloudflare Access / an auth proxy
- [ ] Full two-way sync: pull remote changes via `enumerateChanges` + sync anchors

## Releasing

Distributed builds must be Developer-ID signed **and notarized**, or Gatekeeper blocks them on first launch. Store your notary credentials in the keychain once:

```bash
xcrun notarytool store-credentials findich-notary \
  --apple-id you@example.com --team-id QZSF4W9PK3 \
  --password APP_SPECIFIC_PASSWORD   # appleid.apple.com -> App-Specific Passwords
```

Then build, notarize, staple, and package a DMG:

```bash
./scripts/release.sh            # build build/Findich.dmg
./scripts/release.sh 1.0.0      # ...and publish: GitHub Release, appcast, Homebrew cask
```

The stapled `build/Findich.dmg` is the artifact to distribute: upload it to Gumroad, or pass a version to do the rest. With a version, the script also creates the GitHub Release, commits and pushes `site/public/appcast.xml`, and bumps the Homebrew cask (version + sha256) in the tap, committing and pushing it. The tap is a sibling `../homebrew-tap` clone by default; set `TAP_DIR` if yours is elsewhere.

### Smoke test before publishing

Some behavior (the real Keychain, Sparkle, the Finder extension) needs a signed run and is not covered by the unit tests. Run this once per release, with version N already installed:

1. `./scripts/release.sh N+1` — builds, notarizes, publishes the GitHub Release, pushes the appcast, and bumps the Homebrew cask.
2. Wait for the site to deploy so the appcast is live.
3. In version N: Findich menu → Check for Updates, which should offer N+1.
4. Download it and confirm it installs and relaunches (the EdDSA signature verifies).
5. Keychain: no keychain prompt during or after the update.
6. Finder: "Findich" is still in the sidebar.
7. File Provider: browse an album, open a photo (download), drag a file in (upload).
8. Options → Split large folders (Pages): a large album shows numbered sub-folders; open one and confirm photos download.
9. Options → Group by Year & month: the same album shows year/month folders.
10. Options → Free up space: after downloading a few originals, confirm they revert to placeholders.
11. Lock then unlock the screen, then browse again with no auth error.
12. CI is green on the commit (pure logic plus the appcast generator test).

## Security usage note

**Plain-HTTP servers expose your API key.** Findich allows cleartext connections so it can reach self-hosted servers without TLS (LAN IPs, Tailscale, reverse proxies). If your server URL is `http://` rather than `https://`, your Immich API key is sent unencrypted on every request, so anyone who can observe the network between you and the server can capture it (and that key grants full access to your library). On an untrusted network, use an `https://` URL or a tunnel such as Tailscale that encrypts the transport.

As with any software, there may still be bugs, edge-case errors, or incomplete hardening details. We aim to keep behavior safe, stable, and security-aware, but no software is perfect. We used AI models as a drafting and review aid during implementation.

It was not vibe-coded. Design decisions and a major part of the implementation were still done by a human.

Use this project at your own risk.

## License

GPL-3.0 (see [LICENSE](LICENSE)).
