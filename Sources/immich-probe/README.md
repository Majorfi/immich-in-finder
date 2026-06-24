# immich-probe

A standalone command-line tool that exercises the Immich API (auth, album and timeline enumeration, original and thumbnail download) with none of the File Provider machinery. Reach for it to check a server and key in isolation when something looks wrong, before blaming the extension.

It is a separate SwiftPM target that shares no module with the app, so it carries its own trimmed copy of the client and models (`ImmichClient.swift`, `Models.swift`). That duplication is deliberate: do not fold it back into [`Shared`](../../Shared), or the probe stops being a self-contained diagnostic.

Usage is in the root [README](../../README.md#the-probe-cli).
