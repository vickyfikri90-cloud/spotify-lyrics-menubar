import Foundation

enum LyricDisplay {
    static let preLyricCountdownStart: TimeInterval = 10
    static let preLyricCountdownMid: TimeInterval = 3

    static func isInstrumentalMarker(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♪", with: "")
            .trimmingCharacters(in: .whitespaces)
            .isEmpty
    }

    static func syncedStatus(lyrics: [LyricLine], at position: Double, source: String?) -> String {
        if source == "ytmusic" {
            return ytmSyncedStatus(lyrics: lyrics, at: position)
        }
        return standardSyncedStatus(lyrics: lyrics, at: position)
    }

    static func standardSyncedStatus(lyrics: [LyricLine], at position: Double) -> String {
        var currentLine = ""
        for line in lyrics {
            if line.time <= position {
                currentLine = line.text
            } else {
                break
            }
        }

        if currentLine.isEmpty {
            guard let firstTime = lyrics.first?.time, position < firstTime else {
                return "..."
            }
            return preLyricCountdown(at: position, targetTime: firstTime, maxCountdown: preLyricCountdownStart)
        }
        return currentLine
    }

    static func ytmSyncedStatus(lyrics: [LyricLine], at position: Double) -> String {
        let lastLine = lyrics.last { $0.time <= position }
        let lastVocal = lyrics.last { $0.time <= position && !isInstrumentalMarker($0.text) }
        let nextVocal = lyrics.first { $0.time > position && !isInstrumentalMarker($0.text) }

        if let lastLine, !isInstrumentalMarker(lastLine.text) {
            return lastLine.text
        }

        if let nextVocal {
            let maxCountdown = lastVocal == nil ? preLyricCountdownStart : preLyricCountdownMid
            return preLyricCountdown(at: position, targetTime: nextVocal.time, maxCountdown: maxCountdown)
        }

        return "..."
    }

    static func preLyricCountdown(at position: Double, targetTime: Double, maxCountdown: TimeInterval) -> String {
        guard position < targetTime else { return "..." }
        let remaining = targetTime - position
        if remaining > maxCountdown { return "..." }
        return countdownDisplay(seconds: max(1, Int(ceil(remaining))))
    }

    static func countdownDisplay(seconds: Int) -> String {
        switch seconds {
        case 1: return "●"
        case 2: return "● ●"
        case 3: return "● ● ●"
        default: return String(seconds)
        }
    }
}
