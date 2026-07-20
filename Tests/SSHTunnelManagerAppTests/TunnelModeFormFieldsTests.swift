import Foundation
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@Test func tunnelDraftRoundTripsAutomaticConnectionSettings() throws {
    var tunnel = TunnelConfig(
        name: "Example",
        sshConfigName: "example-service",
        openURL: nil
    )
    tunnel.isAutoReconnectEnabled = true
    tunnel.isAutoStartEnabled = true

    let rebuilt = try TunnelDraft(tunnel: tunnel).makeConfig(id: tunnel.id)

    #expect(rebuilt.isAutoReconnectEnabled)
    #expect(rebuilt.isAutoStartEnabled)
}

@Test func tunnelDraftRoundTripsMixedConnectionGroupRules() throws {
    var tunnel = TunnelConfig(
        name: "Mixed", sshHost: "example-host", localHost: "127.0.0.1", localPort: 15432,
        remoteHost: "db", remotePort: 5432, openURL: URL(string: "http://127.0.0.1:15432")
    )
    tunnel.replaceRules([
        tunnel.rules[0],
        TunnelForwardRule(mode: .remoteForward, localHost: "127.0.0.1", localPort: 3000, remoteHost: "localhost", remotePort: 18080, isEnabled: false),
        TunnelForwardRule(mode: .dynamicForward, localHost: "[::1]", localPort: 1080),
    ])

    let rebuilt = try TunnelDraft(tunnel: tunnel).makeConfig(id: tunnel.id)

    #expect(rebuilt.id == tunnel.id)
    #expect(rebuilt.sshHost == "example-host")
    #expect(rebuilt.effectiveRules == tunnel.effectiveRules)
}

@Test func tunnelDraftEqualityDetectsUnsavedEditorChanges() {
    let initial = TunnelDraft()
    var changed = initial

    #expect(changed == initial)
    changed.rules = changed.rules
    #expect(changed == initial)
    changed.name = "Changed"
    #expect(changed != initial)
}

@Test func sshConfigDraftChangeDetectionIgnoresHiddenConnectionGroupState() {
    let tunnel = TunnelConfig(name: "Reference", sshConfigName: "example", openURL: nil)
    let initial = TunnelDraft(tunnel: tunnel)
    var current = initial

    current.primaryRuleID = UUID()
    current.localHost = "127.0.0.1"
    #expect(current.hasSameEditableContent(as: initial))

    current.sshConfigName = "changed"
    #expect(!current.hasSameEditableContent(as: initial))
}

@Test func ruleDraftBuildsCompactEndpointSummariesForEveryForwardingMode() {
    var local = TunnelRuleDraft()
    local.localHost = "127.0.0.1"
    local.localPort = "18081"
    local.remoteHost = "db"
    local.remotePort = "5432"
    #expect(local.compactEndpointSummary == "127.0.0.1:18081 → db:5432")

    var remote = local
    remote.mode = .remoteForward
    remote.remoteHost = "localhost"
    remote.remotePort = "19083"
    #expect(remote.compactEndpointSummary == "localhost:19083 → 127.0.0.1:18081")

    var socks = local
    socks.mode = .dynamicForward
    socks.localPort = "19082"
    #expect(socks.compactEndpointSummary == "127.0.0.1:19082")
}

@Test func tunnelDraftRemovesRulesByStableIdentifierWithoutRemovingTheLastRule() {
    var draft = TunnelDraft()
    var rules = draft.rules
    let originalPrimaryID = rules[0].id

    var second = TunnelRuleDraft()
    second.localPort = "18081"
    second.remoteHost = "127.0.0.1"
    second.remotePort = "80"
    rules.append(second)
    draft.rules = rules

    let removedSecond = draft.removeRule(id: second.id)
    #expect(removedSecond)
    #expect(draft.rules.map(\.id) == [originalPrimaryID])
    let removedOnlyRule = draft.removeRule(id: originalPrimaryID)
    #expect(!removedOnlyRule)

    rules = draft.rules
    var replacement = TunnelRuleDraft()
    replacement.localPort = "18082"
    replacement.remoteHost = "127.0.0.1"
    replacement.remotePort = "81"
    rules.append(replacement)
    draft.rules = rules

    let removedPrimary = draft.removeRule(id: originalPrimaryID)
    #expect(removedPrimary)
    #expect(draft.rules.map(\.id) == [replacement.id])
}

@Test func tunnelDraftSeparatesConfigurationTypeFromForwardingRuleMode() {
    var draft = TunnelDraft()
    #expect(draft.configurationKind == .connectionGroup)
    #expect(draft.rules.count == 1)

    draft.configurationKind = .sshConfigReference
    #expect(draft.mode == .sshConfig)
    #expect(draft.rules.isEmpty)

    draft.configurationKind = .connectionGroup
    #expect(draft.mode == .localForward)
    #expect(draft.rules.count == 1)
}

@Test func unifiedRuleDraftIncludesAndUpdatesTheFirstRule() {
    var draft = TunnelDraft()
    var first = draft.rules[0]
    first.localHost = "127.0.0.1"
    first.localPort = "18081"
    first.remoteHost = "db"
    first.remotePort = "5432"
    first.isEnabled = false
    var second = TunnelRuleDraft()
    second.mode = .dynamicForward
    second.localHost = "127.0.0.1"
    second.localPort = "1080"

    draft.rules = [second, first]

    #expect(draft.mode == .dynamicForward)
    #expect(draft.localPort == "1080")
    #expect(draft.additionalRules == [first])
    #expect(draft.rules.map(\.id) == [second.id, first.id])
}

