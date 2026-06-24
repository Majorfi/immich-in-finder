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
        // Self-heal control flow lives in DomainRegistration.register: try add, and
        // on failure clear this app's domains and retry once (see that helper for the
        // rationale on why removeAllDomains is safe here).
        try await DomainRegistration.register(
            add: { try await NSFileProviderManager.add(domain) },
            removeAll: { try await NSFileProviderManager.removeAllDomains() }
        )
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
