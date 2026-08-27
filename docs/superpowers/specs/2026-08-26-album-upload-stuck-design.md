# Album drop stuck at "waiting to upload" (issue #17, Bug 2) — design

## Problem

Dropping a photo into an album folder uploads it to Immich successfully, but
Finder shows the item as "waiting to upload" forever.

## Contract research (what it ruled out)

The `NSFileProviderItem.h` SDK header settled three theories from the initial
exploration, all of which turned out NOT to be the cause:

- **contentVersion:** a changed `contentVersion` triggers a re-download, _except_
  "when the extension accepts a content sent by the system when replying to a
  createItem/modifyItem call with shouldFetchContent set to NO." We already
  return `shouldFetchContent = false`, so the server-checksum contentVersion does
  not strand the upload.
- **isUploaded:** the header states an item is uploaded when
  "`-[NSFileProviderItem isUploaded]` not implemented or set to YES." Not
  implementing it defaults to uploaded, so its absence cannot cause a stuck
  "waiting to upload".
- **Parent mismatch (chunk sub-folder):** chunking is opt-in and disabled by
  default (`ChunkingSettings.default.enabled == false`), so a generic report is
  not hitting the chunk-parent divergence.

## Root cause

The album-drop branch of `createItem`
(`FileProvider/FileProviderExtension.swift`, ~646-651) resolves the freshly
uploaded asset only through the album membership search:

```swift
let siblings = try await cache.assets(for: .album(id: albumID))  // → /search/metadata
guard let resolved = resolveAsset(result.ID, in: siblings) else {
    completionHandler(nil, [], false, Self.error(.noSuchItem))
    ...
}
```

`cache.assets(for: .album)` calls `searchMetadata(albumIDs:)` → `/search/metadata`,
whose index lags ~1s behind a mutation (see the `immich-v3-timeline-index-lag`
note). Within that window the just-added asset is absent, `resolveAsset` returns
nil, and `createItem` returns `.noSuchItem` — a failed create for an upload that
actually succeeded. The system leaves Finder's placeholder stuck at "waiting to
upload".

The Timeline-drop branch already works around this (same file, ~604-616): it
resolves via `client.getAsset(assetID:)`, which hits the asset row directly and
is immune to the search-index lag, and inserts the asset into the (possibly
stale) siblings list if the search does not include it yet. The album branch
never received the same fix.

## Fix

Mirror the Timeline branch in the album branch: resolve the asset via
`client.getAsset(assetID: result.ID)` and insert it into `siblings` when the
album search does not contain it yet, before `resolveAsset`. No new helpers —
`getAsset`, `insertByFileCreatedAt`, and `resolveAsset` are already used by the
Timeline branch. ~5 changed lines, scoped to the album-drop path.

## Scope

Only the album-drop branch. The other `createItem` branches do not have this
defect: Timeline is already fixed; album-folder creation resolves via
`/api/albums` (a direct listing, not the lagging search).

## Verification

Build both targets. Manual: drop a photo into an album folder, confirm Finder
clears the "waiting to upload" badge (no longer stuck) while the asset appears
on the Immich server.
