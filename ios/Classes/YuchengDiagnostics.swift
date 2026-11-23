import Foundation

final class YuchengDiagnostics {
    static let shared = YuchengDiagnostics()

    private let queue = DispatchQueue(label: "yucheng.diagnostics")
    private let formatter = ISO8601DateFormatter()
    private let files = FileManager.default
    private let detailedLock = NSLock()
    private var detailedGeneration = 0
    private let detailedFileNames = ["yucheng-history.log", "yucheng-history.previous.log"]
    private let preference = "yucheng.diagnostics.detailed"
    private let defaults: UserDefaults
    private let directory: URL?
    private var writeFailed = false
    private var backupExcluded = false

    init(
        directory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics/native"),
        defaults: UserDefaults = .standard
    ) {
        self.directory = directory
        self.defaults = defaults
    }

    func setDetailedEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        queue.async {
            self.detailedLock.withLock {
                if !enabled { self.detailedGeneration += 1 }
                self.defaults.set(enabled, forKey: self.preference)
            }
            let cleared = enabled || self.clearDetailedFiles()
            let excluded = self.excludeFromBackup()
            DispatchQueue.main.async { completion(cleared && excluded) }
        }
    }

    func flush(completion: @escaping (Bool) -> Void) {
        queue.async {
            let succeeded = !self.writeFailed
            self.writeFailed = false
            DispatchQueue.main.async { completion(succeeded) }
        }
    }

    func summary(_ event: String, _ fields: String = "") {
        let now = Date()
        queue.async {
            let suffix = fields.isEmpty ? "" : " " + fields
            self.append(Data("\(self.formatter.string(from: now)) \(event)\(suffix)\n".utf8), detailed: false)
        }
    }

    func detailedSession() -> Int? {
        detailedLock.withLock { defaults.bool(forKey: preference) ? detailedGeneration : nil }
    }

    func detailed(_ event: String, session: Int?, chunkSize: Int = 64, rows: @autoclosure () -> [[String: Any]]) {
        guard let session, session == detailedSession() else { return }
        let snapshot = rows()
        let now = Date()
        queue.async {
            guard session == self.detailedGeneration else { return }
            let timestamp = self.formatter.string(from: now)
            for offset in stride(from: 0, to: snapshot.count, by: chunkSize) {
                do {
                    let batch = Array(snapshot[offset..<min(offset + chunkSize, snapshot.count)])
                    var line = try JSONSerialization.data(withJSONObject: [
                        "timestamp": timestamp, "event": event, "rows": batch
                    ])
                    line.append(10)
                    self.append(line, detailed: true)
                } catch {
                    self.writeFailed = true
                }
            }
        }
    }

    private func clearDetailedFiles() -> Bool {
        guard let folder = directory?.appendingPathComponent("detailed") else { return false }
        var succeeded = true
        for name in detailedFileNames {
            let url = folder.appendingPathComponent(name)
            guard files.fileExists(atPath: url.path) else { continue }
            do {
                try files.removeItem(at: url)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }

    private func excludeFromBackup() -> Bool {
        guard var root = directory?.deletingLastPathComponent() else { return false }
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try root.setResourceValues(values)
            backupExcluded = true
            return true
        } catch {
            backupExcluded = false
            return false
        }
    }

    private func append(_ line: Data, detailed: Bool) {
        guard let directory else {
            writeFailed = true
            return
        }
        let folder = detailed ? directory.appendingPathComponent("detailed") : directory
        let file = folder.appendingPathComponent(detailed ? detailedFileNames[0] : "yucheng-native.log")
        let previous = folder.appendingPathComponent(detailed ? detailedFileNames[1] : "yucheng-native.previous.log")
        let limit = (detailed ? 384 : 128) * 1024
        guard line.count <= limit else {
            writeFailed = true
            return
        }
        do {
            if !backupExcluded, !excludeFromBackup() {
                writeFailed = true
                return
            }
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if files.fileExists(atPath: file.path) {
                let attributes = try files.attributesOfItem(atPath: file.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                if size + line.count > limit {
                    if files.fileExists(atPath: previous.path) {
                        try files.removeItem(at: previous)
                    }
                    try files.moveItem(at: file, to: previous)
                }
            }
            guard let handle = fopen(file.path, "ab") else {
                writeFailed = true
                return
            }
            let written = line.withUnsafeBytes { fwrite($0.baseAddress, 1, line.count, handle) }
            let closed = fclose(handle)
            if written != line.count || closed != 0 {
                writeFailed = true
            }
        } catch {
            writeFailed = true
        }
    }
}
