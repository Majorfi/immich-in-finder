# Tests

The `ImmichDriveTests` target holds two tiers in one bundle. Unit tests run with no server and no signing. They cover the pure logic: the `ItemID` identifier grammar, asset-to-folder mapping, filename disambiguation, model decoding, error mapping, and cache memoization. The live integration tests (`*IntegrationTests.swift`) hit a real Immich server and skip themselves unless `IMMICH_BASE_URL` and `IMMICH_API_KEY` are set, so the suite stays green in CI without one.

`MockURLProtocol.swift` is the shared scaffolding: it intercepts requests so the unit tests drive `ImmichClient` against canned HTTP responses. `MockClient` and `Fixtures` build those responses, and `IntegrationTestCase` is the env-gated base class for the live tests.

Run commands live in the root [README](../README.md#tests).
