import SwiftUI

struct ContentView: View {
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var visibleSections: Set<SectionKind> = Set(SectionKind.allCases)
    @State private var status: Status = .idle
    @State private var isWorking = false
    @State private var isEnabled = false

    private enum Status: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 480, height: 640)
        .task { await loadState() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 1) {
                Text("Findich").font(.title2.weight(.bold))
                Text("Your photo library, in Finder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var appIcon: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: 50, height: 50)
    }

    private var statusBadge: some View {
        let on = isEnabled
        return HStack(spacing: 5) {
            Circle().fill(on ? Color.green : Color.secondary).frame(width: 6, height: 6)
            Text(on ? "Active" : "Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(on ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill((on ? Color.green : Color.secondary).opacity(0.12)))
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section("Server") {
                LabeledContent {
                    TextField("", text: $baseURL, prompt: Text("https://photos.example.com"))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                } label: {
                    Label("Address", systemImage: "network")
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        Group {
                            if showKey {
                                TextField("", text: $apiKey, prompt: Text("Paste your API key"))
                            } else {
                                SecureField("", text: $apiKey, prompt: Text("Paste your API key"))
                            }
                        }
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(showKey ? "Hide key" : "Show key")
                    }
                } label: {
                    Label("API Key", systemImage: "key.fill")
                }
            }

            Section {
                ForEach(SectionKind.allCases, id: \.self) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label {
                            Text(kind.displayName)
                        } icon: {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint(kind)))
                        }
                    }
                }
            } header: {
                Text("Folders in Finder")
            } footer: {
                Text("Choose which of Immich’s views appear under “Findich” in the Finder sidebar.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            statusView
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.default, value: status)

            HStack(spacing: 10) {
                if isEnabled {
                    Button("Disable", role: .destructive) {
                        Task { await disable() }
                    }
                    .controlSize(.large)
                    .disabled(isWorking)
                }
                Spacer()
                Button {
                    Task { await enable() }
                } label: {
                    HStack(spacing: 6) {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text(isEnabled ? "Update" : "Connect & Enable")
                    }
                    .frame(minWidth: 132)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking || baseURL.isEmpty || apiKey.isEmpty || visibleSections.isEmpty)
            }
        }
        .padding(20)
        .background(.bar)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }

    // MARK: - Helpers

    private func binding(for kind: SectionKind) -> Binding<Bool> {
        Binding(
            get: { visibleSections.contains(kind) },
            set: { isOn in
                if isOn { visibleSections.insert(kind) } else { visibleSections.remove(kind) }
            }
        )
    }

    private func tint(_ kind: SectionKind) -> Color {
        switch kind {
        case .albums: return .blue
        case .timeline: return .orange
        case .people: return .green
        case .places: return .pink
        case .tags: return .purple
        case .favorites: return .red
        }
    }

    // MARK: - Actions

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
            status = .failure("That server address doesn’t look right.")
            return
        }
        let albumCount: Int
        do {
            albumCount = try await ImmichClient(baseURL: url, apiKey: apiKey).listAlbums().count
        } catch {
            status = .failure("Couldn’t connect — check the address and API key.")
            return
        }

        CredentialStore.save(baseURL: baseURL, apiKey: apiKey)
        VisibleSections.save(visibleSections)
        do {
            try await DomainManager.register()
            DomainManager.reloadRoot()
            isEnabled = true
            status = .success("Enabled — find “Findich” in your Finder sidebar (\(albumCount) albums).")
        } catch {
            status = .failure("Connected, but couldn’t enable the Finder location.")
        }
    }

    private func disable() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await DomainManager.unregister()
            CredentialStore.clear()
            isEnabled = false
            status = .idle
        } catch {
            status = .failure("Couldn’t remove the Finder location.")
        }
    }
}
