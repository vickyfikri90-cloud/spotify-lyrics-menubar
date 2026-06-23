#!/usr/bin/swift
import Foundation

private let frameworkPath =
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

private typealias GetNowPlayingInfoFn =
    @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
private typealias GetNowPlayingPIDFn =
    @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
private typealias GetIsPlayingFn =
    @convention(c) (DispatchQueue, @escaping (DarwinBoolean) -> Void) -> Void

private func loadSymbol<T>(_ name: String) -> T? {
    guard let handle = dlopen(frameworkPath, RTLD_NOW),
          let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}

private func numericValue(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber: return number.doubleValue
    case let double as Double: return double
    case let int as Int: return Double(int)
    default: return nil
    }
}

private func stringValue(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func computeElapsed(from info: [String: Any]) -> Double? {
    guard let elapsed = numericValue(info["kMRMediaRemoteNowPlayingInfoElapsedTime"]) else {
        return nil
    }
    let rate = numericValue(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 1
    guard let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date else {
        return elapsed
    }
    return elapsed + rate * Date().timeIntervalSince(timestamp)
}

private func fetchIsPlaying(_ getIsPlaying: GetIsPlayingFn) -> Bool {
    var playing = false
    let semaphore = DispatchSemaphore(value: 0)
    getIsPlaying(DispatchQueue.main) { value in
        playing = value.boolValue
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return playing
}

private func fetchBundleID(_ getPID: GetNowPlayingPIDFn) -> String? {
    var pid: Int32 = 0
    let semaphore = DispatchSemaphore(value: 0)
    getPID(DispatchQueue.main) { value in
        pid = value
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    guard pid > 0 else { return nil }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
}

private func snapshot() -> [String: Any]? {
    guard let getInfo: GetNowPlayingInfoFn = loadSymbol("MRMediaRemoteGetNowPlayingInfo") else {
        return nil
    }

    var infoDict: [String: Any]?
    let semaphore = DispatchSemaphore(value: 0)
    getInfo(DispatchQueue.main) { dict in
        if let dict = dict {
            infoDict = (dict as NSDictionary) as? [String: Any]
        }
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }

    guard let info = infoDict,
          let title = stringValue(info["kMRMediaRemoteNowPlayingInfoTitle"]) else {
        return nil
    }

    let artist = stringValue(info["kMRMediaRemoteNowPlayingInfoArtist"]) ?? ""
    let album = stringValue(info["kMRMediaRemoteNowPlayingInfoAlbum"]) ?? ""
    let duration = numericValue(info["kMRMediaRemoteNowPlayingInfoDuration"]) ?? 0
    let position = computeElapsed(from: info)
        ?? numericValue(info["kMRMediaRemoteNowPlayingInfoElapsedTime"])
        ?? 0
    let rate = numericValue(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 0

    var playing = rate > 0
    if !playing, let getIsPlaying: GetIsPlayingFn = loadSymbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
        playing = fetchIsPlaying(getIsPlaying)
    }

    var bundleID = "unknown"
    if let getPID: GetNowPlayingPIDFn = loadSymbol("MRMediaRemoteGetNowPlayingApplicationPID"),
       let fetched = fetchBundleID(getPID) {
        bundleID = fetched
    }

    return [
        "title": title,
        "artist": artist,
        "album": album,
        "duration": max(0, duration),
        "position": max(0, position),
        "playing": playing,
        "bundleID": bundleID
    ]
}

import AppKit

while true {
    if let payload = snapshot(),
       let data = try? JSONSerialization.data(withJSONObject: payload),
       let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    } else {
        print("null")
        fflush(stdout)
    }
    Thread.sleep(forTimeInterval: 0.4)
}
