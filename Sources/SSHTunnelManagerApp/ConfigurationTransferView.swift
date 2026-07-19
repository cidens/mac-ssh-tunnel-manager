import AppKit
import SSHTunnelCore
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationTransferView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<TunnelConfig.ID>()
    @State private var document: TunnelConfigurationDocument?
    @State private var strategy = TunnelImportConflictStrategy.skip
    @State private var preview: TunnelImportPreview?
    @State private var message = ""
    @State private var isError = false
    @State private var filePanelStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.configurationTransferTitle())
                .font(.title2.weight(.semibold))

            GroupBox(AppStrings.configurationExportTitle()) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(AppStrings.configurationExportSelection(selectedIDs.count, manager.tunnels.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(AppStrings.selectAll()) {
                            selectedIDs = Set(manager.tunnels.map(\.id))
                        }
                        .buttonStyle(.borderless)
                        Button(AppStrings.clearSelection()) {
                            selectedIDs.removeAll()
                        }
                        .buttonStyle(.borderless)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(manager.tunnels) { tunnel in
                                Toggle(isOn: selectionBinding(for: tunnel.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tunnel.name)
                                        Text(AppStrings.tunnelSummary(tunnel))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 150)

                    Button(AppStrings.configurationExportButton()) {
                        exportSelection()
                    }
                    .disabled(selectedIDs.isEmpty || filePanelStatus != nil)
                    if selectedIDs.isEmpty {
                        Text(AppStrings.configurationExportRequiresSelection())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox(AppStrings.configurationImportTitle()) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(AppStrings.configurationChooseFile()) {
                            chooseImportFile()
                        }
                        .disabled(filePanelStatus != nil)
                        if let document {
                            Text(AppStrings.configurationImportSource(document.appVersion, document.configs.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if document != nil {
                        Picker(AppStrings.configurationConflictStrategy(), selection: $strategy) {
                            Text(AppStrings.configurationConflictSkip()).tag(TunnelImportConflictStrategy.skip)
                            Text(AppStrings.configurationConflictReplace()).tag(TunnelImportConflictStrategy.replace)
                            Text(AppStrings.configurationConflictCopy()).tag(TunnelImportConflictStrategy.copy)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: strategy) { _, _ in refreshPreview() }

                        if let preview {
                            Text(AppStrings.configurationImportSummary(
                                preview.importedCount,
                                preview.replacedCount,
                                preview.copiedCount,
                                preview.skippedCount
                            ))
                            .font(.caption)

                            ForEach(Array(preview.issues.enumerated()), id: \.offset) { _, issue in
                                Label(issueText(issue), systemImage: issue.isBlocking ? "xmark.octagon" : "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(issue.isBlocking ? .red : .orange)
                            }

                            Text(AppStrings.configurationImportSafetyNote())
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button(AppStrings.configurationImportButton()) {
                                if manager.commitConfigurationImport(preview) {
                                    message = AppStrings.configurationImportSucceeded()
                                    isError = false
                                    document = nil
                                    self.preview = nil
                                } else {
                                    message = manager.addError
                                    isError = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!preview.canCommit)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if let filePanelStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(filePanelStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(AppStrings.close()) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            if selectedIDs.isEmpty {
                selectedIDs = Set(manager.tunnels.map(\.id))
            }
        }
    }

    private func selectionBinding(for id: TunnelConfig.ID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { selected in
                if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
            }
        )
    }

    private func exportSelection() {
        do {
            let data = try manager.exportConfigurationData(selectedIDs: selectedIDs)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "ssh-tunnel-manager-configs.json"
            present(panel, status: AppStrings.configurationOpeningExportPanel()) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    message = AppStrings.configurationExportSucceeded(selectedIDs.count)
                    isError = false
                } catch {
                    message = AppStrings.configurationExportFailed(error.localizedDescription)
                    isError = true
                }
            }
        } catch {
            message = AppStrings.configurationExportFailed(error.localizedDescription)
            isError = true
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        present(panel, status: AppStrings.configurationOpeningImportPanel()) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize, size > TunnelConfigurationTransfer.maximumFileSize {
                    throw TunnelConfigurationTransferError.fileTooLarge(
                        maximumBytes: TunnelConfigurationTransfer.maximumFileSize
                    )
                }
                let decoded = try manager.decodeConfigurationImport(Data(contentsOf: url))
                document = decoded
                refreshPreview()
                message = ""
                isError = false
            } catch {
                document = nil
                preview = nil
                message = AppStrings.configurationImportFailed(error.localizedDescription)
                isError = true
            }
        }
    }

    private func present(
        _ panel: NSSavePanel,
        status: String,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        filePanelStatus = status
        NotificationCenter.default.post(name: .menuPanelModalInteractionDidBegin, object: nil)
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            filePanelStatus = nil
            NotificationCenter.default.post(name: .menuPanelModalInteractionDidEnd, object: nil)
            completion(response)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private func refreshPreview() {
        guard let document else { return }
        preview = manager.previewConfigurationImport(document, strategy: strategy)
    }

    private func issueText(_ issue: TunnelImportIssue) -> String {
        switch issue {
        case .duplicateIdentifier(let id):
            return AppStrings.configurationDuplicateIdentifier(id.uuidString)
        case .duplicateName(let name):
            return AppStrings.configurationDuplicateName(name)
        case .localEndpointConflict(let host, let port):
            return AppStrings.configurationPortConflict(host, port)
        case .exposedListener(let host, let port):
            return AppStrings.configurationExposureWarning(host, port)
        }
    }
}
