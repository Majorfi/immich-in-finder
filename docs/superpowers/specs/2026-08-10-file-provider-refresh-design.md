# File Provider refresh (issue #17) — design

## Problem

Clicking "Update" in the main app does not refresh content in Finder. Only
toggling "Disable" → "Connect & Enable" does. Reported in issue #17.

## Root cause

Two compounding facts, both in the File Provider extension:

1. The running extension memoizes every list/asset fetch for its whole process
   lifetime in the `ImmichCache` actor (`FileProvider/ItemEnumerator.swift`).
   The `invalidate*` methods are only called from the extension's own write
   paths — there is no path from the app to flush a running extension's cache.

2. `DomainManager.reloadRoot()` signals only `.rootContainer`, and even that
   re-enumeration serves the stale memoized data.

Only `Disable → Enable` works because `NSFileProviderManager.remove(domain)`
tears down the extension process; re-enabling spawns a fresh extension with an
empty cache. A plain "Update" takes the `register()` path on an already-present
domain, which never restarts the extension.

A prior attempt returned a non-nil `currentSyncAnchor` with a no-op
`enumerateChanges` (an incremental-change-feed approach). It made the system
stop re-enumerating and serve stale/empty snapshots, and was reverted to a
`nil` anchor. We are not revisiting that approach.

## Approach

Reuse the existing App Group `UserDefaults` channel (already used for chunking,
visible sections, filename source) — no new XPC plumbing. Two flush triggers on
the extension's shared `ImmichCache`:

- **On-demand flush:** the app bumps a shared generation counter on "Update".
  The extension flushes its whole cache when the counter changes.
- **TTL flush:** the cache flushes itself when its data is older than 60s, so
  content refreshes "from time to time" on its own.

With the current `nil` sync anchor, every folder open re-runs `enumerateItems`
in full, so a flushed cache is all that is needed for the next enumeration to
serve fresh data.

## Changes

1. **`Shared/AppGroup.swift`** — add a `refreshGeneration` defaults key with a
   read accessor and a `bumpRefreshGeneration()` writer.

2. **`FileProvider/ItemEnumerator.swift` (`ImmichCache`)** — add
   `refreshIfNeeded()`: flush all when the generation changed, else flush all
   when `stampedAt` is older than the 60s TTL. Add a private `flushAll()` that
   nils every memoized `Task` / empties the dicts and resets `stampedAt`. Call
   `await cache.refreshIfNeeded()` at the top of the `enumerateItems` Task.

3. **`App/DomainManager.swift`** — replace `reloadRoot()` with
   `requestRefresh()`: `AppGroup.bumpRefreshGeneration()` then
   `signalEnumerator(for: .rootContainer)`.

4. **`App/ContentView.swift`** — call `DomainManager.requestRefresh()` instead
   of `reloadRoot()` in `enable()`.

## Resulting behavior

- **"Update"** bumps the generation; the next enumeration (root is signaled
  immediately, or any folder the moment it is re-opened) flushes the whole
  cache and serves fresh data. No more Disable/Enable dance.
- **Auto-refresh:** past 60s, the next enumeration of any container flushes and
  re-fetches.

## Known limitation

`.rootContainer` signaling repaints the top level immediately. A deep folder
that is already open on screen does not repaint instantly — Finder only
re-enumerates a subfolder when the user re-navigates to it. After "Update" that
folder is fresh as soon as it is re-opened (its cache is already flushed). This
matches Disable/Enable behavior minus the process restart. `.workingSet`
signaling is out of scope: its enumerator is currently inert (returns sections,
nil anchor) and belongs to the separate upload-state issue (Bug 2).

## Design choices

- **Coarse flush** (whole cache at once) via a single `stampedAt` and single
  `lastSeenGeneration`, rather than per-entry timestamps across the 8 memoized
  slots. Less code; per-entry precision buys nothing here since a flush only
  causes on-demand network refetches.
- **Plain `defaults.integer` read** each enumeration, not cross-process KVO
  (unreliable). Same read pattern the chunking/visible-sections settings
  already use.

## Verification

Build both targets. Manual: enable the domain, add a photo/album on the Immich
server, click "Update", confirm Finder shows it without Disable/Enable. Confirm
that leaving content untouched for >60s and re-opening a folder also picks up
server-side changes.
