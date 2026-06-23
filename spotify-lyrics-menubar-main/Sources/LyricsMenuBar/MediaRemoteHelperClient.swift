import Foundation

final class MediaRemoteHelperClient {
    static let shared = MediaRemoteHelperClient()

    private let lock = NSLock()
    private var process: Process?
    private var latestPayload: [String: Any]?
    private var hasLatest = false
    private var readThread: Thread?

    private init() {}

    func startIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard process == nil else { return }
        guard let scriptURL = Self.helperScriptURL() else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        proc.arguments = [scriptURL.path]

        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return
        }

        process = proc
        let handle = stdout.fileHandleForReading
        readThread = Thread {
            self.consumeOutput(from: handle)
        }
        readThread?.start()
    }

    func latestSnapshot() -> [String: Any]? {
        startIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return hasLatest ? latestPayload : nil
    }

    private func consumeOutput(from handle: FileHandle) {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let range = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                handleLine(lineData)
            }
        }
    }

    private func handleLine(_ data: Data) {
        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        if line == "null" {
            latestPayload = nil
            hasLatest = true
            return
        }

        guard let json = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return
        }
        latestPayload = object
        hasLatest = true
    }

    private static func helperScriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "MediaRemoteHelper", withExtension: "swift") {
            return bundled
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let devScript = projectRoot.appendingPathComponent("Scripts/MediaRemoteHelper.swift")
        if FileManager.default.fileExists(atPath: devScript.path) {
            return devScript
        }
        return nil
    }
}
