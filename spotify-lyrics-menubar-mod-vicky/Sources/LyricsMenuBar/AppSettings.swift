import Foundation

enum AppSettings {
    private static let syncOffsetKey = "lyricsSyncOffsetSeconds"

    static var syncOffsetSeconds: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: syncOffsetKey) as? Int ?? 0
            return min(5, max(-5, stored))
        }
        set {
            UserDefaults.standard.set(min(5, max(-5, newValue)), forKey: syncOffsetKey)
        }
    }
}
