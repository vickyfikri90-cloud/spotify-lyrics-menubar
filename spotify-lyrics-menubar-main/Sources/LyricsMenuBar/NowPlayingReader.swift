import AppKit
import Foundation

enum NowPlayingReader {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    private static let spotifyBundleID = "com.spotify.client"
    private static let musicBundleID = "com.apple.Music"

    private typealias GetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias GetNowPlayingPIDFn =
        @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias GetIsPlayingFn =
        @convention(c) (DispatchQueue, @escaping (DarwinBoolean) -> Void) -> Void

    static func state() -> PlayerState? {
        if let direct = inProcessState() { return direct }
        return helperState()
    }

    private static func helperState() -> PlayerState? {
        guard let payload = MediaRemoteHelperClient.shared.latestSnapshot() else { return nil }
        guard let title = stringValue(payload["title"]), !title.isEmpty else { return nil }

        let artist = stringValue(payload["artist"]) ?? ""
        let duration = numericValue(payload["duration"]) ?? 0
        let position = numericValue(payload["position"]) ?? 0
        let playing = payload["playing"] as? Bool ?? false
        let bundleID = stringValue(payload["bundleID"]) ?? "unknown"
        guard !shouldIgnoreMissingAlbum(
            bundleID: bundleID,
            album: stringValue(payload["album"])
        ) else { return nil }
        let source = displayName(forBundleID: bundleID)

        return PlayerState(
            track: title,
            artist: artist,
            position: max(0, position),
            duration: max(0, duration),
            id: "np:\(bundleID):\(title):\(artist):\(Int(duration))",
            playing: playing,
            source: source
        )
    }

    private static func inProcessState() -> PlayerState? {
        guard let getInfo: GetNowPlayingInfoFn = loadSymbol("MRMediaRemoteGetNowPlayingInfo"),
              let info = fetchNowPlayingInfo(getInfo) else { return nil }

        guard let title = stringValue(info["kMRMediaRemoteNowPlayingInfoTitle"]),
              !title.isEmpty else { return nil }

        let artist = stringValue(info["kMRMediaRemoteNowPlayingInfoArtist"]) ?? ""
        let duration = numericValue(info["kMRMediaRemoteNowPlayingInfoDuration"]) ?? 0
        let position = computeElapsed(from: info)
            ?? numericValue(info["kMRMediaRemoteNowPlayingInfoElapsedTime"])
            ?? 0
        let rate = numericValue(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 0

        var playing = rate > 0
        if !playing, let getIsPlaying: GetIsPlayingFn = loadSymbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            playing = fetchIsPlaying(getIsPlaying)
        }

        let bundleID = fetchBundleID() ?? "unknown"
        guard !shouldIgnoreMissingAlbum(
            bundleID: bundleID,
            album: stringValue(info["kMRMediaRemoteNowPlayingInfoAlbum"])
        ) else { return nil }
        let source = displayName(forBundleID: bundleID)

        return PlayerState(
            track: title,
            artist: artist,
            position: max(0, position),
            duration: max(0, duration),
            id: "np:\(bundleID):\(title):\(artist):\(Int(duration))",
            playing: playing,
            source: source
        )
    }

    private static func loadSymbol<T>(_ name: String) -> T? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func fetchNowPlayingInfo(_ getInfo: GetNowPlayingInfoFn) -> [String: Any]? {
        var result: [String: Any]?
        let semaphore = DispatchSemaphore(value: 0)
        getInfo(DispatchQueue.main) { dict in
            if let dict = dict {
                result = (dict as NSDictionary) as? [String: Any]
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success else { return nil }
        return result
    }

    private static func fetchIsPlaying(_ getIsPlaying: GetIsPlayingFn) -> Bool {
        var playing = false
        let semaphore = DispatchSemaphore(value: 0)
        getIsPlaying(DispatchQueue.main) { value in
            playing = value.boolValue
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success else { return false }
        return playing
    }

    private static func fetchBundleID() -> String? {
        guard let getPID: GetNowPlayingPIDFn = loadSymbol("MRMediaRemoteGetNowPlayingApplicationPID") else {
            return nil
        }
        var pid: Int32 = 0
        let semaphore = DispatchSemaphore(value: 0)
        getPID(DispatchQueue.main) { value in
            pid = value
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func computeElapsed(from info: [String: Any]) -> Double? {
        guard let elapsed = numericValue(info["kMRMediaRemoteNowPlayingInfoElapsedTime"]) else {
            return nil
        }
        let rate = numericValue(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 1
        guard let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date else {
            return elapsed
        }
        return elapsed + rate * Date().timeIntervalSince(timestamp)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let raw = value as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let double as Double: return double
        case let int as Int: return Double(int)
        default: return nil
        }
    }

    private static func isNativePlayerBundle(_ bundleID: String) -> Bool {
        bundleID == spotifyBundleID || bundleID == musicBundleID
    }

    private static func shouldIgnoreMissingAlbum(bundleID: String, album: String?) -> Bool {
        !isNativePlayerBundle(bundleID) && album == nil
    }

    private static func displayName(forBundleID bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        switch bundleID {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Music"
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome": return "Chrome"
        case "com.brave.Browser": return "Brave"
        case "company.thebrowser.Browser": return "Arc"
        default:
            let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
            return last.isEmpty ? "Now Playing" : last
        }
    }
}
