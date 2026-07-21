import Foundation
import SSHTunnelCore

enum AppStrings {
    static func string(_ key: String, language: String? = nil) -> String {
        string(key, language: language, defaultValue: key)
    }

    static func string(_ key: String, language: String? = nil, defaultValue: String) -> String {
        if let language,
           let value = stringsDictionary(language: language)[key] {
            return value
        }

        return NSLocalizedString(
            key,
            tableName: nil,
            bundle: resourceBundle,
            value: defaultValue,
            comment: ""
        )
    }

    static func format(_ key: String, language: String? = nil, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, language: language),
            arguments: arguments
        )
    }

    static func localizationKeys(language: String) throws -> Set<String> {
        Set(stringsDictionary(language: language).keys)
    }

    static func menuTitle(runningCount: Int, language: String? = nil) -> String {
        runningCount == 0
            ? string("menu.title.idle", language: language)
            : format("menu.title.running", language: language, runningCount)
    }

    static func modeName(_ mode: TunnelMode, language: String? = nil) -> String {
        switch mode {
        case .localForward:
            return modeLocalForward(language: language)
        case .remoteForward:
            return modeRemoteForward(language: language)
        case .dynamicForward:
            return modeDynamicForward(language: language)
        case .sshConfig:
            return modeSSHConfig(language: language)
        }
    }

    static func tunnelSummary(_ tunnel: TunnelConfig, language: String? = nil) -> String {
        if tunnel.mode != .sshConfig {
            return format(
                "row.summary.connectionGroup",
                language: language,
                tunnel.sshHost,
                tunnel.effectiveRules.filter(\.isEnabled).count,
                tunnel.effectiveRules.count
            )
        }
        switch tunnel.mode {
        case .sshConfig:
            return format("row.summary.sshConfig", language: language, tunnel.sshConfigName ?? "")
        case .localForward, .remoteForward, .dynamicForward:
            preconditionFailure("Connection groups are handled before the mode switch")
        }
    }

    static func failedToLoadTunnels(_ message: String, language: String? = nil) -> String {
        format("error.failedToLoadTunnels", language: language, message)
    }

    static func failedToSaveTunnels(_ message: String, language: String? = nil) -> String {
        format("error.failedToSaveTunnels", language: language, message)
    }

    static func localPortAlreadyListeningOutsideApp(host: String, port: Int, language: String? = nil) -> String {
        format("error.localPortAlreadyListeningOutsideApp", language: language, host, port)
    }

    static func stopBeforeEditing(language: String? = nil) -> String {
        string("error.stopBeforeEditing", language: language)
    }

    static func formAutomation(language: String? = nil) -> String {
        string("form.automation", language: language)
    }

    static func formAutoReconnect(language: String? = nil) -> String {
        string("form.autoReconnect", language: language)
    }

    static func autoReconnectHelp(language: String? = nil) -> String {
        string("form.autoReconnect.help", language: language)
    }

    static func formAutoStart(language: String? = nil) -> String {
        string("form.autoStart", language: language)
    }

    static func autoStartHelp(language: String? = nil) -> String {
        string("form.autoStart.help", language: language)
    }

    static func autoStartRiskConfirmationRequired(language: String? = nil) -> String {
        string("error.autoStartRiskConfirmationRequired", language: language)
    }

    static func sshProcessExited(code: Int32, language: String? = nil) -> String {
        format("error.sshProcessExited", language: language, code)
    }

    static func headerSubtitle(language: String? = nil) -> String {
        string("header.subtitle", language: language)
    }

    static func refresh(language: String? = nil) -> String {
        string("button.refresh", language: language)
    }

    static func refreshHelp(language: String? = nil) -> String {
        string("help.refresh", language: language)
    }

    static func settings(language: String? = nil) -> String {
        string("button.settings", language: language)
    }

    static func settingsTitle(language: String? = nil) -> String {
        string("settings.title", language: language)
    }

    static func settingsHelp(language: String? = nil) -> String {
        string("help.settings", language: language)
    }

    static func notificationSettingsTitle(language: String? = nil) -> String {
        string("notification.settings.title", language: language)
    }

    static func notificationEnabled(language: String? = nil) -> String {
        string("notification.enabled", language: language)
    }

    static func notificationPermissionHelp(language: String? = nil) -> String {
        string("notification.permission.help", language: language)
    }

    static func notificationPermissionDenied(language: String? = nil) -> String {
        string("notification.permission.denied", language: language)
    }

    static func notificationPermissionFailed(language: String? = nil) -> String {
        string("notification.error.permission", language: language)
    }

    static func notificationSettingsLoadFailed(language: String? = nil) -> String {
        string("notification.error.load", language: language)
    }

    static func notificationSettingsSaveFailed(language: String? = nil) -> String {
        string("notification.error.save", language: language)
    }

    static func notificationDeliveryFailed(language: String? = nil) -> String {
        string("notification.error.delivery", language: language)
    }

    static func notificationUnavailableOutsideApp(language: String? = nil) -> String {
        string("notification.error.unsupported", language: language)
    }

    static func loginItemSettingsTitle(language: String? = nil) -> String {
        string("loginItem.settings.title", language: language)
    }

    static func loginItemEnabled(language: String? = nil) -> String {
        string("loginItem.enabled", language: language)
    }

    static func loginItemHelp(language: String? = nil) -> String {
        string("loginItem.help", language: language)
    }

    static func loginItemStatusRequiresApproval(language: String? = nil) -> String {
        string("loginItem.status.requiresApproval", language: language)
    }

    static func loginItemStatusUnsupported(language: String? = nil) -> String {
        string("loginItem.status.unsupported", language: language)
    }

    static func loginItemUnsupported(language: String? = nil) -> String {
        string("loginItem.error.unsupported", language: language)
    }

    static func loginItemOperationFailed(_ message: String, language: String? = nil) -> String {
        format("loginItem.error.operation", language: language, message)
    }

    static func notificationFailureTitle(language: String? = nil) -> String {
        string("notification.failure.title", language: language)
    }

    static func notificationFailureBody(
        category: TunnelFailureCategory,
        retryCount: Int,
        willRetry: Bool,
        language: String? = nil
    ) -> String {
        let categoryText = failureCategory(category, language: language)
        return willRetry
            ? format("notification.failure.retry", language: language, categoryText, retryCount)
            : format("notification.failure.stopped", language: language, categoryText)
    }

    static func notificationRecoveryTitle(language: String? = nil) -> String {
        string("notification.recovery.title", language: language)
    }

    static func notificationRecoveryBody(language: String? = nil) -> String {
        string("notification.recovery.body", language: language)
    }

    static func failureCategory(_ category: TunnelFailureCategory, language: String? = nil) -> String {
        string("diagnostic.category.\(category.rawValue)", language: language)
    }

    static func healthKind(_ kind: TunnelHealthCheckKind, language: String? = nil) -> String {
        string("health.kind.\(kind.rawValue)", language: language)
    }

    static func healthPhase(_ phase: TunnelHealthAggregatePhase, language: String? = nil) -> String {
        let key: String
        switch phase {
        case .notConfigured: key = "notConfigured"
        case .waiting: key = "waiting"
        case .healthy: key = "healthy"
        case .unhealthy: key = "unhealthy"
        }
        return string("health.phase.\(key)", language: language)
    }

    static func healthPhase(_ phase: RuleHealthCheckPhase, language: String? = nil) -> String {
        let key: String
        switch phase {
        case .waiting: key = "waiting"
        case .healthy: key = "healthy"
        case .unhealthy: key = "unhealthy"
        }
        return string("health.phase.\(key)", language: language)
    }

    static func healthFailureCategory(
        _ category: HealthProbeFailureCategory,
        language: String? = nil
    ) -> String {
        string("health.failure.\(category.rawValue)", language: language)
    }

    static func connectionDetails(language: String? = nil) -> String {
        string("diagnostic.details", language: language)
    }

    static func copyDiagnostics(language: String? = nil) -> String {
        string("diagnostic.copy", language: language)
    }

    static func diagnosticsCopied(language: String? = nil) -> String {
        string("diagnostic.copied", language: language)
    }

    static func diagnosticStatusChanged(language: String? = nil) -> String {
        string("diagnostic.statusChanged", language: language)
    }

    static func diagnosticExitCode(language: String? = nil) -> String {
        string("diagnostic.exitCode", language: language)
    }

    static func diagnosticRetryCount(language: String? = nil) -> String {
        string("diagnostic.retryCount", language: language)
    }

    static func diagnosticNextRetry(language: String? = nil) -> String {
        string("diagnostic.nextRetry", language: language)
    }

    static func diagnosticErrorCategory(language: String? = nil) -> String {
        string("diagnostic.errorCategory", language: language)
    }

    static func diagnosticErrorSummary(language: String? = nil) -> String {
        string("diagnostic.errorSummary", language: language)
    }

    static func diagnosticNone(language: String? = nil) -> String {
        string("diagnostic.none", language: language)
    }

    static func close(language: String? = nil) -> String {
        string("button.close", language: language)
    }

    static func importSSHConfig(language: String? = nil) -> String {
        string("import.sshConfig.button", language: language)
    }

    static func importSSHConfigTitle(language: String? = nil) -> String {
        string("import.sshConfig.title", language: language)
    }

    static func importSSHConfigSubtitle(language: String? = nil) -> String {
        string("import.sshConfig.subtitle", language: language)
    }

    static func importManualAlias(language: String? = nil) -> String {
        string("import.manualAlias", language: language)
    }

    static func importManualAliasPlaceholder(language: String? = nil) -> String {
        string("import.manualAlias.placeholder", language: language)
    }

    static func importManualAliasHelp(language: String? = nil) -> String {
        string("import.manualAlias.help", language: language)
    }

    static func importAddAlias(language: String? = nil) -> String {
        string("import.manualAlias.add", language: language)
    }

    static func importInvalidAlias(language: String? = nil) -> String {
        string("import.error.invalidAlias", language: language)
    }

    static func importNoNewHosts(language: String? = nil) -> String {
        string("import.error.noNewHosts", language: language)
    }

    static func importScanning(language: String? = nil) -> String {
        string("import.scanning", language: language)
    }

    static func importEmpty(language: String? = nil) -> String {
        string("import.empty", language: language)
    }

    static func importSelectAll(language: String? = nil) -> String {
        string("import.selectAll", language: language)
    }

    static func importSelectNone(language: String? = nil) -> String {
        string("import.selectNone", language: language)
    }

    static func importPreviewSelected(language: String? = nil) -> String {
        string("import.previewSelected", language: language)
    }

    static func importSelected(_ count: Int, language: String? = nil) -> String {
        format("import.selected", language: language, count)
    }

    static func importSelectionCount(_ count: Int, language: String? = nil) -> String {
        format("import.selectionCount", language: language, count)
    }

    static func importMatchExecTitle(language: String? = nil) -> String {
        string("import.matchExec.title", language: language)
    }

    static func importMatchExecMessage(language: String? = nil) -> String {
        string("import.matchExec.message", language: language)
    }

    static func importRiskTitle(language: String? = nil) -> String {
        string("import.risk.title", language: language)
    }

    static func importRiskMessage(language: String? = nil) -> String {
        string("import.risk.message", language: language)
    }

    static func importDuplicate(language: String? = nil) -> String {
        string("import.status.duplicate", language: language)
    }

    static func importNotPreviewed(language: String? = nil) -> String {
        string("import.status.notPreviewed", language: language)
    }

    static func importResolving(language: String? = nil) -> String {
        string("import.status.resolving", language: language)
    }

    static func importNoForwarding(language: String? = nil) -> String {
        string("import.status.noForwarding", language: language)
    }

    static func importResolutionFailed(language: String? = nil) -> String {
        string("import.status.failed", language: language)
    }

    static func importResolutionTimedOut(language: String? = nil) -> String {
        string("import.status.timedOut", language: language)
    }

    static func importSource(_ path: String, line: Int, language: String? = nil) -> String {
        format("import.source", language: language, path, line)
    }

    static func importForwardKind(_ kind: SSHConfigForwardingKind, language: String? = nil) -> String {
        string("import.forward.\(kind.rawValue)", language: language)
    }

    static func importListener(
        host: String,
        port: Int?,
        exposed: Bool,
        language: String? = nil
    ) -> String {
        let endpoint = port.map { "\(host):\($0)" } ?? host
        return format(
            exposed ? "import.listener.exposed" : "import.listener.loopback",
            language: language,
            endpoint
        )
    }

    static func importDiscoveryIssue(
        _ issue: SSHConfigDiscoveryIssue,
        language: String? = nil
    ) -> String {
        let key = "import.discovery.\(issue.kind.rawValue)"
        if let line = issue.line {
            return format(key + ".line", language: language, issue.sourcePath, line)
        }
        return format(key, language: language, issue.sourcePath)
    }

    static func shortcutSettingsTitle(language: String? = nil) -> String {
        string("shortcut.settings.title", language: language)
    }

    static func shortcutEnabled(language: String? = nil) -> String {
        string("shortcut.enabled", language: language)
    }

    static func shortcutLabel(language: String? = nil) -> String {
        string("shortcut.label", language: language)
    }

    static func shortcutRecord(language: String? = nil) -> String {
        string("shortcut.record", language: language)
    }

    static func shortcutRecording(language: String? = nil) -> String {
        string("shortcut.recording", language: language)
    }

    static func shortcutRetry(language: String? = nil) -> String {
        string("shortcut.retry", language: language)
    }

    static func shortcutRestoreDefault(language: String? = nil) -> String {
        string("shortcut.restoreDefault", language: language)
    }

    static func shortcutStatusLabel(language: String? = nil) -> String {
        string("shortcut.status.label", language: language)
    }

    static func shortcutStatusActive(language: String? = nil) -> String {
        string("shortcut.status.active", language: language)
    }

    static func shortcutStatusDisabled(language: String? = nil) -> String {
        string("shortcut.status.disabled", language: language)
    }

    static func shortcutStatusConflict(language: String? = nil) -> String {
        string("shortcut.status.conflict", language: language)
    }

    static func shortcutStatusFailed(language: String? = nil) -> String {
        string("shortcut.status.failed", language: language)
    }

    static func shortcutLimitation(language: String? = nil) -> String {
        string("shortcut.limitation", language: language)
    }

    static func shortcutInvalid(language: String? = nil) -> String {
        string("shortcut.error.invalid", language: language)
    }

    static func shortcutInvalidStoredSettings(language: String? = nil) -> String {
        string("shortcut.error.invalidStoredSettings", language: language)
    }

    static func shortcutValidationError(
        _ error: GlobalShortcutValidationError,
        language: String? = nil
    ) -> String {
        switch error {
        case .missingPrimaryKey:
            string("shortcut.error.missingPrimaryKey", language: language)
        case .missingRequiredModifier:
            string("shortcut.error.missingModifier", language: language)
        case .unsupportedKey:
            string("shortcut.error.unsupportedKey", language: language)
        }
    }

    static func shortcutIssue(
        _ issue: GlobalShortcutIssue,
        shortcut: GlobalShortcut,
        language: String? = nil
    ) -> String {
        let shortcutText = GlobalShortcutFormatter.displayText(for: shortcut)
        switch issue {
        case let .invalidShortcut(error):
            return shortcutValidationError(error, language: language)
        case .systemConflict:
            return format("shortcut.error.conflict", language: language, shortcutText)
        case let .systemQueryFailed(code):
            return format("shortcut.error.queryFailed", language: language, code)
        case let .registrationFailed(code):
            return format("shortcut.error.registrationFailed", language: language, shortcutText, code)
        case .persistenceFailed:
            return string("shortcut.error.persistenceFailed", language: language)
        }
    }

    static func emptyStateTitle(language: String? = nil) -> String {
        string("empty.title", language: language)
    }

    static func emptyStateBody(language: String? = nil) -> String {
        string("empty.body", language: language)
    }

    static func addTunnel(language: String? = nil) -> String {
        string("button.addTunnel", language: language)
    }

    static func quit(language: String? = nil) -> String {
        string("button.quit", language: language)
    }

    static func quitHelp(language: String? = nil) -> String {
        string("help.quit", language: language)
    }

    static func stop(language: String? = nil) -> String {
        string("button.stop", language: language)
    }

    static func start(language: String? = nil) -> String {
        string("button.start", language: language)
    }

    static func open(language: String? = nil) -> String {
        string("button.open", language: language)
    }

    static func edit(language: String? = nil) -> String {
        string("button.edit", language: language)
    }

    static func deleteTunnelHelp(language: String? = nil) -> String {
        string("help.deleteTunnel", language: language)
    }

    static func deleteTunnelConfirmationTitle(language: String? = nil) -> String {
        string("delete.confirmation.title", language: language)
    }

    static func deleteTunnelConfirmationMessage(name: String, language: String? = nil) -> String {
        format("delete.confirmation.message", language: language, name)
    }

    static func delete(language: String? = nil) -> String {
        string("button.delete", language: language)
    }

    static func save(language: String? = nil) -> String {
        string("button.save", language: language)
    }

    static func configurationTransfer(language: String? = nil) -> String { string("configuration.transfer", language: language) }
    static func importActions(language: String? = nil) -> String { string("configuration.actions", language: language) }
    static func configurationTransferTitle(language: String? = nil) -> String { string("configuration.transfer.title", language: language) }
    static func configurationExportTitle(language: String? = nil) -> String { string("configuration.export.title", language: language) }
    static func configurationImportTitle(language: String? = nil) -> String { string("configuration.import.title", language: language) }
    static func configurationExportButton(language: String? = nil) -> String { string("configuration.export.button", language: language) }
    static func configurationImportButton(language: String? = nil) -> String { string("configuration.import.button", language: language) }
    static func configurationChooseFile(language: String? = nil) -> String { string("configuration.import.chooseFile", language: language) }
    static func configurationConflictStrategy(language: String? = nil) -> String { string("configuration.import.conflictStrategy", language: language) }
    static func configurationConflictSkip(language: String? = nil) -> String { string("configuration.import.conflict.skip", language: language) }
    static func configurationConflictReplace(language: String? = nil) -> String { string("configuration.import.conflict.replace", language: language) }
    static func configurationConflictCopy(language: String? = nil) -> String { string("configuration.import.conflict.copy", language: language) }
    static func configurationImportSafetyNote(language: String? = nil) -> String { string("configuration.import.safetyNote", language: language) }
    static func configurationExportRequiresSelection(language: String? = nil) -> String { string("configuration.export.requiresSelection", language: language) }
    static func configurationOpeningExportPanel(language: String? = nil) -> String { string("configuration.export.openingPanel", language: language) }
    static func configurationOpeningImportPanel(language: String? = nil) -> String { string("configuration.import.openingPanel", language: language) }
    static func configurationImportSucceeded(language: String? = nil) -> String { string("configuration.import.succeeded", language: language) }
    static func selectAll(language: String? = nil) -> String { string("button.selectAll", language: language) }
    static func clearSelection(language: String? = nil) -> String { string("button.clearSelection", language: language) }
    static func configurationExportSelection(_ selected: Int, _ total: Int, language: String? = nil) -> String { format("configuration.export.selection", language: language, selected, total) }
    static func configurationImportSource(_ version: String, _ count: Int, language: String? = nil) -> String { format("configuration.import.source", language: language, version, count) }
    static func configurationImportSummary(_ added: Int, _ replaced: Int, _ copied: Int, _ skipped: Int, language: String? = nil) -> String { format("configuration.import.summary", language: language, added, replaced, copied, skipped) }
    static func configurationExportSucceeded(_ count: Int, language: String? = nil) -> String { format("configuration.export.succeeded", language: language, count) }
    static func configurationExportFailed(_ detail: String, language: String? = nil) -> String { format("configuration.export.failed", language: language, detail) }
    static func configurationImportFailed(_ detail: String, language: String? = nil) -> String { format("configuration.import.failed", language: language, detail) }
    static func configurationImportHasConflicts(language: String? = nil) -> String { string("configuration.import.hasConflicts", language: language) }
    static func configurationImportStopTunnels(language: String? = nil) -> String { string("configuration.import.stopTunnels", language: language) }
    static func configurationImportSaveFailed(_ detail: String, language: String? = nil) -> String { format("configuration.import.saveFailed", language: language, detail) }
    static func configurationImportRestoreFailed(_ detail: String, language: String? = nil) -> String { format("configuration.import.restoreFailed", language: language, detail) }
    static func configurationDuplicateIdentifier(_ id: String, language: String? = nil) -> String { format("configuration.import.issue.duplicateID", language: language, id) }
    static func configurationDuplicateName(_ name: String, language: String? = nil) -> String { format("configuration.import.issue.duplicateName", language: language, name) }
    static func configurationPortConflict(_ host: String, _ port: Int, language: String? = nil) -> String { format("configuration.import.issue.portConflict", language: language, host, port) }
    static func configurationExposureWarning(_ host: String, _ port: Int, language: String? = nil) -> String { format("configuration.import.issue.exposure", language: language, host, port) }

    static func update(language: String? = nil) -> String {
        string("button.update", language: language)
    }

    static func cancel(language: String? = nil) -> String {
        string("button.cancel", language: language)
    }

    static func riskyLocalBindTitle(language: String? = nil) -> String {
        string("security.riskyLocalBind.title", language: language)
    }

    static func riskyLocalBindMessage(language: String? = nil) -> String {
        string("security.riskyLocalBind.message", language: language)
    }

    static func riskyRemoteBindTitle(language: String? = nil) -> String {
        string("security.riskyRemoteBind.title", language: language)
    }

    static func riskyRemoteBindMessage(host: String, port: Int, language: String? = nil) -> String {
        format("security.riskyRemoteBind.message", language: language, host, port)
    }

    static func continueAnyway(language: String? = nil) -> String {
        string("security.continueAnyway", language: language)
    }

    static func formMode(language: String? = nil) -> String {
        string("form.mode", language: language)
    }

    static func formName(language: String? = nil) -> String {
        string("form.name", language: language)
    }

    static func formSSHHost(language: String? = nil) -> String {
        string("form.sshHost", language: language)
    }

    static func formLocal(language: String? = nil) -> String {
        string("form.local", language: language)
    }

    static func formSOCKS(language: String? = nil) -> String {
        string("form.socks", language: language)
    }

    static func formRemote(language: String? = nil) -> String {
        string("form.remote", language: language)
    }

    static func formLocalTarget(language: String? = nil) -> String {
        string("form.localTarget", language: language)
    }

    static func formRemoteListener(language: String? = nil) -> String {
        string("form.remoteListener", language: language)
    }

    static func formPort(language: String? = nil) -> String {
        string("form.port", language: language)
    }

    static func formOpenURL(language: String? = nil) -> String {
        string("form.openURL", language: language)
    }

    static func modeLocalForward(language: String? = nil) -> String {
        string("mode.localForward", language: language)
    }

    static func modeRemoteForward(language: String? = nil) -> String {
        string("mode.remoteForward", language: language)
    }

    static func modeDynamicForward(language: String? = nil) -> String {
        string("mode.dynamicForward", language: language)
    }

    static func modeSSHConfig(language: String? = nil) -> String {
        string("mode.sshConfig", language: language)
    }

    static func compactModeName(_ mode: TunnelMode, language: String? = nil) -> String {
        switch mode {
        case .localForward:
            return string("mode.compact.localForward", language: language)
        case .remoteForward:
            return string("mode.compact.remoteForward", language: language)
        case .dynamicForward:
            return string("mode.compact.dynamicForward", language: language)
        case .sshConfig:
            return string("mode.compact.sshConfig", language: language)
        }
    }

    static func placeholderName(language: String? = nil) -> String {
        string("placeholder.name", language: language)
    }

    static func placeholderSSHHost(language: String? = nil) -> String {
        string("placeholder.sshHost", language: language)
    }

    static func placeholderPort(language: String? = nil) -> String {
        string("placeholder.port", language: language)
    }

    static func placeholderSSHConfig(language: String? = nil) -> String {
        string("placeholder.sshConfig", language: language)
    }

    static func placeholderOpenURL(language: String? = nil) -> String {
        string("placeholder.openURL", language: language)
    }

    static func formTags(language: String? = nil) -> String { string("form.tags", language: language) }
    static func placeholderTags(language: String? = nil) -> String { string("placeholder.tags", language: language) }
    static func searchTunnels(language: String? = nil) -> String { string("filter.search", language: language) }
    static func favoritesOnly(language: String? = nil) -> String { string("filter.favorites", language: language) }
    static func allTags(language: String? = nil) -> String { string("filter.allTags", language: language) }
    static func chooseTag(language: String? = nil) -> String { string("filter.chooseTag", language: language) }
    static func searchTags(language: String? = nil) -> String { string("filter.searchTags", language: language) }
    static func tagCount(_ count: Int, language: String? = nil) -> String { format("filter.tagCount", language: language, count) }
    static func noMatchingTags(language: String? = nil) -> String { string("filter.noMatchingTags", language: language) }
    static func pinnedTags(language: String? = nil) -> String { string("filter.pinnedTags", language: language) }
    static func pinnedTagSlot(_ slot: Int, language: String? = nil) -> String { format("filter.pinnedTagSlot", language: language, slot) }
    static func replacePinnedTagHelp(_ slot: Int, language: String? = nil) -> String { format("filter.replacePinnedTagHelp", language: language, slot) }
    static func configurationCount(_ count: Int, language: String? = nil) -> String { format("filter.configurationCount", language: language, count) }
    static func failedToSavePinnedTags(_ reason: String, language: String? = nil) -> String { format("filter.pinnedTags.saveError", language: language, reason) }
    static func clearFilters(language: String? = nil) -> String { string("filter.clear", language: language) }
    static func resultCount(_ count: Int, language: String? = nil) -> String { format("filter.resultCount", language: language, count) }
    static func noMatchingTunnels(language: String? = nil) -> String { string("filter.empty", language: language) }
    static func sort(language: String? = nil) -> String { string("sort.label", language: language) }
    static func sortManual(language: String? = nil) -> String { string("sort.manual", language: language) }
    static func sortName(language: String? = nil) -> String { string("sort.name", language: language) }
    static func sortStatus(language: String? = nil) -> String { string("sort.status", language: language) }
    static func sortLastUsed(language: String? = nil) -> String { string("sort.lastUsed", language: language) }
    static func favorite(language: String? = nil) -> String { string("button.favorite", language: language) }
    static func moveUp(language: String? = nil) -> String { string("button.moveUp", language: language) }
    static func moveDown(language: String? = nil) -> String { string("button.moveDown", language: language) }

    private static func stringsDictionary(language: String) -> [String: String] {
        guard let url = stringsURL(language: language),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return [:]
        }
        return dictionary
    }

    private static func stringsURL(language: String) -> URL? {
        let languageDirectory = "\(language).lproj"
        if let url = resourceBundle.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: languageDirectory
        ) {
            return url
        }

        return resourceBundle.urls(forResourcesWithExtension: "strings", subdirectory: nil)?
            .first { url in
                url.lastPathComponent == "Localizable.strings"
                    && url.deletingLastPathComponent().lastPathComponent.lowercased() == languageDirectory.lowercased()
            }
    }

    private static let resourceBundle: Bundle = {
        let bundleName = "ssh-tunnel-manager_SSHTunnelManagerApp.bundle"
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           let bundle = Bundle(url: resourceURL) {
            return bundle
        }
        return Bundle.module
    }()
}
