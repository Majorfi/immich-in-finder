import Foundation

// The top-level views the extension can expose in Finder. Adding a case here is
// the single point of extension for a new view (People, Places, Tags, …): it
// shows up as a toggle in the app and as a section the enumerator can emit.
enum SectionKind: String, CaseIterable, Sendable {
    case albums
    case timeline
    case people
    case places
    case tags
    case favorites

    // Every raw value is its display name lowercased, so derive it.
    var displayName: String { rawValue.capitalized }
}

// Which sections the user chose to show, shared from the app to the extension
// via the App Group. Absent (first run) means all of them.
enum VisibleSections {
    static func load() -> Set<SectionKind> {
        guard let raw = AppGroup.defaults?.stringArray(forKey: AppGroup.DefaultsKey.visibleSections) else {
            return Set(SectionKind.allCases)
        }
        return Set(raw.compactMap(SectionKind.init(rawValue:)))
    }

    static func save(_ sections: Set<SectionKind>) {
        AppGroup.defaults?.set(sections.map(\.rawValue), forKey: AppGroup.DefaultsKey.visibleSections)
    }
}
