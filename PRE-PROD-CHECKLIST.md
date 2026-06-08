# Pre-production checklist — Immich in Finder

> Snapshot date: 2026-06-08. Revisit target: ~2026-06-22.
>
> **Where we are:** the API layer and the Swift 6 build are verified end-to-end.
> The File Provider *plumbing inside the real Finder* has **never been run** —
> that's the main gate before trusting this in daily use. Everything below the
> "✅ already verified" section is still open.

---

## ✅ Already verified this round (don't redo)

- API client works end-to-end against a live Immich **v2.5.6** server: auth,
  album list, album/timeline enumeration, original + thumbnail download.
- Write API verified live (then cleaned up): upload (multipart), add-to-album,
  create album, **trash = recoverable** (`isTrashed: true`, not permanent),
  rename album, move asset between albums.
- Album enumeration paginated via `/api/search/metadata?albumIds` — the 4433-asset
  album pages back to exactly 4433 items; `withExif` returns file sizes.
- Extension builds under **Swift 6 strict concurrency**, zero concurrency warnings.
- `ItemID` identifier construction ↔ parsing round-trips exactly.

---

## 🔴 Gate 1 — Signing & a real build (currently blocked)

- [ ] Produce a **signed** build (this machine has no Apple Developer account in
      Xcode; `CODE_SIGNING_ALLOWED=NO` only proves compilation). Either:
  - [ ] GUI: open `ImmichDrive.xcodeproj`, set Team = **Quub (QZSF4W9PK3)**,
        ☑ automatically manage signing on **both** targets, Run.
  - [ ] Headless: App Store Connect API key + `xcodebuild -allowProvisioningUpdates
        -authenticationKeyID/IssuerID/Path …`.
- [ ] Provisioning profiles generated for `app.quub.immichdrive` **and**
      `app.quub.immichdrive.FileProvider`.
- [ ] App Group `QZSF4W9PK3.app.quub.immichdrive` authorized by the profile.
- [ ] If shipping to anyone else: change `DEVELOPMENT_TEAM`, bundle IDs, and the
      App Group id in the three entitlements/`AppGroup.swift` (see README → Signing).

## 🔴 Gate 2 — Real Finder run (never exercised — the big unknown)

- [ ] App launches; config UI saves URL + API key (App Group `UserDefaults` + Keychain).
- [ ] **Connect & Enable in Finder** registers the domain with **no** `-2001`/`-2014`
      (the README's documented failure mode — needs `NSExtensionFileProviderDocumentGroup`).
- [ ] "Immich" appears in the Finder sidebar under Locations.
- [ ] `Albums/` lists folders; names disambiguated on collision.
- [ ] `Timeline/YYYY/MM` lists years → months → assets.
- [ ] Thumbnails render in Finder.
- [ ] Opening a photo materializes the original on demand.
- [ ] File sizes show on items (the `withExif` fix).
- [ ] Eviction frees local space (currently via deprecated `.allowsEvicting`).

## 🟠 Gate 3 — Write operations in the real Finder

> API calls are proven; what's unproven is the File Provider identity/refresh plumbing.

- [ ] Drag a photo into an album → uploads and appears (no ghost/duplicate entry).
- [ ] Create a folder under `Albums/` → creates an Immich album.
- [ ] Delete a photo → lands in Immich trash (recoverable 30 d), vanishes from Finder.
- [ ] Rename an album folder → renames the Immich album.
- [ ] Move a photo between albums → re-links (gone from source, present in dest).
- [ ] An already-open Finder window refreshes after a write (`signalEnumerator`).
- [ ] `Timeline/` and asset rename are rejected cleanly (read-only paths).
- [ ] A failed write (server offline / bad key) shows a sane Finder error, not a hang.

## 🟠 Gate 4 — Scale & edge cases

- [ ] Large album (4400+) enumerates in Finder without timeout (pagination holds).
- [ ] Bulk drag (~50 files at once) — no errors, no album-list refetch storm.
- [ ] Large video upload — **currently buffered fully in memory** (see deferred tasks).
- [ ] Assets with missing/odd metadata decode (nullable model fields).
- [ ] Special characters / very long names in albums and files.
- [ ] Trash/move propagation: deleted/moved asset still shows in *other* views until
      re-navigation — confirm this is acceptable or schedule the sync fix.

## 🟡 Gate 5 — Auth, errors, resilience

- [ ] Revoked/expired API key → graceful failure, domain not left broken.
- [ ] Server unreachable / slow → no UI hang, retriable.
- [ ] Map failures to specific `NSFileProviderError` codes (`.notAuthenticated`,
      `.insufficientQuota`, `.serverUnreachable`) instead of generic errors.
- [ ] Extension killed mid-upload (system kills FP extensions aggressively) leaves
      no corrupt/partial state.

## 🟡 Gate 6 — Security & config

- [ ] API key stored only in Keychain; confirm it never appears in `fileProviderLog`
      (logs use `privacy: .public` on ids — verify no key/URL leakage).
- [ ] Use a **scoped** Immich API key for real use (the dev key was a throwaway in a
      controlled env).
- [ ] `.env.local` stays gitignored; no secrets committed.

## 🟢 Deferred / hardening (tracked, not blockers)

- [ ] Stream uploads instead of buffering in memory — *spawned task task_4dfd352b*.
- [ ] `allowsEvicting` → `NSFileProviderContentPolicy` — *spawned task task_d6f790f1*.
- [ ] Full two-way sync: real `enumerateChanges` + persisted sync anchors so remote
      changes (phone/web) propagate to Finder automatically.
- [ ] Commit a small test target: `ItemID` round-trip, model decoding, API contract.
- [ ] Keep `SWIFT_VERSION = 6.0` + strict concurrency on the extension (already set).

---

### Definition of done for "prod"

Gates 1–3 fully green on a real machine, Gate 5 (auth/error) at least graceful,
and the Gate 4 large-album + bulk-drag cases confirmed. Gates in 🟢 can ship after.
