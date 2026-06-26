import SwiftUI

struct ContentView: View {
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var customHeaders: [CustomHeader] = []
    @State private var showKey = false
    @State private var visibleSections: Set<SectionKind> = Set(SectionKind.allCases)
    @State private var chunking = ChunkingSettings.default
    @State private var isFreeingSpace = false
    @State private var freedMessage: String?
    @State private var selectedTab: AppTab = .setup
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
            TabStrip(selection: $selectedTab)
            Group {
                switch selectedTab {
                case .setup:
                    form
                case .options:
                    optionsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 480, height: 640)
        .task { await loadState() }
    }

    private var optionsTab: some View {
        OptionsTab(
            chunking: $chunking,
            customHeaders: $customHeaders,
            isEnabled: isEnabled,
            isFreeingSpace: isFreeingSpace,
            freedMessage: freedMessage,
            onFreeUpSpace: { Task { await freeUpSpace() } }
        )
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
        let color: Color = if on { .green } else { .secondary }
        let label: String = if on { "Active" } else { "Off" }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
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

                        let keyIcon: String = if showKey { "eye.slash.fill" } else { "eye.fill" }
                        let keyHelp: String = if showKey { "Hide key" } else { "Show key" }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: keyIcon)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(keyHelp)
                    }
                } label: {
                    Label("API Key", systemImage: "key.fill")
                }

                HStack {
                    Spacer()
                    Button("Add custom headers") {
                        selectedTab = .options
                    }
                    .buttonStyle(.link)
                    .font(.callout)
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
                        let actionTitle: String = if isEnabled { "Update" } else { "Connect & Enable" }
                        Text(actionTitle)
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
            customHeaders = credentials.customHeaders
        }
        visibleSections = VisibleSections.load()
        chunking = ChunkingSettings.load()
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
            albumCount = try await ImmichClient(baseURL: url, apiKey: apiKey, customHeaders: customHeaders.asRequestHeaders).listAlbums().count
        } catch {
            status = .failure("Couldn’t connect. Check the address and API key.")
            return
        }

        customHeaders = customHeaders.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        let previous = CredentialStore.load()
        CredentialStore.save(baseURL: baseURL, apiKey: apiKey, customHeaders: customHeaders)
        VisibleSections.save(visibleSections)
        chunking = chunking.clampedToValidSize()
        ChunkingSettings.save(chunking)
        let credentialsChanged = previous?.apiKey != apiKey
            || previous?.baseURL.absoluteString != baseURL
            || previous?.customHeaders != customHeaders
        do {
            if isEnabled && credentialsChanged {
                try await DomainManager.reload()
            } else {
                try await DomainManager.register()
            }
            DomainManager.reloadRoot()
            isEnabled = true
            status = .success("Enabled. Find “Findich” in your Finder sidebar (\(albumCount) albums).")
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

    private func freeUpSpace() async {
        isFreeingSpace = true
        defer { isFreeingSpace = false }
        let count = await SpaceManager.freeUpSpace()
        freedMessage = "Reverted \(count) downloaded files to placeholders."
    }
}
