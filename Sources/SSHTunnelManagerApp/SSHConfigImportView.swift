import SSHTunnelCore
import SwiftUI

struct SSHConfigImportView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = SSHConfigImportController()
    @State private var manualAlias = ""
    @State private var isManualAliasExpanded = false
    @State private var didLoad = false
    @State private var showsMatchExecConfirmation = false
    @State private var showsRiskConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.importSSHConfigTitle())
                .font(.title2.weight(.semibold))
            Text(AppStrings.importSSHConfigSubtitle())
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            manualAliasSection

            if controller.isDiscovering {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(AppStrings.importScanning())
                        .foregroundStyle(.secondary)
                }
            } else {
                discoveryIssues
                selectionToolbar
                candidateList
            }

            if !manager.addError.isEmpty {
                Text(manager.addError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            actionBar
        }
        .padding(20)
        .frame(width: 560, height: 620, alignment: .top)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            controller.load(existingAliases: manager.existingSSHConfigAliases)
        }
        .alert(AppStrings.importMatchExecTitle(), isPresented: $showsMatchExecConfirmation) {
            Button(AppStrings.cancel(), role: .cancel) {}
            Button(AppStrings.continueAnyway(), role: .destructive) {
                controller.approveMatchExec()
                Task { await controller.previewSelected() }
            }
        } message: {
            Text(AppStrings.importMatchExecMessage())
        }
        .alert(AppStrings.importRiskTitle(), isPresented: $showsRiskConfirmation) {
            Button(AppStrings.cancel(), role: .cancel) {}
            Button(AppStrings.continueAnyway(), role: .destructive) {
                importSelectedAliases()
            }
        } message: {
            Text(AppStrings.importRiskMessage())
        }
    }

    private var manualAliasSection: some View {
        DisclosureGroup(isExpanded: $isManualAliasExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.importManualAliasHelp())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField(AppStrings.importManualAliasPlaceholder(), text: $manualAlias)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addManualAlias)
                    Button(AppStrings.importAddAlias(), action: addManualAlias)
                        .disabled(manualAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !controller.manualAliasError.isEmpty {
                    Text(controller.manualAliasError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 6)
        } label: {
            Text(AppStrings.importManualAlias())
                .font(.headline)
        }
    }

    @ViewBuilder
    private var discoveryIssues: some View {
        if !controller.discoveryIssues.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(controller.discoveryIssues.enumerated()), id: \.offset) { _, issue in
                        Label(AppStrings.importDiscoveryIssue(issue), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
        }
    }

    private var selectionToolbar: some View {
        HStack {
            Button(AppStrings.importSelectAll()) { controller.selectAll() }
                .buttonStyle(.link)
            Button(AppStrings.importSelectNone()) { controller.selectNone() }
                .buttonStyle(.link)
            Spacer()
            Text(AppStrings.importSelectionCount(controller.selectedCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var candidateList: some View {
        ScrollView {
            if controller.candidates.isEmpty {
                Text(AppStrings.importEmpty())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(controller.candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func candidateRow(_ candidate: SSHConfigImportCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { candidate.isSelected },
                    set: { controller.setSelected($0, id: candidate.id) }
                )
            )
            .labelsHidden()
            .accessibilityLabel(candidate.alias)
            .disabled(candidate.isDuplicate || controller.isResolving)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.alias)
                    .font(.headline)
                if let path = candidate.sourcePath, let line = candidate.sourceLine {
                    Text(AppStrings.importSource(path, line: line))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                previewStatus(candidate)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func previewStatus(_ candidate: SSHConfigImportCandidate) -> some View {
        if candidate.isDuplicate {
            Text(AppStrings.importDuplicate())
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch candidate.preview {
            case .notPreviewed:
                Text(AppStrings.importNotPreviewed())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .resolving:
                Text(AppStrings.importResolving())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .resolved(let directives):
                ForEach(Array(directives.enumerated()), id: \.offset) { _, directive in
                    Text(
                        "\(AppStrings.importForwardKind(directive.kind)) · "
                            + AppStrings.importListener(
                                host: directive.listenHost,
                                port: directive.listenPort,
                                exposed: directive.isPotentiallyExposed
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(directive.isPotentiallyExposed ? .orange : .secondary)
                }
            case .noForwarding:
                errorStatus(AppStrings.importNoForwarding())
            case .failed:
                errorStatus(AppStrings.importResolutionFailed())
            case .timedOut:
                errorStatus(AppStrings.importResolutionTimedOut())
            }
        }
    }

    private func errorStatus(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private var actionBar: some View {
        HStack {
            Button(AppStrings.cancel()) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(AppStrings.importPreviewSelected()) {
                if controller.requiresMatchExecConfirmation {
                    showsMatchExecConfirmation = true
                } else {
                    Task { await controller.previewSelected() }
                }
            }
            .disabled(!controller.canPreview)
            Button(AppStrings.importSelected(controller.importableAliases.count)) {
                if controller.hasRiskyImport {
                    showsRiskConfirmation = true
                } else {
                    importSelectedAliases()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.importableAliases.isEmpty || controller.isResolving)
        }
    }

    private func addManualAlias() {
        if controller.addManualAlias(manualAlias) {
            manualAlias = ""
        }
    }

    private func importSelectedAliases() {
        if manager.importSSHConfigAliases(controller.importableAliases) {
            dismiss()
        }
    }
}
