import SSHTunnelCore

extension TunnelMode {
    var showsSSHHostAndLocalFields: Bool {
        self == .localForward || self == .dynamicForward
    }

    var showsRemoteFields: Bool {
        self == .localForward
    }

    var showsSSHConfigFields: Bool {
        self == .sshConfig
    }
}
