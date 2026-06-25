import SwiftUI

// The "Options" tab: how very large folders are presented, and reclaiming the
// disk that downloaded originals take. Bindings are owned by ContentView so the
// values save alongside the rest of the settings when the domain is enabled.
struct OptionsTab: View {
    @Binding var chunking: ChunkingSettings
    let isEnabled: Bool
    let isFreeingSpace: Bool
    let freedMessage: String?
    let onFreeUpSpace: () -> Void

    var body: some View {
        Form {
            largeFolders
            storage
        }
        .formStyle(.grouped)
    }

    private var largeFolders: some View {
        Section {
            Toggle(isOn: $chunking.enabled) {
                Label("Split large folders", systemImage: "square.grid.2x2")
            }
            if chunking.enabled {
                Picker(selection: $chunking.strategy) {
                    Text("Pages").tag(ChunkStrategy.pages)
                    Text("Year & month").tag(ChunkStrategy.date)
                } label: {
                    Label("Group by", systemImage: "calendar")
                }
                LabeledContent("Photos per page") {
                    HStack(spacing: 4) {
                        TextField("", value: $chunking.size, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Stepper("", value: $chunking.size, in: 100...10000, step: 100)
                            .labelsHidden()
                    }
                }
            }
        } header: {
            Text("Large folders")
        } footer: {
            Text("Folders larger than this many photos are split so each part loads on its own. “Pages” makes numbered slices; “Year & month” groups by date and pages a month only if it is itself too big. Places use pages. Takes effect on the next Update.")
        }
    }

    private var storage: some View {
        Section {
            Button {
                onFreeUpSpace()
            } label: {
                HStack(spacing: 6) {
                    if isFreeingSpace {
                        ProgressView().controlSize(.small)
                    }
                    Text("Free up space")
                }
            }
            .disabled(isFreeingSpace || isEnabled == false)

            if let freedMessage {
                Text(freedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Reverts downloaded originals to placeholders to reclaim disk. They re-download when next opened. Files you have open are kept.")
        }
        .listRowBackground(Color.clear)
    }
}
