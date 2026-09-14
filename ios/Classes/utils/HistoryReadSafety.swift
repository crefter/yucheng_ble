import Foundation

/// The delete API has no read/ack token. After an incomplete read, an old ack
/// cannot safely clear history even if a later read succeeds. Keep this latch
/// for the process lifetime; explicit factory reset/deleteAllData is separate.
final class HistoryReadSafety {
    static let sleep = HistoryReadSafety()
    static let health = HistoryReadSafety()
    private let lock = NSLock()
    private var active = 0
    private var blocked = false
    private var deleting = false

    func begin() -> Bool {
        lock.withLock {
            guard !deleting else { blocked = true; return false }
            active += 1
            return true
        }
    }
    func finish(complete: Bool) {
        lock.withLock {
            active -= 1
            if !complete { blocked = true }
        }
    }
    func beginDelete() -> Bool {
        lock.withLock {
            guard active == 0 && !blocked && !deleting else { return false }
            deleting = true
            return true
        }
    }
    func finishDelete() { lock.withLock { deleting = false } }
}
