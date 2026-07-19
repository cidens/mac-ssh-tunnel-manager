import SwiftUI
import SSHTunnelCore

struct TunnelMenuView: View {
    @EnvironmentObject private var manager: TunnelManager
    @EnvironmentObject private var shortcutController: GlobalShortcutController
    @EnvironmentObject private var notificationController: ConnectionNotificationController
    @EnvironmentObject private var loginItemController: LoginItemController
    @State private var editorRequest: TunnelEditorRequest?
    @State private var tunnelPendingScrollID: UUID?
    @State private var isShowingSettings = false
    @State private var isShowingSSHConfigImport = false
    @State private var isShowingConfigurationTransfer = false
    @State private var tunnelPendingDeletion: TunnelConfig?
    @State private var searchQuery = ""
    @State private var selectedTag: String?
    @State private var favoritesOnly = false
    @State private var sortOption: TunnelSortOption = .manual
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()

                filters

                ScrollViewReader { proxy in
                    ScrollView {
                        if manager.tunnels.isEmpty {
                            emptyState
                        } else {
                            tunnelList
                        }
                    }
                    .onChange(of: tunnelPendingScrollID) { _, tunnelID in
                        guard let tunnelID else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(tunnelID, anchor: .bottom)
                            tunnelPendingScrollID = nil
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()
                addSection
            }

            if let warning = manager.riskWarning {
                TunnelRiskWarningOverlay(warning: warning)
                    .environmentObject(manager)
            }

            if let tunnel = tunnelPendingDeletion {
                deleteConfirmationOverlay(tunnel)
            }
        }
        .padding(16)
        .sheet(isPresented: $isShowingSettings) {
            GlobalShortcutSettingsView()
                .environmentObject(shortcutController)
                .environmentObject(notificationController)
                .environmentObject(loginItemController)
        }
        .sheet(isPresented: $isShowingSSHConfigImport) {
            SSHConfigImportView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $isShowingConfigurationTransfer) {
            ConfigurationTransferView()
                .environmentObject(manager)
        }
        .sheet(item: $editorRequest) { request in
            TunnelEditorView(tunnel: request.tunnel) { addedTunnelID in
                editorRequest = nil
                tunnelPendingScrollID = addedTunnelID
            }
            .environmentObject(manager)
        }
        .onChange(of: manager.riskWarning?.id) { _, warningID in
            if warningID != nil {
                isSearchFocused = false
            }
        }
        .onExitCommand {
            if tunnelPendingDeletion != nil {
                tunnelPendingDeletion = nil
            } else if manager.riskWarning != nil {
                manager.cancelRiskyOperation()
            } else {
                isSearchFocused = false
            }
        }
    }

    private func deleteConfirmationOverlay(_ tunnel: TunnelConfig) -> some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.deleteTunnelConfirmationTitle())
                    .font(.headline)
                Text(AppStrings.deleteTunnelConfirmationMessage(name: tunnel.name))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button(AppStrings.cancel()) {
                        tunnelPendingDeletion = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(AppStrings.delete(), role: .destructive) {
                        tunnelPendingDeletion = nil
                        manager.deleteTunnel(tunnel)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary)
            }
            .shadow(radius: 12)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(20)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("SSH Tunnel Manager")
                        .font(.headline)
                    Text(AppVersion.displayText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(AppStrings.headerSubtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(manager.summary.displayText())
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                isShowingSettings = true
            } label: {
                Label(AppStrings.settings(), systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.settingsHelp())
            Button {
                manager.refreshStatuses()
            } label: {
                Label(AppStrings.refresh(), systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.refreshHelp())
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.emptyStateTitle())
                .font(.title3.weight(.semibold))
            Text(AppStrings.emptyStateBody())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }

    private var tunnelList: some View {
        let displayed = manager.displayedTunnels(
            searchQuery: searchQuery,
            selectedTag: selectedTag,
            favoritesOnly: favoritesOnly,
            sort: sortOption
        )
        return LazyVStack(spacing: 10) {
            if displayed.isEmpty {
                Text(AppStrings.noMatchingTunnels())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
            ForEach(displayed) { tunnel in
                TunnelRowView(
                    tunnel: tunnel,
                    onEditRequest: {
                        manager.addError = ""
                        editorRequest = TunnelEditorRequest(tunnel: $0)
                    },
                    onDeleteRequest: {
                        isSearchFocused = false
                        tunnelPendingDeletion = $0
                    },
                    showsManualOrderControls: sortOption == .manual && searchQuery.isEmpty && selectedTag == nil && !favoritesOnly
                )
                    .environmentObject(manager)
                    .id(tunnel.id)
            }
        }
    }

    private var filters: some View {
        let availableTags = manager.availableTags
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(AppStrings.searchTunnels(), text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                Toggle(isOn: $favoritesOnly) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .help(AppStrings.favoritesOnly())
                Picker(AppStrings.sort(), selection: $sortOption) {
                    Text(AppStrings.sortManual()).tag(TunnelSortOption.manual)
                    Text(AppStrings.sortName()).tag(TunnelSortOption.name)
                    Text(AppStrings.sortStatus()).tag(TunnelSortOption.status)
                    Text(AppStrings.sortLastUsed()).tag(TunnelSortOption.lastUsed)
                }
                .labelsHidden()
                .frame(width: 130)
            }
            if !availableTags.isEmpty || selectedTag != nil || !searchQuery.isEmpty || favoritesOnly {
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button(AppStrings.allTags()) { selectedTag = nil }
                                .buttonStyle(.bordered)
                                .tint(selectedTag == nil ? .accentColor : nil)
                            ForEach(availableTags, id: \.self) { tag in
                                Button(tag) {
                                    selectedTag = isSelectedTag(tag) ? nil : tag
                                }
                                .buttonStyle(.bordered)
                                .tint(isSelectedTag(tag) ? .accentColor : nil)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    let count = manager.displayedTunnels(searchQuery: searchQuery, selectedTag: selectedTag, favoritesOnly: favoritesOnly, sort: sortOption).count
                    Text(AppStrings.resultCount(count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedTag != nil || !searchQuery.isEmpty || favoritesOnly {
                        Button(AppStrings.clearFilters()) {
                            searchQuery = ""
                            selectedTag = nil
                            favoritesOnly = false
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func isSelectedTag(_ tag: String) -> Bool {
        selectedTag?.caseInsensitiveCompare(tag) == .orderedSame
    }

    private var addSection: some View {
        HStack {
            Button {
                manager.addError = ""
                editorRequest = TunnelEditorRequest(tunnel: nil)
            } label: {
                Label(AppStrings.addTunnel(), systemImage: "plus")
            }

            Menu {
                Button(AppStrings.importSSHConfig()) {
                    isShowingSSHConfigImport = true
                }
                Button(AppStrings.configurationTransfer()) {
                    isShowingConfigurationTransfer = true
                }
            } label: {
                Label(AppStrings.importActions(), systemImage: "square.and.arrow.down")
            }

            Spacer()

            Button(role: .destructive) {
                manager.quitApplication()
            } label: {
                Label(AppStrings.quit(), systemImage: "power")
            }
            .help(AppStrings.quitHelp())
        }
    }
}

private struct TunnelEditorRequest: Identifiable {
    let id = UUID()
    let tunnel: TunnelConfig?
}

private struct TunnelEditorView: View {
    @EnvironmentObject private var manager: TunnelManager
    let tunnel: TunnelConfig?
    let onDismiss: (UUID?) -> Void
    private let initialDraft: TunnelDraft
    @State private var draft: TunnelDraft
    @State private var expandedRuleID: UUID?
    @State private var rulePendingScrollID: UUID?
    @State private var isConfirmingDiscard = false

    init(tunnel: TunnelConfig?, onDismiss: @escaping (UUID?) -> Void) {
        self.tunnel = tunnel
        self.onDismiss = onDismiss
        let initialDraft = tunnel.map(TunnelDraft.init(tunnel:)) ?? TunnelDraft()
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
        _expandedRuleID = State(initialValue: initialDraft.rules.first?.id)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tunnel == nil
                        ? AppStrings.string("editor.add.title")
                        : AppStrings.string("editor.edit.title"))
                        .font(.title2.weight(.semibold))
                    if let tunnel {
                        Text(tunnel.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        TunnelFormView(
                            draft: $draft,
                            allowsTypeSelection: tunnel == nil,
                            expandedRuleID: $expandedRuleID,
                            onRuleAdded: { ruleID in
                                expandedRuleID = ruleID
                                rulePendingScrollID = ruleID
                            }
                        )
                        .padding(.vertical, 2)
                    }
                    .onChange(of: rulePendingScrollID) { _, ruleID in
                        guard let ruleID else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(ruleID, anchor: .bottom)
                            rulePendingScrollID = nil
                        }
                    }
                }

                Divider()

                if !manager.addError.isEmpty {
                    Text(manager.addError)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button(AppStrings.cancel()) {
                        requestCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(tunnel == nil ? AppStrings.save() : AppStrings.update()) {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)

            if isConfirmingDiscard {
                discardConfirmationOverlay
            }

            if let warning = manager.riskWarning {
                TunnelRiskWarningOverlay(warning: warning)
                    .environmentObject(manager)
            }
        }
        .frame(width: 680, height: 700)
        .onAppear {
            NotificationCenter.default.post(name: .menuPanelModalInteractionDidBegin, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .menuPanelModalInteractionDidEnd, object: nil)
        }
        .onExitCommand {
            if manager.riskWarning != nil {
                manager.cancelRiskyOperation()
            } else if isConfirmingDiscard {
                isConfirmingDiscard = false
            } else {
                requestCancel()
            }
        }
    }

    private var discardConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.string("editor.discard.title"))
                    .font(.headline)
                Text(AppStrings.string("editor.discard.message"))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(AppStrings.string("editor.discard.keepEditing")) {
                        isConfirmingDiscard = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(AppStrings.string("editor.discard.action"), role: .destructive) {
                        dismissEditor()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary)
            }
            .shadow(radius: 12)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(15)
    }

    private func requestCancel() {
        if draft.hasSameEditableContent(as: initialDraft) {
            dismissEditor()
        } else {
            isConfirmingDiscard = true
        }
    }

    private func save() {
        manager.addError = ""
        if let tunnel {
            _ = manager.updateTunnel(tunnel, with: draft) {
                dismissEditor()
            }
        } else {
            _ = manager.addTunnel(draft) {
                dismissEditor(revealing: manager.tunnels.last?.id)
            }
        }
    }

    private func dismissEditor(revealing tunnelID: UUID? = nil) {
        manager.addError = ""
        isConfirmingDiscard = false
        onDismiss(tunnelID)
    }
}

private struct TunnelRiskWarningOverlay: View {
    @EnvironmentObject private var manager: TunnelManager
    let warning: TunnelRiskWarning

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(warning.title)
                    .font(.headline)
                Text(warning.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button(AppStrings.cancel()) {
                        manager.cancelRiskyOperation()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(AppStrings.continueAnyway()) {
                        manager.confirmRiskyOperation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary)
            }
            .shadow(radius: 12)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(20)
    }
}

struct TunnelRowView: View {
    @EnvironmentObject private var manager: TunnelManager
    let tunnel: TunnelConfig
    let onEditRequest: (TunnelConfig) -> Void
    let onDeleteRequest: (TunnelConfig) -> Void
    let showsManualOrderControls: Bool
    @State private var isShowingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tunnel.name)
                        .font(.headline)
                    Text(tunnelSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            HStack {
                Button {
                    manager.toggleFavorite(tunnel)
                } label: {
                    Image(systemName: tunnel.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.favorite())
                if manager.isRunRequested(for: tunnel) {
                    Button(AppStrings.stop()) {
                        manager.stop(tunnel)
                    }
                } else {
                    Button(AppStrings.start()) {
                        manager.start(tunnel)
                    }
                    .disabled(!canStart)
                    .help(canStart ? AppStrings.start() : AppStrings.string("error.noEnabledRules"))
                }

                let openURLs = manager.openURLs(for: tunnel)
                if openURLs.count == 1 {
                    Button(AppStrings.open()) { manager.openURL(openURLs[0]) }
                } else if openURLs.count > 1 {
                    Menu(AppStrings.open()) {
                        ForEach(Array(openURLs.enumerated()), id: \.offset) { index, url in
                            Button("\(index + 1). \(url.absoluteString)") { manager.openURL(url) }
                        }
                    }
                }

                Button {
                    onEditRequest(tunnel)
                } label: {
                    Label(AppStrings.edit(), systemImage: "pencil")
                }

                Button {
                    isShowingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.connectionDetails())
                .accessibilityLabel(AppStrings.connectionDetails())

                if showsManualOrderControls {
                    Button { manager.moveManualOrder(tunnel, direction: -1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help(AppStrings.moveUp())
                    Button { manager.moveManualOrder(tunnel, direction: 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help(AppStrings.moveDown())
                }

                Spacer()

                Button(role: .destructive) {
                    onDeleteRequest(tunnel)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.deleteTunnelHelp())
            }

            if tunnel.mode != .sshConfig && !tunnel.effectiveRules.contains(where: \.isEnabled) {
                Text(AppStrings.string("error.noEnabledRules"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !tunnel.tags.isEmpty {
                Text(tunnel.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let error = manager.lastError(for: tunnel)
            if !error.isEmpty {
                Text(error)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $isShowingDetails) {
            TunnelConnectionDetailsView(tunnel: tunnel)
                .environmentObject(manager)
        }
    }

    private var statusBadge: some View {
        let status = manager.status(for: tunnel)
        return Text(status.displayText())
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color(for: status).opacity(0.15))
            .foregroundStyle(color(for: status))
            .clipShape(Capsule())
    }

    private func color(for status: TunnelRuntimeStatus) -> Color {
        switch status {
        case .stopped:
            return .secondary
        case .connecting, .waitingForNetwork, .waitingToReconnect, .running:
            return .orange
        case .portListening:
            return .green
        case .externalListening:
            return .orange
        case .failed:
            return .red
        }
    }

    private var tunnelSummary: String {
        AppStrings.tunnelSummary(tunnel)
    }

    private var canStart: Bool {
        tunnel.mode == .sshConfig || tunnel.effectiveRules.contains(where: \.isEnabled)
    }
}

struct TunnelConnectionDetailsView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss
    let tunnel: TunnelConfig
    @State private var didCopyDiagnostics = false

    var body: some View {
        let details = manager.connectionDetails(for: tunnel)
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.connectionDetails())
                .font(.title2.weight(.semibold))
            Text(tunnel.name)
                .font(.headline)
            Text(manager.status(for: tunnel).displayText())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                detailRow(
                    AppStrings.diagnosticStatusChanged(),
                    details.statusChangedAt.formatted(date: .abbreviated, time: .standard)
                )
                detailRow(
                    AppStrings.diagnosticExitCode(),
                    details.exitCode.map(String.init) ?? AppStrings.diagnosticNone()
                )
                detailRow(AppStrings.diagnosticRetryCount(), String(details.retryCount))
                detailRow(
                    AppStrings.diagnosticNextRetry(),
                    details.nextRetryAt?.formatted(date: .abbreviated, time: .standard)
                        ?? AppStrings.diagnosticNone()
                )
                detailRow(
                    AppStrings.diagnosticErrorCategory(),
                    details.errorCategory.map { AppStrings.failureCategory($0) }
                        ?? AppStrings.diagnosticNone()
                )
                detailRow(
                    AppStrings.diagnosticErrorSummary(),
                    details.errorSummary.isEmpty ? AppStrings.diagnosticNone() : details.errorSummary
                )
            }

            Divider()

            HStack {
                Button(didCopyDiagnostics ? AppStrings.diagnosticsCopied() : AppStrings.copyDiagnostics()) {
                    manager.copyDiagnostics(for: tunnel)
                    didCopyDiagnostics = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        didCopyDiagnostics = false
                    }
                }
                Spacer()
                Button(AppStrings.close()) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

struct TunnelFormView: View {
    @Binding var draft: TunnelDraft
    var allowsTypeSelection = false
    @Binding var expandedRuleID: UUID?
    var onRuleAdded: ((UUID) -> Void)?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text(AppStrings.string("form.configurationType"))
                if allowsTypeSelection {
                    Picker(AppStrings.string("form.configurationType"), selection: $draft.configurationKind) {
                        Text(AppStrings.string("configuration.type.connectionGroup"))
                            .tag(TunnelConfigurationKind.connectionGroup)
                        Text(AppStrings.string("configuration.type.sshConfigReference"))
                            .tag(TunnelConfigurationKind.sshConfigReference)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else {
                    Text(draft.configurationKind == .connectionGroup
                        ? AppStrings.string("configuration.type.connectionGroup")
                        : AppStrings.string("configuration.type.sshConfigReference"))
                        .foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text(AppStrings.formName())
                TextField(AppStrings.placeholderName(), text: $draft.name)
            }

            if draft.configurationKind == .connectionGroup {
                GridRow {
                    Text(AppStrings.formSSHHost())
                    TextField(AppStrings.placeholderSSHHost(), text: $draft.sshHost)
                }
            } else {
                GridRow {
                    Text(AppStrings.string("form.sshConfigReference"))
                    TextField(AppStrings.placeholderSSHConfig(), text: $draft.sshConfigName)
                }
                GridRow {
                    Text(AppStrings.formOpenURL())
                    TextField(AppStrings.placeholderOpenURL(), text: $draft.openURL)
                }
            }
            GridRow {
                Text(AppStrings.formTags())
                TextField(AppStrings.placeholderTags(), text: $draft.tags)
            }
        }
        .textFieldStyle(.roundedBorder)

        if draft.configurationKind == .connectionGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppStrings.string("form.rules.title"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        let rule = TunnelRuleDraft()
                        var rules = draft.rules
                        rules.append(rule)
                        draft.rules = rules
                        onRuleAdded?(rule.id)
                    } label: {
                        Label(AppStrings.string("form.rule.add"), systemImage: "plus")
                    }
                    .disabled(!draft.canAddRule)
                    .help(draft.canAddRule
                        ? AppStrings.string("form.rule.add")
                        : draft.hasReachedRuleLimit
                            ? AppStrings.format("form.rule.limit", TunnelConfig.maximumRuleCount)
                            : AppStrings.string("form.rule.completeFirst"))
                }
                Text(!draft.canAddRule && !draft.hasReachedRuleLimit
                    ? AppStrings.string("form.rule.completeFirst")
                    : draft.hasReachedRuleLimit
                        ? AppStrings.format("form.rule.limit", TunnelConfig.maximumRuleCount)
                        : AppStrings.string("form.rules.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(draft.rules) { rule in
                    let ruleID = rule.id
                    let index = draft.rules.firstIndex(where: { $0.id == ruleID }) ?? 0
                    TunnelRuleDraftView(
                        rule: ruleBinding(for: ruleID, fallback: rule),
                        index: index,
                        isExpanded: expandedRuleID == ruleID,
                        canDelete: draft.rules.count > 1,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < draft.rules.count
                    ) {
                        expandedRuleID = expandedRuleID == ruleID ? nil : ruleID
                    } onDelete: {
                        if draft.removeRule(id: ruleID), expandedRuleID == ruleID {
                            expandedRuleID = draft.rules.first?.id
                        }
                    } onMove: { direction in
                        var rules = draft.rules
                        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
                        let target = index + direction
                        guard rules.indices.contains(target) else { return }
                        rules.swapAt(index, target)
                        draft.rules = rules
                    }
                    .id(ruleID)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.formAutomation())
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(AppStrings.formAutoStart(), isOn: $draft.isAutoStartEnabled)
                        .toggleStyle(.checkbox)
                    Text(AppStrings.autoStartHelp())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(AppStrings.formAutoReconnect(), isOn: $draft.isAutoReconnectEnabled)
                        .toggleStyle(.checkbox)
                    Text(AppStrings.autoReconnectHelp())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ruleBinding(for ruleID: UUID, fallback: TunnelRuleDraft) -> Binding<TunnelRuleDraft> {
        Binding(
            get: {
                draft.rules.first(where: { $0.id == ruleID }) ?? fallback
            },
            set: { updatedRule in
                var rules = draft.rules
                guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
                rules[index] = updatedRule
                draft.rules = rules
            }
        )
    }
}

private struct TunnelRuleDraftView: View {
    @Binding var rule: TunnelRuleDraft
    let index: Int
    let isExpanded: Bool
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggleExpansion: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onToggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.string(isExpanded ? "form.rule.collapse" : "form.rule.expand"))
                .accessibilityLabel(AppStrings.string(isExpanded ? "form.rule.collapse" : "form.rule.expand"))
                Toggle(AppStrings.string("form.rule.enabled"), isOn: $rule.isEnabled)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Text("\(index + 1). \(AppStrings.compactModeName(rule.mode))")
                    .font(.callout.weight(.semibold))
                Text(rule.compactEndpointSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !rule.hasRequiredFields {
                    Text(AppStrings.string("form.rule.incomplete"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button { onMove(-1) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                    .help(AppStrings.moveUp())
                Button { onMove(1) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
                    .help(AppStrings.moveDown())
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(!canDelete)
                    .help(AppStrings.string("form.rule.delete"))
            }

            if isExpanded {
                Picker(AppStrings.formMode(), selection: $rule.mode) {
                    Text(AppStrings.compactModeName(.localForward)).tag(TunnelMode.localForward)
                    Text(AppStrings.compactModeName(.remoteForward)).tag(TunnelMode.remoteForward)
                    Text(AppStrings.compactModeName(.dynamicForward)).tag(TunnelMode.dynamicForward)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack {
                    Text(rule.mode == .remoteForward
                        ? AppStrings.formLocalTarget()
                        : rule.mode == .dynamicForward ? AppStrings.formSOCKS() : AppStrings.formLocal())
                        .frame(width: 95, alignment: .leading)
                    TextField("127.0.0.1", text: $rule.localHost)
                    TextField(AppStrings.placeholderPort(), text: $rule.localPort)
                        .frame(width: 70)
                }
                if rule.mode != .dynamicForward {
                    HStack {
                        Text(rule.mode == .remoteForward ? AppStrings.formRemoteListener() : AppStrings.formRemote())
                            .frame(width: 95, alignment: .leading)
                        TextField("127.0.0.1", text: $rule.remoteHost)
                        TextField(AppStrings.placeholderPort(), text: $rule.remotePort)
                            .frame(width: 70)
                    }
                }
                HStack {
                    Text(AppStrings.formOpenURL())
                        .frame(width: 95, alignment: .leading)
                    TextField(AppStrings.placeholderOpenURL(), text: $rule.openURL)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(8)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
