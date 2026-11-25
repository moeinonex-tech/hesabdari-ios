import Foundation

/// Background writes in the order they were asked for (audit 2026-11, critical #3 — the iCloud backup copy).
///
/// Jobs run one after another on one serial queue, so an older copy of a file can never be written after a newer
/// one. A job that has been overtaken by a newer job with the same key before it started is skipped: only the
/// newest copy of each file needs to land.
public final class LatestWinsQueue: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var newest: [String: UInt64] = [:]
    private var counter: UInt64 = 0

    public init(label: String) {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    public func submit(key: String, _ work: @escaping () -> Void) {
        lock.lock()
        counter += 1
        let mine = counter
        newest[key] = mine
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            let current = newest[key] == mine
            lock.unlock()
            if current { work() }
        }
    }

    /// Blocks until every job submitted so far has run or been skipped (tests).
    public func waitUntilIdle() { queue.sync {} }
}
