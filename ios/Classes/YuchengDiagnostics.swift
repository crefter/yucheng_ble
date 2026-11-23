import Foundation

final class YuchengDiagnostics {
    static let shared = YuchengDiagnostics(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics/native"),
        legacyDetailed: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics/native/detailed")
    )

    private let queue = DispatchQueue(label: "yucheng.diagnostics")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let files = FileManager.default
    private let detailedLock = NSLock()
    private var detailedGeneration = 0
    private var detailedEnabled = false
    private let pendingWrites = DispatchSemaphore(value: 64)
    private var writesDropped = false
    private let detailedSegmentBytes = 384 * 1024
    private let segmentDuration: TimeInterval = 24 * 60 * 60
    private let legacyNames = ["yucheng-history.log", "yucheng-history.previous.log"]
    private let directory: URL?
    private let legacyDetailed: URL?
    private let now: () -> Date
    private var activeSegment: (url: URL, started: Date)?
    private var writeFailed = false
    private var backupExcluded = false

    init(directory: URL?, legacyDetailed: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.legacyDetailed = legacyDetailed
        self.now = now
        queue.async {
            self.writeFailed = !self.pruneDetailedFiles()
            if !self.clearLegacyFiles() { self.writeFailed = true }
        }
    }

    func setDetailedEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        detailedLock.withLock {
            if !enabled {
                detailedGeneration += 1
                detailedEnabled = false
            }
            let generation = detailedGeneration
            queue.async {
                let ready = enabled ? self.excludeFromBackup() && self.pruneDetailedFiles() : self.clearDetailedFiles()
                let legacyCleared = self.clearLegacyFiles()
                let success = ready && legacyCleared
                if enabled {
                    self.detailedLock.withLock {
                        if self.detailedGeneration == generation { self.detailedEnabled = success }
                    }
                }
                DispatchQueue.main.async { completion(success) }
            }
        }
    }

    func flush(completion: @escaping (Bool) -> Void) {
        queue.async {
            let pruned = self.pruneDetailedFiles()
            let legacyCleared = self.clearLegacyFiles()
            let dropped = self.detailedLock.withLock {
                let dropped = self.writesDropped
                self.writesDropped = false
                return dropped
            }
            let succeeded = pruned && legacyCleared && !self.writeFailed && !dropped
            self.writeFailed = false
            DispatchQueue.main.async { completion(succeeded) }
        }
    }

    func summary(_ event: String, _ fields: String = "") {
        let timestamp = now()
        guard reserveWrite() else { return }
        queue.async {
            defer { self.pendingWrites.signal() }
            let suffix = fields.isEmpty ? "" : " " + fields
            self.append(Data("\(self.formatter.string(from: timestamp)) \(event)\(suffix)\n".utf8), detailed: false)
        }
    }

    func detailedSession() -> Int? {
        detailedLock.withLock { detailedEnabled ? detailedGeneration : nil }
    }

    func detailed(_ event: String, session: Int?, chunkSize: Int = 64, rows: @autoclosure () -> [[String: Any]]) {
        guard let session, session == detailedSession(), reserveWrite() else { return }
        let timestamp = now()
        let snapshot = rows()
        detailedLock.withLock {
            guard detailedEnabled, session == detailedGeneration else {
                pendingWrites.signal()
                return
            }
            queue.async {
                defer { self.pendingWrites.signal() }
                let date = self.formatter.string(from: timestamp)
                for offset in stride(from: 0, to: snapshot.count, by: chunkSize) {
                    guard session == self.detailedSession() else { break }
                    do {
                        let batch = Array(snapshot[offset..<min(offset + chunkSize, snapshot.count)])
                        var line = try JSONSerialization.data(withJSONObject: [
                            "timestamp": date, "event": event, "rows": batch
                        ])
                        line.append(10)
                        self.append(line, detailed: true)
                    } catch {
                        self.writeFailed = true
                    }
                }
            }
        }
    }

    private func reserveWrite() -> Bool {
        if pendingWrites.wait(timeout: .now()) == .success { return true }
        detailedLock.withLock { writesDropped = true }
        return false
    }

    private func segmentStart(_ url: URL) -> Date? {
        let parts = url.lastPathComponent.split(separator: ".")
        guard parts.count == 4, parts[0] == "yucheng-history", parts[3] == "log",
              let millis = Int64(parts[1]), UUID(uuidString: String(parts[2])) != nil else { return nil }
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private func detailedFiles(in folder: URL, includingSegments: Bool) throws -> [URL] {
        do {
            return try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter {
                legacyNames.contains($0.lastPathComponent) || (includingSegments && segmentStart($0) != nil)
            }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
    }

    private func remove(_ file: URL) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true || values.isSymbolicLink == true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try files.removeItem(at: file)
        if activeSegment?.url == file { activeSegment = nil }
    }

    private func clearLegacyFiles() -> Bool {
        guard let legacyDetailed else { return true }
        do {
            for file in try detailedFiles(in: legacyDetailed, includingSegments: false) { try remove(file) }
            return true
        } catch { return false }
    }

    private func clearDetailedFiles() -> Bool {
        guard let folder = directory?.appendingPathComponent("detailed") else { return false }
        do {
            for file in try detailedFiles(in: folder, includingSegments: true) { try remove(file) }
            return true
        } catch { return false }
    }

    private func pruneDetailedFiles() -> Bool {
        guard let folder = directory?.appendingPathComponent("detailed") else { return false }
        do {
            let cutoff = now().addingTimeInterval(-7 * segmentDuration)
            var retained: [(file: URL, started: Date, bytes: Int)] = []
            for file in try detailedFiles(in: folder, includingSegments: true) {
                guard let started = segmentStart(file), started > cutoff else {
                    try remove(file)
                    continue
                }
                let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                retained.append((file, started, bytes))
            }
            var bytes = retained.reduce(0) { $0 + $1.bytes }
            for segment in retained.sorted(by: { $0.started < $1.started }) where bytes > 2 * detailedSegmentBytes {
                try remove(segment.file)
                bytes -= segment.bytes
            }
            return true
        } catch { return false }
    }

    private func excludeFromBackup() -> Bool {
        if backupExcluded { return true }
        guard var root = directory?.deletingLastPathComponent() else { return false }
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try root.setResourceValues(values)
            backupExcluded = true
            return true
        } catch { return false }
    }

    private func fileSize(_ file: URL) throws -> Int {
        guard files.fileExists(atPath: file.path) else { return 0 }
        return (try files.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    private func append(_ line: Data, detailed: Bool) {
        guard let directory, excludeFromBackup() else {
            writeFailed = true
            return
        }
        let limit = detailed ? detailedSegmentBytes : 128 * 1024
        guard line.count <= limit else {
            writeFailed = true
            return
        }
        do {
            let folder = detailed ? directory.appendingPathComponent("detailed") : directory
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let file: URL
            if detailed {
                let started = now()
                if let activeSegment,
                   started.timeIntervalSince(activeSegment.started) < segmentDuration,
                   try fileSize(activeSegment.url) + line.count <= limit {
                    file = activeSegment.url
                } else {
                    let millis = Int64(started.timeIntervalSince1970 * 1000)
                    file = folder.appendingPathComponent("yucheng-history.\(millis).\(UUID().uuidString).log")
                    activeSegment = (file, started)
                }
            } else {
                file = folder.appendingPathComponent("yucheng-native.log")
                if try fileSize(file) + line.count > limit {
                    let previous = folder.appendingPathComponent("yucheng-native.previous.log")
                    if files.fileExists(atPath: previous.path) { try remove(previous) }
                    try files.moveItem(at: file, to: previous)
                }
            }
            guard let handle = fopen(file.path, "ab") else {
                writeFailed = true
                return
            }
            let written = line.withUnsafeBytes { fwrite($0.baseAddress, 1, line.count, handle) }
            let closed = fclose(handle)
            if written != line.count || closed != 0 { writeFailed = true }
            if detailed, !pruneDetailedFiles() { writeFailed = true }
        } catch {
            writeFailed = true
        }
    }
}
