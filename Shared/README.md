# Shared

Code compiled into both targets, the [app](../App) and the [File Provider extension](../FileProvider), plus the test bundle. It is the contract between two separate processes, so everything here is `Sendable` and builds under the extension's Swift 6 strict concurrency.

- `ImmichClient.swift`: the only thing that talks to Immich. A thin async REST client (`x-api-key` plus any user custom headers) with paging and a bounded retry.
- `ImmichModels.swift`: the `Decodable` wire models. Server `id` fields are renamed to `assetID`, `albumID`, and the like through `CodingKeys`.
- `CredentialStore.swift`: reads and writes the server URL (App Group defaults) and the API key plus any custom request headers (Keychain, keyed by account), shared through the App Group.
- `CustomHeaders.swift`: the editable name/value model for custom request headers, and its collapse into the `[field: value]` map the client sends. Used to reach a server behind an auth proxy (Cloudflare Access, basic-auth).
- `AppGroup.swift`: the shared App Group, domain, and UserDefaults identifiers.
- `VisibleSections.swift`: which top-level folders appear in Finder, persisted in App Group defaults.
- `ChunkingSettings.swift`: how a large folder splits (Pages or Year & month, and the page size), persisted in App Group defaults. The page-boundary math here is shared by enumeration and an asset's parent resolution, so they cannot disagree.
- `DateChunkLayout.swift`: the pure year/month/page tree for the date strategy, derived from each asset's capture month so listing a folder and resolving an asset's parent always agree. No FileProvider dependency, so it is unit-tested directly.
- `DomainRegistration.swift`: the add and remove-then-retry logic for registering the domain, factored out so it can be tested without `NSFileProviderManager`.
