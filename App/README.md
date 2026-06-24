# App

The container app (`ImmichDrive`). It does two things: collect your Immich server URL and API key, and register the File Provider domain so "Findich" shows up in the Finder sidebar. It does not browse files itself; the [extension](../FileProvider) handles all of that.

- `ContentView.swift`: the SwiftUI config window, with the server URL and API key fields, the section toggles, and the Connect & Enable / Disable buttons.
- `DomainManager.swift`: adds, removes, and reloads the File Provider domain, and signals the Finder to refresh. Reloading on a credential change is what lets a new API key take effect.
- `ImmichDriveApp.swift`: the app entry point.
- `App.entitlements`: App Group plus sandbox, required for a File Provider container.

Credentials go to the Keychain via [`Shared/CredentialStore`](../Shared), and the extension reads them back from the same App Group. To build and run, see the root [README](../README.md).
