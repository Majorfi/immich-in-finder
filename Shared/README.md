# Shared

Code compiled into both targets, the [app](../App) and the [File Provider extension](../FileProvider), plus the test bundle. It is the contract between two separate processes, so everything here is `Sendable` and builds under the extension's Swift 6 strict concurrency.

- `ImmichClient.swift`: the only thing that talks to Immich. A thin async REST client (`x-api-key` header) with paging and a bounded retry.
- `ImmichModels.swift`: the `Decodable` wire models. Server `id` fields are renamed to `assetID`, `albumID`, and the like through `CodingKeys`.
- `CredentialStore.swift`: reads and writes the server URL and API key in the Keychain, shared through the App Group.
- `AppGroup.swift`: the shared App Group, domain, and UserDefaults identifiers.
- `VisibleSections.swift`: which top-level folders appear in Finder, persisted in App Group defaults.
- `DomainRegistration.swift`: the add and remove-then-retry logic for registering the domain, factored out so it can be tested without `NSFileProviderManager`.
