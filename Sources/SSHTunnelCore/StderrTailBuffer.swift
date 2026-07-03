import Foundation

public final class StderrTailBuffer: @unchecked Sendable {
    private let maxLines: Int
    private let lock = NSLock()
    private var lines: [String] = []

    public init(maxLines: Int = 6) {
        self.maxLines = max(1, maxLines)
    }

    public var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    public func append(_ chunk: String) {
        let newLines = chunk
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !newLines.isEmpty else {
            return
        }

        lock.lock()
        lines.append(contentsOf: newLines)
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        lock.unlock()
    }
}
