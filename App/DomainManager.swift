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
        try await NSFileProviderManager.add(domain)
    }

    static func unregister() async throws {
        try await NSFileProviderManager.remove(domain)
    }

    // Ask Finder to re-enumerate the root so a change to the visible sections
    // takes effect without re-mounting the domain.
    static func reloadRoot() {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: .rootContainer) { _ in }
    }
}
