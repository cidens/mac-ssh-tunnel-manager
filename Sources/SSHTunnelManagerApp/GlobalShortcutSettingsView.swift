import SSHTunnelCore
import SwiftUI

struct GlobalShortcutSettingsView: View {
    private struct SaveFailure: Equatable {
        let candidate: GlobalShortcutSettings
        let issue: GlobalShortcutIssue
    }

    @EnvironmentObject private var controller: GlobalShortcutController
    @EnvironmentObject private var notificationController: ConnectionNotificationController
    @EnvironmentObject private var loginItemController: LoginItemController
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GlobalShortcutSettings.defaultSettings
    @State private var notificationDraft = ConnectionNotificationSettings.defaultSettings.isEnabled
    @State private var loginItemDraft = false
    @State private var saveFailure: SaveFailure?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.settingsTitle())
                .font(.title2.weight(.semibold))

            Text(AppStrings.shortcutSettingsTitle())
                .font(.headline)

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

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.notificationSettingsTitle())
                    .font(.headline)
                Toggle(
                    AppStrings.notificationEnabled(),
                    isOn: $notificationDraft
                )
                Text(AppStrings.notificationPermissionHelp())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if notificationDraft,
                   notificationController.authorizationState == .denied {
                    Text(AppStrings.notificationPermissionDenied())
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !notificationController.errorMessage.isEmpty {
                    Text(notificationController.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.loginItemSettingsTitle())
                    .font(.headline)
                Toggle(AppStrings.loginItemEnabled(), isOn: $loginItemDraft)
                    .disabled(!loginItemController.isSupported)
                if loginItemController.status == .requiresApproval {
                    Text(AppStrings.loginItemStatusRequiresApproval())
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if loginItemController.status == .unsupported {
                    Text(AppStrings.loginItemStatusUnsupported())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(AppStrings.loginItemHelp())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !loginItemController.errorMessage.isEmpty {
                    Text(loginItemController.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                Button(AppStrings.shortcutRestoreDefault()) {
                    saveFailure = nil
                    draft.isEnabled = true
                    draft.shortcut = .defaultShortcut
                    notificationDraft = ConnectionNotificationSettings.defaultSettings.isEnabled
                    loginItemDraft = false
                }
                .disabled(isSaving)
                Spacer()
                Button(AppStrings.cancel()) {
                    controller.cancelRecording()
                    dismiss()
                }
                .disabled(isSaving)
                Button(AppStrings.save()) {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            draft = controller.settings
            notificationDraft = notificationController.isEnabled
            loginItemController.refresh()
            loginItemDraft = loginItemController.isRegistered
            saveFailure = nil
            isSaving = false
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
        validationMessage == nil && hasUnsavedChanges && !isSaving
    }

    private var hasUnsavedChanges: Bool {
        draft != controller.settings
            || controller.hasInvalidStoredSettings
            || notificationDraft != notificationController.isEnabled
            || loginItemDraft != loginItemController.isRegistered
    }

    private func saveSettings() {
        let shortcutCandidate = draft
        if shortcutCandidate != controller.settings || controller.hasInvalidStoredSettings {
            guard controller.save(shortcutCandidate) else {
                if let issue = controller.issue {
                    saveFailure = SaveFailure(candidate: shortcutCandidate, issue: issue)
                }
                return
            }
            draft = controller.settings
        }

        saveFailure = nil
        controller.cancelRecording()
        if loginItemDraft != loginItemController.isRegistered {
            guard loginItemController.setRegistered(loginItemDraft) else {
                return
            }
            loginItemDraft = loginItemController.isRegistered
        }
        isSaving = true
        Task {
            if notificationDraft != notificationController.isEnabled {
                guard await notificationController.setEnabled(notificationDraft) else {
                    isSaving = false
                    return
                }
            }
            isSaving = false
            dismiss()
        }
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
