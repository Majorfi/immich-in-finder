import Foundation

enum DomainRegistration {
    /// Try `add`; on failure clear with `removeAll` (best-effort) and retry `add`
    /// once, propagating the second add's error.
    ///
    /// A domain left behind by a prior install (e.g. the app moved on disk, or an
    /// upgrade) can linger pointing at a now-missing extension host and block
    /// re-adding ours. removeAllDomains is scoped to *this* app's own domains, so
    /// clearing and retrying once is safe and self-heals that state.
    static func register(
        add: () async throws -> Void,
        removeAll: () async throws -> Void
    ) async throws {
        do {
            try await add()
        } catch {
            try? await removeAll()
            try await add()
        }
    }
}
