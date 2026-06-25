# App

The container app (`ImmichDrive`). It collects your Immich server URL and API key, registers the File Provider domain so "Findich" shows up in the Finder sidebar, and exposes options for how large folders appear and for reclaiming downloaded-file disk. It does not browse files itself; the [extension](../FileProvider) handles all of that.

- `ContentView.swift`: the SwiftUI config window. A Setup tab (server URL and API key fields, the section toggles, and the Connect & Enable / Disable buttons) and an Options tab.
- `TabStrip.swift`: the Finder-style Setup / Options tab strip.
- `OptionsTab.swift`: the Options tab. Controls how large folders split (Pages or Year & month, and the page size) and the Free up space action.
- `SpaceManager.swift`: drives Free up space. Enumerates the materialized items and reverts the downloaded originals back to placeholders via `NSFileProviderManager.evictItem`; files in use are skipped.
- `DomainManager.swift`: adds, removes, and reloads the File Provider domain, and signals the Finder to refresh. Reloading on a credential change is what lets a new API key take effect.
- `ImmichDriveApp.swift`: the app entry point.
- `App.entitlements`: App Group plus sandbox, required for a File Provider container.

Credentials go to the Keychain via [`Shared/CredentialStore`](../Shared), and the extension reads them back from the same App Group. To build and run, see the root [README](../README.md).
