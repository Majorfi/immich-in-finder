import Foundation
import FileProvider

enum DomainManager {
    private static var domain: NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: AppGroup.domainIdentifier),
            displayName: AppGroup.domainDisplayName
        )
    }

    static func isRegistered() async -> Bool {
        let domains = try? await NSFileProviderManager.domains()
        return domains?.contains { $0.identifier.rawValue == AppGroup.domainIdentifier } ?? false
    }

    static func register() async throws {
        do {
            try await NSFileProviderManager.add(domain)
        } catch {
            // A domain left behind by a prior install (e.g. the app moved on disk,
            // or an upgrade) can linger pointing at a now-missing extension host and
            // block re-adding ours. removeAllDomains is scoped to *this* app's own
            // domains, so clearing and retrying once is safe and self-heals that state.
            try? await NSFileProviderManager.removeAllDomains()
            try await NSFileProviderManager.add(domain)
        }
    }

    static func unregister() async throws {
        try await NSFileProviderManager.remove(domain)
    }

    // Ask Finder to re-enumerate the root so a change to the visible sections
    // takes effect without re-mounting the domain.
    static func reloadRoot() {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: .rootContainer) { _ in }
    }

    // A credential change needs a fresh extension: the running one caches its
    // ImmichClient from the credentials read at init. Remove + re-add rebuilds it.
    static func reload() async throws {
        try? await NSFileProviderManager.remove(domain)
        try await register()
    }
}
