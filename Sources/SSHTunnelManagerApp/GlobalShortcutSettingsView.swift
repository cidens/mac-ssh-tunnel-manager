import SSHTunnelCore
import SwiftUI

struct GlobalShortcutSettingsView: View {
    private struct SaveFailure: Equatable {
        let candidate: GlobalShortcutSettings
        let issue: GlobalShortcutIssue
    }

    @EnvironmentObject private var controller: GlobalShortcutController
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GlobalShortcutSettings.defaultSettings
    @State private var saveFailure: SaveFailure?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.shortcutSettingsTitle())
                .font(.title2.weight(.semibold))

            Toggle(AppStrings.shortcutEnabled(), isOn: $draft.isEnabled)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.shortcutLabel())
                    .font(.headline)
                HStack(spacing: 10) {
                    Text(
                        controller.isRecording
                            ? AppStrings.shortcutRecording()
                            : GlobalShortcutFormatter.displayText(for: draft.shortcut)
                    )
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(AppStrings.shortcutLabel())
                    .accessibilityValue(GlobalShortcutFormatter.accessibilityText(for: draft.shortcut))

                    Button(
                        controller.isRecording
                            ? AppStrings.cancel()
                            : AppStrings.shortcutRecord()
                    ) {
                        if controller.isRecording {
                            controller.cancelRecording()
                        } else {
                            saveFailure = nil
                            controller.beginRecording()
                        }
                    }
                    .disabled(!draft.isEnabled)
                }

                ShortcutRecorderView(
                    isRecording: controller.isRecording,
                    onCapture: { controller.finishRecording(with: $0) },
                    onCancel: { controller.cancelRecording() }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let issuePresentation {
                    Label {
                        Text(
                            AppStrings.shortcutIssue(
                                issuePresentation.issue,
                                shortcut: issuePresentation.shortcut
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .foregroundStyle(.red)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if controller.hasInvalidStoredSettings {
                    Text(AppStrings.shortcutInvalidStoredSettings())
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Text(AppStrings.shortcutStatusLabel())
                    .font(.headline)
                Text(statusText)
                    .foregroundStyle(statusColor)
                if shouldShowRetry {
                    Button(AppStrings.shortcutRetry()) {
                        _ = controller.retry()
                    }
                    .buttonStyle(.link)
                }
            }

            Text(AppStrings.shortcutLimitation())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button(AppStrings.shortcutRestoreDefault()) {
                    saveFailure = nil
                    draft.isEnabled = true
                    draft.shortcut = .defaultShortcut
                }
                Spacer()
                Button(AppStrings.cancel()) {
                    controller.cancelRecording()
                    dismiss()
                }
                Button(AppStrings.save()) {
                    let candidate = draft
                    if controller.save(candidate) {
                        draft = controller.settings
                        saveFailure = nil
                        controller.cancelRecording()
                        dismiss()
                    } else if let issue = controller.issue {
                        saveFailure = SaveFailure(candidate: candidate, issue: issue)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            draft = controller.settings
            saveFailure = nil
            controller.cancelRecording()
        }
        .onDisappear {
            controller.cancelRecording()
        }
        .onChange(of: controller.recordedShortcut) { _, shortcut in
            guard let shortcut else {
                return
            }
            saveFailure = nil
            draft.shortcut = shortcut
            controller.consumeRecordedShortcut()
        }
        .onChange(of: draft.isEnabled) { _, isEnabled in
            if !isEnabled {
                controller.cancelRecording()
            }
        }
    }

    private var canSave: Bool {
        guard validationMessage == nil else {
            return false
        }
        return draft != controller.settings || controller.hasInvalidStoredSettings
    }

    private var validationMessage: String? {
        guard draft.isEnabled else {
            return nil
        }
        do {
            try draft.shortcut.validate()
            return nil
        } catch let error as GlobalShortcutValidationError {
            return AppStrings.shortcutValidationError(error)
        } catch {
            return AppStrings.shortcutInvalid()
        }
    }

    private var issuePresentation: (issue: GlobalShortcutIssue, shortcut: GlobalShortcut)? {
        if let saveFailure, saveFailure.candidate == draft {
            return (saveFailure.issue, saveFailure.candidate.shortcut)
        }
        guard controller.runtimeState != .active,
              draft == controller.settings,
              let issue = controller.issue else {
            return nil
        }
        return (issue, draft.shortcut)
    }

    private var statusText: String {
        switch controller.runtimeState {
        case .disabled: AppStrings.shortcutStatusDisabled()
        case .active: AppStrings.shortcutStatusActive()
        case .conflict: AppStrings.shortcutStatusConflict()
        case .failed: AppStrings.shortcutStatusFailed()
        }
    }

    private var statusColor: Color {
        switch controller.runtimeState {
        case .active: .green
        case .disabled: .secondary
        case .conflict, .failed: .red
        }
    }

    private var shouldShowRetry: Bool {
        controller.settings.isEnabled
            && controller.runtimeState != .active
            && !controller.isRecording
    }
}
