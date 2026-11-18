extension ServerConnection {
    var canReachServer: Bool {
        self == .connected || self == .controllerOffline
    }
}

extension MachineStatus {
    var canStartProgram: Bool {
        connected && !program.name.isEmpty && !program.running
    }

    func canUploadProgram(connection: ServerConnection, isUploading: Bool) -> Bool {
        connection.canReachServer && !isUploading && !program.running
    }
}

struct ReconnectPolicy {
    static let retryDelay: Duration = .seconds(5)

    private static let retryLimit = 3
    private var retriesRemaining = 0

    mutating func recordServerStatus() {
        retriesRemaining = Self.retryLimit
    }

    mutating func reset() {
        retriesRemaining = 0
    }

    mutating func consumeRetry() -> Bool {
        guard retriesRemaining > 0 else { return false }
        retriesRemaining -= 1
        return true
    }
}
