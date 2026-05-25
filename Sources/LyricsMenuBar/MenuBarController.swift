import Cocoa

final class MenuBarController {
    private let placeholder = "♪ Lyrics"
    private let maxChars = 70
    private let pollInterval: TimeInterval = 0.4
    private let trackCheckInterval: TimeInterval = 2.0

    private let statusItem: NSStatusItem
    private let nowPlayingItem: NSMenuItem

    private var currentTrackID: String?
    private var lyrics: [LyricLine] = []
    private var lastDisplayed: String = ""

    private var trackTimer: Timer?
    private var lyricsTimer: Timer?
    private let workQueue = DispatchQueue(label: "lyrics.work", qos: .utility)

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = placeholder

        let menu = NSMenu()
        nowPlayingItem = NSMenuItem(title: "Now Playing: -", action: nil, keyEquivalent: "")
        nowPlayingItem.isEnabled = false
        menu.addItem(nowPlayingItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Lyrics", action: #selector(forceRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu

        trackTimer = Timer.scheduledTimer(withTimeInterval: trackCheckInterval, repeats: true) { [weak self] _ in
            self?.checkTrack()
        }
        lyricsTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.updateLyric()
        }
        DispatchQueue.main.async { [weak self] in self?.checkTrack() }
    }

    @objc private func forceRefresh() {
        currentTrackID = nil
    }

    private func checkTrack() {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let state = PlayerReader.currentState()
            DispatchQueue.main.async {
                self.handleTrackUpdate(state)
            }
        }
    }

    private func handleTrackUpdate(_ state: PlayerState?) {
        guard let state = state else {
            if currentTrackID != nil {
                currentTrackID = nil
                lyrics = []
                lastDisplayed = ""
                statusItem.button?.title = placeholder
                nowPlayingItem.title = "Now Playing: -"
            }
            return
        }
        guard state.id != currentTrackID else { return }

        currentTrackID = state.id
        lyrics = []
        lastDisplayed = ""
        nowPlayingItem.title = "♪ [\(state.source)] \(state.track) — \(state.artist)"
        statusItem.button?.title = "Loading lyrics..."

        let track = state.track
        let artist = state.artist
        let duration = state.duration
        let trackID = state.id
        workQueue.async { [weak self] in
            let (lines, _) = LyricsFetcher.fetch(track: track, artist: artist, duration: duration)
            DispatchQueue.main.async {
                guard let self = self, self.currentTrackID == trackID else { return }
                self.lyrics = lines
                if lines.isEmpty {
                    self.statusItem.button?.title = "♪ (no lyrics found)"
                }
            }
        }
    }

    private func updateLyric() {
        guard !lyrics.isEmpty, currentTrackID != nil else { return }
        let snapshot = lyrics
        workQueue.async { [weak self] in
            guard let state = PlayerReader.currentState(), state.playing else { return }
            var currentLine = ""
            for line in snapshot {
                if line.time <= state.position {
                    currentLine = line.text
                } else {
                    break
                }
            }
            guard !currentLine.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self = self, currentLine != self.lastDisplayed else { return }
                var display = currentLine
                if display.count > self.maxChars {
                    display = String(display.prefix(self.maxChars - 1)) + "…"
                }
                self.statusItem.button?.title = display
                self.lastDisplayed = currentLine
            }
        }
    }
}
