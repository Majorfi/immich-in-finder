import Foundation

// One user-supplied HTTP header sent on every Immich request, so a server behind
// an auth reverse proxy (Cloudflare Access, basic-auth, a WAF) is reachable. This
// mirrors Immich's own "custom proxy headers". rowID is a transient SwiftUI
// identity for the editor, deliberately neither persisted nor compared: two rows
// are the same header when their name and value match, so a reload (which mints
// fresh rowIDs) never reads as a credential change.
struct CustomHeader: Codable, Equatable, Sendable {
    let rowID = UUID()
    var name: String
    var value: String

    private enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    static func == (lhs: CustomHeader, rhs: CustomHeader) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value
    }
}

extension Sequence where Element == CustomHeader {
    // Collapses the editable rows into the [field: value] map applied to each
    // request, dropping rows whose trimmed name is empty and trimming the
    // surrounding whitespace a paste tends to carry. A later row with the same
    // name wins.
    var asRequestHeaders: [String: String] {
        var headers: [String: String] = [:]
        for header in self {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            headers[name] = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headers
    }
}
