import SwiftUI
import SSHTunnelCore

struct TunnelMenuView: View {
    @EnvironmentObject private var manager: TunnelManager
    @EnvironmentObject private var shortcutController: GlobalShortcutController
    @State private var draft = TunnelDraft()
    @State private var isAdding = false
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()

                ScrollView {
                    if manager.tunnels.isEmpty {
                        if !isAdding {
                            emptyState
                        }
                    } else {
                        tunnelList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()
                addSection
            }

            if let warning = manager.riskWarning {
                riskWarningOverlay(warning)
            }
        }
        .padding(16)
        .sheet(isPresented: $isShowingSettings) {
            GlobalShortcutSettingsView()
                .environmentObject(shortcutController)
        }
    }

    private func riskWarningOverlay(_ warning: TunnelRiskWarning) -> some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.riskyLocalBindTitle())
                    .font(.headline)
                Text(warning.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button(AppStrings.cancel()) {
                        manager.cancelRiskyOperation()
                    }
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
        .zIndex(10)
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
        LazyVStack(spacing: 10) {
            ForEach(manager.tunnels) { tunnel in
                TunnelRowView(tunnel: tunnel)
                    .environmentObject(manager)
            }
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation {
                        isAdding.toggle()
                    }
                } label: {
                    Label(
                        isAdding ? AppStrings.collapseAddForm() : AppStrings.addTunnel(),
                        systemImage: isAdding ? "chevron.up" : "plus"
                    )
                }

                Spacer()

                Button(role: .destructive) {
                    manager.quitApplication()
                } label: {
                    Label(AppStrings.quit(), systemImage: "power")
                }
                .help(AppStrings.quitHelp())
            }

            if isAdding {
                TunnelFormView(draft: $draft) {
                    manager.addTunnel(draft) {
                        draft = TunnelDraft()
                        isAdding = false
                    }
                }
            }

            if !manager.addError.isEmpty {
                Text(manager.addError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TunnelRowView: View {
    @EnvironmentObject private var manager: TunnelManager
    let tunnel: TunnelConfig
    @State private var isEditing = false
    @State private var editDraft = TunnelDraft()
    @State private var editError = ""

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
                if manager.isManagedProcessRunning(for: tunnel) {
                    Button(AppStrings.stop()) {
                        manager.stop(tunnel)
                    }
                } else {
                    Button(AppStrings.start()) {
                        manager.start(tunnel)
                    }
                }

                if tunnel.openURL != nil {
                    Button(AppStrings.open()) {
                        manager.openURL(for: tunnel)
                    }
                }

                if !manager.isManagedProcessRunning(for: tunnel) {
                    Button {
                        editDraft = TunnelDraft(tunnel: tunnel)
                        editError = ""
                        withAnimation {
                            isEditing.toggle()
                        }
                    } label: {
                        Label(isEditing ? AppStrings.collapseEdit() : AppStrings.edit(), systemImage: "pencil")
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    manager.deleteTunnel(tunnel)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.deleteTunnelHelp())
            }

            if isEditing {
                TunnelFormView(
                    draft: $editDraft,
                    saveTitle: AppStrings.update(),
                    onCancel: {
                        editDraft = TunnelDraft(tunnel: tunnel)
                        editError = ""
                        isEditing = false
                    }
                ) {
                    if !manager.updateTunnel(tunnel, with: editDraft, onSuccess: {
                        editError = ""
                        isEditing = false
                    }) {
                        editError = manager.addError
                    }
                }
            }

            if !editError.isEmpty {
                Text(editError)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
        case .running:
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
}

struct TunnelFormView: View {
    @Binding var draft: TunnelDraft
    var saveTitle: String?
    var onCancel: (() -> Void)?
    let onSave: () -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text(AppStrings.formMode())
                Picker(AppStrings.formMode(), selection: $draft.mode) {
                    Text(AppStrings.modeLocalForward()).tag(TunnelMode.localForward)
                    Text(AppStrings.modeDynamicForward()).tag(TunnelMode.dynamicForward)
                    Text(AppStrings.modeSSHConfig()).tag(TunnelMode.sshConfig)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            GridRow {
                Text(AppStrings.formName())
                TextField(AppStrings.placeholderName(), text: $draft.name)
            }

            if draft.mode.showsSSHHostAndLocalFields {
                GridRow {
                    Text(AppStrings.formSSHHost())
                    TextField(AppStrings.placeholderSSHHost(), text: $draft.sshHost)
                }
                GridRow {
                    Text(draft.mode == .dynamicForward ? AppStrings.formSOCKS() : AppStrings.formLocal())
                    HStack {
                        TextField("127.0.0.1", text: $draft.localHost)
                        TextField(AppStrings.placeholderPort(), text: $draft.localPort)
                            .frame(width: 70)
                    }
                }
            }

            if draft.mode.showsRemoteFields {
                GridRow {
                    Text(AppStrings.formRemote())
                    HStack {
                        TextField("127.0.0.1", text: $draft.remoteHost)
                        TextField(AppStrings.placeholderPort(), text: $draft.remotePort)
                            .frame(width: 70)
                    }
                }
            }

            if draft.mode.showsSSHConfigFields {
                GridRow {
                    Text(AppStrings.modeSSHConfig())
                    TextField(AppStrings.placeholderSSHConfig(), text: $draft.sshConfigName)
                }
            }

            GridRow {
                Text(AppStrings.formOpenURL())
                TextField(AppStrings.placeholderOpenURL(), text: $draft.openURL)
            }
        }
        .textFieldStyle(.roundedBorder)

        HStack {
            if let onCancel {
                Button(AppStrings.cancel()) {
                    onCancel()
                }
            }
            Spacer()
            Button(saveTitle ?? AppStrings.save()) {
                onSave()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
