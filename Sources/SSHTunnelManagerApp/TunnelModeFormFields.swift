import SSHTunnelCore

extension TunnelMode {
    var showsSSHHostAndLocalFields: Bool {
        self == .localForward || self == .remoteForward || self == .dynamicForward
    }

    var showsRemoteFields: Bool {
        self == .localForward || self == .remoteForward
    }

    var showsSSHConfigFields: Bool {
        self == .sshConfig
    }
}