@Test func dynamicForwardFormShowsOnlySSHHostAndLocalFields() {
    #expect(TunnelMode.dynamicForward.showsSSHHostAndLocalFields)
    #expect(!TunnelMode.dynamicForward.showsRemoteFields)
    #expect(!TunnelMode.dynamicForward.showsSSHConfigFields)
}

@Test func localForwardFormShowsManualForwardFields() {
    #expect(TunnelMode.localForward.showsSSHHostAndLocalFields)
    #expect(TunnelMode.localForward.showsRemoteFields)
    #expect(!TunnelMode.localForward.showsSSHConfigFields)
}

@Test func remoteForwardFormShowsSSHRemoteListenerAndLocalTargetFields() {
    #expect(TunnelMode.remoteForward.showsSSHHostAndLocalFields)
    #expect(TunnelMode.remoteForward.showsRemoteFields)
    #expect(!TunnelMode.remoteForward.showsSSHConfigFields)
}

@Test func selectingRemoteForwardDefaultsRemoteListenerToLocalhost() {
    var draft = TunnelDraft()
    draft.remoteHost = "example-target"

    draft.mode = .remoteForward

    #expect(draft.remoteHost == "localhost")
}

@Test func sshConfigFormShowsOnlyConfigAliasField() {
    #expect(!TunnelMode.sshConfig.showsSSHHostAndLocalFields)
    #expect(!TunnelMode.sshConfig.showsRemoteFields)
    #expect(TunnelMode.sshConfig.showsSSHConfigFields)
}

@Test func addRuleRequiresCurrentRulesToBeCompleteAndHonorsLimit() {
    var draft = TunnelDraft()
    #expect(!draft.canAddRule)

    draft.localHost = "127.0.0.1"
    draft.localPort = "18081"
    draft.remoteHost = "db"
    draft.remotePort = "5432"
    #expect(draft.canAddRule)

    draft.additionalRules.append(TunnelRuleDraft())
    #expect(!draft.canAddRule)
    draft.additionalRules[0].mode = .dynamicForward
    draft.additionalRules[0].localHost = "127.0.0.1"
    draft.additionalRules[0].localPort = "18082"
    #expect(draft.canAddRule)

    let completed = draft.additionalRules[0]
    draft.additionalRules = Array(
        repeating: completed,
        count: TunnelConfig.maximumRuleCount - 1
    )
    #expect(draft.hasReachedRuleLimit)
    #expect(!draft.canAddRule)
}

@Test func applyingRecommendedPortUpdatesMatchingURLAndClearsRiskConfirmation() {
    var draft = TunnelDraft()
    draft.localHost = "127.0.0.1"
    draft.localPort = "18080"
    draft.remoteHost = "example-service"
    draft.remotePort = "80"
    draft.openURL = "http://localhost:18080/path?q=1#section"
    draft.primaryRiskConfirmationSignature = "old-signature"

    let applied = draft.applyRecommendedLocalPort(18081, to: draft.primaryRuleID)

    #expect(applied)
    #expect(draft.localPort == "18081")
    #expect(draft.openURL == "http://localhost:18081/path?q=1#section")
    #expect(draft.primaryRiskConfirmationSignature == nil)
}

@Test func applyingRecommendedPortDoesNotRewriteUnrelatedURL() {
    var draft = TunnelDraft()
    draft.localHost = "127.0.0.1"
    draft.localPort = "18080"
    draft.remoteHost = "example-service"
    draft.remotePort = "80"
    draft.openURL = "https://example.invalid:18080/path"

    let applied = draft.applyRecommendedLocalPort(18081, to: draft.primaryRuleID)
    #expect(applied)
    #expect(draft.openURL == "https://example.invalid:18080/path")
}

@Test func applyingRecommendedPortChangesOnlyTheSelectedRule() {
    var draft = TunnelDraft()
    draft.localHost = "127.0.0.1"
    draft.localPort = "18080"
    draft.remoteHost = "example-service"
    draft.remotePort = "80"
    var second = TunnelRuleDraft()
    second.mode = .dynamicForward
    second.localHost = "127.0.0.1"
    second.localPort = "1080"
    draft.additionalRules = [second]

    let applied = draft.applyRecommendedLocalPort(1081, to: second.id)
    #expect(applied)
    #expect(draft.localPort == "18080")
    #expect(draft.additionalRules[0].localPort == "1081")
}

@Test func recommendedPortCannotBeAppliedToRemoteForwardOrPrivilegedPort() {
    var draft = TunnelDraft()
    draft.mode = .remoteForward
    draft.localHost = "127.0.0.1"
    draft.localPort = "3000"
    draft.remoteHost = "localhost"
    draft.remotePort = "18080"

    let appliedToRemote = draft.applyRecommendedLocalPort(3001, to: draft.primaryRuleID)
    #expect(!appliedToRemote)

    draft.mode = .localForward
    let appliedPrivilegedPort = draft.applyRecommendedLocalPort(80, to: draft.primaryRuleID)
    #expect(!appliedPrivilegedPort)
}
