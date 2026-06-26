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
    // surrounding whitespace a paste tends to carry. HTTP header names are
    // case-insensitive, so rows whose names differ only by case are the same
    // header: the last-entered row wins, and its exact casing is what is sent.
    var asRequestHeaders: [String: String] {
        var headers: [String: String] = [:]
        for header in self {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            // Drop any prior entry that differs only by case, so the collapse is
            // deterministic: a Dictionary's iteration order is not guaranteed, and
            // request.setValue is itself case-insensitive, so two surviving keys
            // would otherwise race in makeRequest.
            for existing in headers.keys where existing.caseInsensitiveCompare(name) == .orderedSame {
                headers[existing] = nil
            }
            headers[name] = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headers
    }
}
