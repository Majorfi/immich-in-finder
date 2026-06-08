import SwiftUI

struct ContentView: View {
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var visibleSections: Set<SectionKind> = Set(SectionKind.allCases)
    @State private var status = ""
    @State private var isWorking = false
    @State private var isEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Immich Drive").font(.title2).bold()
                Text("Browse your Immich library in Finder.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Form {
                TextField("Server URL", text: $baseURL, prompt: Text("https://photos.example.com"))
                SecureField("API key", text: $apiKey)
            }
            .formStyle(.columns)

            VStack(alignment: .leading, spacing: 4) {
                Text("Visible folders").font(.subheadline).foregroundStyle(.secondary)
                ForEach(SectionKind.allCases, id: \.self) { kind in
                    Toggle(kind.displayName, isOn: Binding(
                        get: { visibleSections.contains(kind) },
                        set: { isOn in
                            if isOn { visibleSections.insert(kind) } else { visibleSections.remove(kind) }
                        }
                    ))
                }
            }

            HStack(spacing: 10) {
                Button(isEnabled ? "Update" : "Connect & Enable in Finder") {
                    Task { await enable() }
                }
                .disabled(isWorking || baseURL.isEmpty || apiKey.isEmpty || visibleSections.isEmpty)

                if isEnabled {
                    Button("Disable", role: .destructive) {
                        Task { await disable() }
                    }
                    .disabled(isWorking)
                }
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }

            if status.isEmpty == false {
                Text(status)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
        .task { await loadState() }
    }

    private func loadState() async {
        if let credentials = CredentialStore.load() {
            baseURL = credentials.baseURL.absoluteString
            apiKey = credentials.apiKey
        }
        visibleSections = VisibleSections.load()
        isEnabled = await DomainManager.isRegistered()
    }

    private func enable() async {
        isWorking = true
        defer { isWorking = false }

        guard let url = URL(string: baseURL) else {
            status = "✗ Invalid URL"
            return
        }
        do {
            let albums = try await ImmichClient(baseURL: url, apiKey: apiKey).listAlbums()
            status = "✓ Connected — \(albums.count) album(s) visible"
        } catch {
            status = "✗ Connection failed: \(error)"
            return
        }

        CredentialStore.save(baseURL: baseURL, apiKey: apiKey)
        VisibleSections.save(visibleSections)
        do {
            try await DomainManager.register()
            DomainManager.reloadRoot()
            isEnabled = true
            status += "\n✓ Enabled — open Finder and look for “Immich” in the sidebar."
        } catch {
            status += "\n✗ Could not register the File Provider: \(error)"
        }
    }

    private func disable() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await DomainManager.unregister()
            CredentialStore.clear()
            isEnabled = false
            status = "Disabled."
        } catch {
            status = "✗ Could not disable: \(error)"
        }
    }
}
