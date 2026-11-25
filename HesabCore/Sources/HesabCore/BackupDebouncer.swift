import Foundation

/// Stage 3: the daily backup leaves the save path.
///
/// The database is still saved at once (atomically) on every change. The end-of-day backup is made `delay` seconds
/// after the last change, on a background queue, from a snapshot of the state as it was saved — a Swift value, so a
/// later change can never alter it. Several quick changes give one backup (the newest). A pending backup is marked
/// in `marker` (UserDefaults in the app): if the app is closed before it is written, the next launch writes it.
/// `flush()` writes a pending backup right away (the app going to the background).
public final class BackupDebouncer: @unchecked Sendable {
    public typealias Snapshot = [String: JSONValue]

    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: Snapshot?
    private var generation = 0
    private let marker: PendingBackupMarker
    private let write: (Snapshot) -> Void

    public init(delay: TimeInterval = 2, label: String = "backup.daily", marker: PendingBackupMarker,
                write: @escaping (Snapshot) -> Void) {
        self.delay = delay
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.marker = marker
        self.write = write
    }

    public var hasPending: Bool { lock.lock(); defer { lock.unlock() }; return pending != nil }

    /// A change was saved: back up this snapshot `delay` seconds from now, unless another change comes first.
    public func schedule(_ snapshot: Snapshot) {
        lock.lock()
        pending = snapshot
        generation += 1
        let mine = generation
        lock.unlock()
        marker.isSet = true
        queue.asyncAfter(deadline: .now() + delay) { [self] in fire(mine) }
    }

    private func fire(_ g: Int) {
        lock.lock()
        guard g == generation, let s = pending else { lock.unlock(); return }      // a newer change restarted the wait
        pending = nil
        lock.unlock()
        write(s)
        finish()
    }

    /// Writes the pending backup now (and waits for it). Nothing pending: nothing happens.
    public func flush() {
        queue.sync {
            lock.lock()
            let s = pending
            pending = nil
            generation += 1
            lock.unlock()
            if let s { write(s) }
            finish()
        }
    }

    /// Drop a pending backup (the data was replaced: import / reset — a fresh one is scheduled by the caller).
    public func cancel() {
        lock.lock()
        pending = nil
        generation += 1
        lock.unlock()
        queue.sync {}
        marker.isSet = false
    }

    private func finish() {
        lock.lock()
        let more = pending != nil
        lock.unlock()
        if !more { marker.isSet = false }
    }

    /// waits for everything already started on the backup queue (tests)
    public func waitUntilIdle() { queue.sync {} }
}

/// Remembers across launches that a backup was still waiting to be written.
public protocol PendingBackupMarker: AnyObject {
    var isSet: Bool { get set }
}

public final class UserDefaultsBackupMarker: PendingBackupMarker {
    private let key: String
    private let defaults: UserDefaults
    public init(key: String = "backup.pending", defaults: UserDefaults = .standard) { self.key = key; self.defaults = defaults }
    public var isSet: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
