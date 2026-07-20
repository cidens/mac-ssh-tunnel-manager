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
    @State private var tagBatchConfirmation: TagBatchConfirmation?
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
            TunnelEditorView(
                tunnel: request.tunnel,
                initialPortConflict: request.initialPortConflict
            ) { addedTunnelID in
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
        .confirmationDialog(
            tagBatchConfirmation.map(tagBatchConfirmationTitle) ?? "",
            isPresented: Binding(
                get: { tagBatchConfirmation != nil },
                set: { if !$0 { tagBatchConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation = tagBatchConfirmation {
                if confirmation.action == .stop {
                    Button(
                        AppStrings.format("tagBatch.action.stop", confirmation.count),
                        role: .destructive
                    ) {
                        performTagBatchAction(confirmation)
                    }
                } else {
                    Button(AppStrings.format("tagBatch.action.start", confirmation.count)) {
                        performTagBatchAction(confirmation)
                    }
                }
            }
            Button(AppStrings.cancel(), role: .cancel) {
                tagBatchConfirmation = nil
            }
        } message: {
            if let confirmation = tagBatchConfirmation {
                Text(tagBatchConfirmationMessage(confirmation))
            }
        }
        .onExitCommand {
            if tagBatchConfirmation != nil {
                tagBatchConfirmation = nil
            } else if tunnelPendingDeletion != nil {
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
                    onPortRecommendationRequest: { tunnel, conflict in
                        manager.addError = ""
                        editorRequest = TunnelEditorRequest(
                            tunnel: tunnel,
                            initialPortConflict: conflict
                        )
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
            if let selectedTag {
                TagBatchControlsView(
                    snapshot: manager.tagGroupSnapshot(for: selectedTag),
                    onRequestAction: { action, count in
                        isSearchFocused = false
                        tagBatchConfirmation = TagBatchConfirmation(
                            action: action,
                            tag: selectedTag,
                            count: count
                        )
                    }
                )
                .environmentObject(manager)
            }
        }
    }

    private func isSelectedTag(_ tag: String) -> Bool {
        selectedTag?.caseInsensitiveCompare(tag) == .orderedSame
    }

    private func tagBatchConfirmationTitle(_ confirmation: TagBatchConfirmation) -> String {
        AppStrings.format(
            confirmation.action == .start
                ? "tagBatch.confirm.start.title"
                : "tagBatch.confirm.stop.title",
            confirmation.tag
        )
    }

    private func tagBatchConfirmationMessage(_ confirmation: TagBatchConfirmation) -> String {
        AppStrings.format(
            confirmation.action == .start
                ? "tagBatch.confirm.start.message"
                : "tagBatch.confirm.stop.message",
            confirmation.count
        )
    }

    private func performTagBatchAction(_ confirmation: TagBatchConfirmation) {
        tagBatchConfirmation = nil
        switch confirmation.action {
        case .start:
            manager.startAllTunnels(withTag: confirmation.tag)
        case .stop:
            manager.stopAllTunnels(withTag: confirmation.tag)
        }
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

private struct TagBatchConfirmation: Identifiable {
    let id = UUID()
    let action: TagBatchAction
    let tag: String
    let count: Int
}

private struct TagBatchControlsView: View {
    @EnvironmentObject private var manager: TunnelManager
    let snapshot: TagGroupSnapshot
    let onRequestAction: (TagBatchAction, Int) -> Void

    private var matchingOperation: TagBatchOperationState? {
        guard let operation = manager.tagBatchOperation,
              TagGroupSnapshot.comparisonKey(operation.tag)
                == TagGroupSnapshot.comparisonKey(snapshot.tag) else {
            return nil
        }
        return operation
    }

    private var hasRunningOperation: Bool {
        manager.tagBatchOperation?.isRunning == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(snapshot.tag, systemImage: "tag.fill")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(AppStrings.format(
                    "tagBatch.summary",
                    snapshot.totalCount,
                    snapshot.runningCount,
                    snapshot.pendingCount,
                    snapshot.failedCount,
                    snapshot.stoppedCount
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    onRequestAction(.start, snapshot.totalCount)
                } label: {
                    Label(
                        AppStrings.format("tagBatch.action.start", snapshot.totalCount),
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(snapshot.totalCount == 0 || hasRunningOperation)
                .help(AppStrings.format(
                    "tagBatch.help.start",
                    snapshot.totalCount,
                    snapshot.tag
                ))
                .accessibilityLabel(AppStrings.format("tagBatch.action.start", snapshot.totalCount))

                Button(role: .destructive) {
                    onRequestAction(.stop, snapshot.totalCount)
                } label: {
                    Label(
                        AppStrings.format("tagBatch.action.stop", snapshot.totalCount),
                        systemImage: "stop.fill"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    snapshot.totalCount == 0
                        || (manager.tagBatchOperation?.isRunning == true
                            && manager.tagBatchOperation?.action == .stop)
                )
                .help(AppStrings.format(
                    "tagBatch.help.stop",
                    snapshot.totalCount,
                    snapshot.tag
                ))
                .accessibilityLabel(AppStrings.format("tagBatch.action.stop", snapshot.totalCount))
            }

            if let operation = matchingOperation {
                if operation.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppStrings.format(
                            operation.action == .start
                                ? "tagBatch.progress.start"
                                : "tagBatch.progress.stop",
                            operation.totalCount
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else if let result = operation.result {
                    TagBatchResultView(result: result)
                        .environmentObject(manager)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TagBatchResultView: View {
    @EnvironmentObject private var manager: TunnelManager
    let result: TagBatchResult
    @State private var showsDetails = false

    var body: some View {
        let issues = result.issues
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(AppStrings.format(
                    result.action == .start
                        ? "tagBatch.result.start"
                        : "tagBatch.result.stop",
                    result.action == .start ? result.startedCount : result.stoppedCount,
                    result.skippedCount,
                    result.failedCount
                ))
                .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    manager.clearTagBatchResult()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.string("tagBatch.result.dismiss"))
                .accessibilityLabel(AppStrings.string("tagBatch.result.dismiss"))
            }

            if !issues.isEmpty {
                DisclosureGroup(
                    AppStrings.string("tagBatch.result.details"),
                    isExpanded: $showsDetails
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(issues) { issue in
                                Text("\(issue.name)：\(issue.reason ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(issue.kind == .failed ? .red : .secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                    .padding(.top, 3)
                }
                .font(.caption)
            }
        }
    }
}

private struct TunnelEditorRequest: Identifiable {
    let id = UUID()
    let tunnel: TunnelConfig?
    let initialPortConflict: LocalPortEndpoint?

    init(tunnel: TunnelConfig?, initialPortConflict: LocalPortEndpoint? = nil) {
        self.tunnel = tunnel
        self.initialPortConflict = initialPortConflict
    }
}

private struct TunnelEditorView: View {
    @EnvironmentObject private var manager: TunnelManager
    let tunnel: TunnelConfig?
    let initialPortConflict: LocalPortEndpoint?
    let onDismiss: (UUID?) -> Void
    private let initialDraft: TunnelDraft
    @State private var draft: TunnelDraft
    @State private var expandedRuleID: UUID?
    @State private var rulePendingScrollID: UUID?
    @State private var isConfirmingDiscard = false
    @State private var portRecommendation: LocalPortRecommendationPresentation?
    @State private var portRecommendationTask: Task<Void, Never>?
    @State private var didHandleInitialPortConflict = false

    init(
        tunnel: TunnelConfig?,
        initialPortConflict: LocalPortEndpoint? = nil,
        onDismiss: @escaping (UUID?) -> Void
    ) {
        self.tunnel = tunnel
        self.initialPortConflict = initialPortConflict
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
                            portRecommendation: portRecommendation,
                            onRecommendLocalPort: requestPortRecommendation,
                            onUseRecommendedLocalPort: applyRecommendedLocalPort,
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(manager.addError)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if let conflict = manager.validationPortConflict,
                           let rule = recommendationRule(matching: conflict) {
                            Button(AppStrings.string("portRecommendation.action")) {
                                requestPortRecommendation(rule.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
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
            handleInitialPortConflictIfNeeded()
        }
        .onDisappear {
            portRecommendationTask?.cancel()
            NotificationCenter.default.post(name: .menuPanelModalInteractionDidEnd, object: nil)
        }
        .onChange(of: draft.rules) { _, _ in
            guard portRecommendation != nil else { return }
            portRecommendationTask?.cancel()
            portRecommendationTask = nil
            portRecommendation = nil
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
        manager.clearValidationPortConflict()
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
        manager.clearValidationPortConflict()
        portRecommendationTask?.cancel()
        isConfirmingDiscard = false
        onDismiss(tunnelID)
    }

    private func handleInitialPortConflictIfNeeded() {
        guard !didHandleInitialPortConflict, let initialPortConflict else { return }
        didHandleInitialPortConflict = true
        guard let rule = recommendationRule(matching: initialPortConflict) else { return }
        expandedRuleID = rule.id
        requestPortRecommendation(rule.id)
    }

    private func recommendationRule(matching endpoint: LocalPortEndpoint) -> TunnelRuleDraft? {
        draft.rules.first { rule in
            guard rule.mode == .localForward || rule.mode == .dynamicForward,
                  Int(rule.localPort.trimmingCharacters(in: .whitespacesAndNewlines)) == endpoint.port else {
                return false
            }
            return LocalPortOccupancyIndex.hostsOverlap(rule.localHost, endpoint.host)
        }
    }

    private func requestPortRecommendation(_ ruleID: UUID) {
        guard let rule = draft.rules.first(where: { $0.id == ruleID }),
              let fingerprint = rule.localPortRecommendationFingerprint else {
            return
        }
        portRecommendationTask?.cancel()
        manager.clearValidationPortConflict()
        portRecommendation = LocalPortRecommendationPresentation(
            fingerprint: fingerprint,
            phase: .loading
        )
        let draftSnapshot = draft
        portRecommendationTask = Task {
            do {
                let port = try await manager.recommendedLocalPort(
                    for: fingerprint,
                    in: draftSnapshot,
                    editingTunnelID: tunnel?.id
                )
                guard !Task.isCancelled,
                      draft.rules.first(where: { $0.id == ruleID })?
                        .localPortRecommendationFingerprint == fingerprint else {
                    return
                }
                portRecommendation = LocalPortRecommendationPresentation(
                    fingerprint: fingerprint,
                    phase: .suggested(port)
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                portRecommendation = LocalPortRecommendationPresentation(
                    fingerprint: fingerprint,
                    phase: .failed(error.localizedDescription)
                )
            }
        }
    }

    private func applyRecommendedLocalPort(ruleID: UUID, port: Int) {
        portRecommendationTask?.cancel()
        portRecommendationTask = nil
        portRecommendation = nil
        if draft.applyRecommendedLocalPort(port, to: ruleID) {
            manager.addError = ""
            manager.clearValidationPortConflict()
        }
    }
}

private struct LocalPortRecommendationPresentation: Equatable {
    enum Phase: Equatable {
        case loading
        case suggested(Int)
        case failed(String)
    }

    let fingerprint: LocalPortRecommendationFingerprint
    let phase: Phase
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
    let onPortRecommendationRequest: (TunnelConfig, LocalPortEndpoint) -> Void
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
                HStack(spacing: 6) {
                    statusBadge
                    healthStatusBadge
                }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if let conflict = manager.localPortConflict(for: tunnel) {
                        Button(AppStrings.string("portRecommendation.action")) {
                            onPortRecommendationRequest(tunnel, conflict)
                        }
                        .buttonStyle(.bordered)
                    }
                }
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

    @ViewBuilder
    private var healthStatusBadge: some View {
        let phase = manager.healthAggregatePhase(for: tunnel)
        if phase != .notConfigured {
            Label(AppStrings.healthPhase(phase), systemImage: healthSystemImage(for: phase))
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(healthColor(for: phase).opacity(0.15))
                .foregroundStyle(healthColor(for: phase))
                .clipShape(Capsule())
        }
    }

    private func healthColor(for phase: TunnelHealthAggregatePhase) -> Color {
        switch phase {
        case .notConfigured, .waiting: return .secondary
        case .healthy: return .green
        case .unhealthy: return .red
        }
    }

    private func healthSystemImage(for phase: TunnelHealthAggregatePhase) -> String {
        switch phase {
        case .notConfigured, .waiting: return "heart.text.square"
        case .healthy: return "heart.text.square.fill"
        case .unhealthy: return "exclamationmark.heart.fill"
        }
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
        let healthDetails = manager.healthCheckDetails(for: tunnel)
        ScrollView {
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

                if !healthDetails.isEmpty {
                    Divider()
                    Text(AppStrings.string("health.details.title"))
                        .font(.headline)
                    ForEach(healthDetails) { detail in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(AppStrings.format(
                                    "health.details.rule",
                                    detail.ruleNumber,
                                    AppStrings.healthKind(detail.kind)
                                ))
                                .font(.caption.weight(.semibold))
                                Spacer()
                                Text(AppStrings.healthPhase(detail.state.phase))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(detail.state.phase == .unhealthy ? .red : .secondary)
                            }
                            detailRow(
                                AppStrings.string("health.details.lastChecked"),
                                detail.state.lastCheckedAt?.formatted(date: .abbreviated, time: .standard)
                                    ?? AppStrings.diagnosticNone()
                            )
                            if let category = detail.state.failureCategory {
                                detailRow(
                                    AppStrings.string("health.details.failure"),
                                    AppStrings.healthFailureCategory(category)
                                )
                            }
                        }
                    }
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
        }
        .frame(width: 420, height: 600)
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

private struct TunnelFormView: View {
    @Binding var draft: TunnelDraft
    var allowsTypeSelection = false
    @Binding var expandedRuleID: UUID?
    var portRecommendation: LocalPortRecommendationPresentation?
    var onRecommendLocalPort: ((UUID) -> Void)?
    var onUseRecommendedLocalPort: ((UUID, Int) -> Void)?
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
                        canMoveDown: index + 1 < draft.rules.count,
                        portRecommendation: portRecommendation?.fingerprint.ruleID == ruleID
                            ? portRecommendation
                            : nil,
                        onRecommendLocalPort: { onRecommendLocalPort?(ruleID) },
                        onUseRecommendedLocalPort: { port in
                            onUseRecommendedLocalPort?(ruleID, port)
                        }
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
    let portRecommendation: LocalPortRecommendationPresentation?
    let onRecommendLocalPort: () -> Void
    let onUseRecommendedLocalPort: (Int) -> Void
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
                if rule.healthCheck.isEnabled {
                    Text(AppStrings.healthKind(rule.healthCheck.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        ruleFieldLabel(rule.mode == .remoteForward
                            ? AppStrings.formLocalTarget()
                            : rule.mode == .dynamicForward ? AppStrings.formSOCKS() : AppStrings.formLocal())
                        TextField("127.0.0.1", text: $rule.localHost)
                            .frame(maxWidth: .infinity)
                        RulePortField(
                            text: $rule.localPort,
                            showsRecommendation: rule.mode == .localForward || rule.mode == .dynamicForward,
                            isRecommendationLoading: portRecommendation?.phase == .loading,
                            isRecommendationDisabled: rule.localHost
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty,
                            onRecommend: onRecommendLocalPort
                        )
                    }

                    if let portRecommendation {
                        GridRow {
                            Color.clear
                                .frame(width: 0, height: 0)
                                .accessibilityHidden(true)
                            recommendationStatus(for: portRecommendation)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear
                                .frame(width: 0, height: 0)
                                .accessibilityHidden(true)
                        }
                    }

                    if rule.mode != .dynamicForward {
                        GridRow {
                            ruleFieldLabel(rule.mode == .remoteForward
                                ? AppStrings.formRemoteListener()
                                : AppStrings.formRemote())
                            TextField("127.0.0.1", text: $rule.remoteHost)
                                .frame(maxWidth: .infinity)
                            RulePortField(text: $rule.remotePort)
                        }
                    }

                    GridRow {
                        ruleFieldLabel(AppStrings.formOpenURL())
                        TextField(AppStrings.placeholderOpenURL(), text: $rule.openURL)
                            .frame(maxWidth: .infinity)
                        Color.clear
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)

                if rule.mode == .localForward || rule.mode == .dynamicForward {
                    healthCheckEditor
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(8)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var healthCheckEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(AppStrings.string("health.form.enabled"), isOn: $rule.healthCheck.isEnabled)
                .toggleStyle(.checkbox)
            if rule.healthCheck.isEnabled {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        ruleFieldLabel(AppStrings.string("health.form.kind"))
                        if rule.mode == .dynamicForward {
                            Text(AppStrings.healthKind(.socks5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker(AppStrings.string("health.form.kind"), selection: $rule.healthCheck.kind) {
                                Text(AppStrings.healthKind(.tcp)).tag(TunnelHealthCheckKind.tcp)
                                Text(AppStrings.healthKind(.http)).tag(TunnelHealthCheckKind.http)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
                    }
                    if rule.healthCheck.kind == .http {
                        GridRow {
                            ruleFieldLabel(AppStrings.string("health.form.url"))
                            TextField(AppStrings.string("health.form.url.placeholder"), text: $rule.healthCheck.url)
                                .frame(maxWidth: .infinity)
                            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
                        }
                    }
                    GridRow {
                        ruleFieldLabel(AppStrings.string("health.form.interval"))
                        TextField("30", text: $rule.healthCheck.interval)
                            .frame(maxWidth: .infinity)
                        Text(AppStrings.string("health.form.seconds"))
                            .frame(width: 96, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        ruleFieldLabel(AppStrings.string("health.form.timeout"))
                        TextField("3", text: $rule.healthCheck.timeout)
                            .frame(maxWidth: .infinity)
                        Text(AppStrings.string("health.form.seconds"))
                            .frame(width: 96, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(AppStrings.string("health.form.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func recommendationStatus(for presentation: LocalPortRecommendationPresentation) -> some View {
        switch presentation.phase {
        case .loading:
            Text(AppStrings.string("portRecommendation.loading"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .suggested(let port):
            HStack(spacing: 8) {
                Text(AppStrings.format("portRecommendation.suggested", port))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(AppStrings.format("portRecommendation.use", port)) {
                    onUseRecommendedLocalPort(port)
                }
                .buttonStyle(.bordered)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func ruleFieldLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: 95, alignment: .leading)
    }
}

private struct RulePortField: View {
    @Binding var text: String
    var showsRecommendation = false
    var isRecommendationLoading = false
    var isRecommendationDisabled = false
    var onRecommend: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(AppStrings.placeholderPort(), text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .layoutPriority(1)

            if showsRecommendation {
                Button(action: onRecommend) {
                    Group {
                        if isRecommendationLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(isRecommendationDisabled || isRecommendationLoading)
                .help(AppStrings.string("portRecommendation.action"))
                .accessibilityLabel(AppStrings.string("portRecommendation.action"))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, showsRecommendation ? 4 : 8)
        .padding(.vertical, 4)
        .frame(width: 96)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isFocused ? 2 : 1
                )
        }
    }
}
