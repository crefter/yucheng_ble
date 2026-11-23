import Foundation

final class Clock {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000.8)
    private var shouldBlockWriter = false
    let writerBlocked = DispatchSemaphore(value: 0)
    let releaseWriter = DispatchSemaphore(value: 0)

    func now() -> Date {
        let (date, blocked) = lock.withLock {
            let blocked = shouldBlockWriter && !Thread.isMainThread
            if blocked { shouldBlockWriter = false }
            return (value, blocked)
        }
        if blocked {
            writerBlocked.signal()
            precondition(releaseWriter.wait(timeout: .now() + 5) == .success)
        }
        return date
    }

    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
    func blockNextWriterCall() { lock.withLock { shouldBlockWriter = true } }
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: folder) }
let native = folder.appendingPathComponent("diagnostics/native")
let detailed = native.appendingPathComponent("detailed")
let legacy = folder.appendingPathComponent("legacy/detailed")
try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
let legacyFile = legacy.appendingPathComponent("yucheng-history.log")
try Data("older diagnostic payload".utf8).write(to: legacyFile)

func awaitResult(_ operation: (@escaping (Bool) -> Void) -> Void) -> Bool {
    var result: Bool?
    operation { result = $0 }
    let deadline = Date().addingTimeInterval(5)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    precondition(result != nil)
    return result!
}

func segments() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: detailed, includingPropertiesForKeys: nil)) ?? []
}

let clock = Clock()
let diagnostics = YuchengDiagnostics(directory: native, legacyDetailed: legacy, now: clock.now)
precondition(diagnostics.detailedSession() == nil)
precondition(awaitResult { diagnostics.setDetailedEnabled(true, completion: $0) })
precondition(!FileManager.default.fileExists(atPath: legacyFile.path))
let session = diagnostics.detailedSession()
diagnostics.detailed("history", session: session, rows: [["sample": 75]])
precondition(awaitResult(diagnostics.flush))
let first = segments().first!
let record = try JSONSerialization.jsonObject(with: Data(contentsOf: first)) as! [String: Any]
let parser = ISO8601DateFormatter()
parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let recordedAt = parser.date(from: record["timestamp"] as! String)!
precondition(recordedAt.timeIntervalSince1970 > 1_800_000_000.2)
clock.advance(6 * 86_400)
diagnostics.detailed("history", session: session, rows: [["sample": 76]])
precondition(awaitResult(diagnostics.flush) && segments().count == 2)
clock.advance(86_400)
precondition(awaitResult(diagnostics.flush))
precondition(segments().count == 1 && !segments().contains(first))

clock.blockNextWriterCall()
var initialFlush: Bool?
diagnostics.flush { initialFlush = $0 }
precondition(clock.writerBlocked.wait(timeout: .now() + 5) == .success)
for _ in 0..<65 { diagnostics.detailed("history", session: session, rows: [["sample": 77]]) }
var revoked: Bool?
diagnostics.setDetailedEnabled(false) { revoked = $0 }
precondition(diagnostics.detailedSession() == nil)
clock.releaseWriter.signal()
precondition(awaitResult(diagnostics.flush) && initialFlush == false && revoked == true && segments().isEmpty)

precondition(awaitResult { diagnostics.setDetailedEnabled(true, completion: $0) })
diagnostics.detailed("history", session: session, rows: [["sample": 78]])
precondition(awaitResult(diagnostics.flush) && segments().isEmpty)
print("PASS timestamp precision, expiry, queue saturation, legacy cleanup and opt-out")
