import Cocoa

final class MenuBarController {
    private let placeholder = "♪ Lyrics"
    private let maxChars = 70
    private let pollInterval: TimeInterval = 0.5

    private let statusItem: NSStatusItem
    private let nowPlayingItem: NSMenuItem

    private var currentTrackID: String?
    private var lyrics: [LyricLine] = []
    private var lastDisplayed: String = ""

    private var pollTimer: Timer?
    private let pollQueue = DispatchQueue(label: "lyrics.poll", qos: .userInitiated)
    private let fetchQueue = DispatchQueue(label: "lyrics.fetch", qos: .utility)

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

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        DispatchQueue.main.async { [weak self] in self?.poll() }
    }

    @objc private func forceRefresh() {
        currentTrackID = nil
        lyrics = []
        lastDisplayed = ""
    }

    private func poll() {
        pollQueue.async { [weak self] in
            let state = PlayerReader.currentState()
            DispatchQueue.main.async {
                self?.handle(state: state)
            }
        }
    }

    private func handle(state: PlayerState?) {
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

        if state.id != currentTrackID {
            currentTrackID = state.id
            lyrics = []
            lastDisplayed = ""
            nowPlayingItem.title = "♪ [\(state.source)] \(state.track) — \(state.artist)"
            statusItem.button?.title = "Loading lyrics..."
            startFetch(track: state.track, artist: state.artist, duration: state.duration, trackID: state.id)
            return
        }

        guard state.playing, !lyrics.isEmpty else { return }

        var currentLine = ""
        for line in lyrics {
            if line.time <= state.position {
                currentLine = line.text
            } else {
                break
            }
        }

        if currentLine.isEmpty {
            if !lastDisplayed.isEmpty {
                statusItem.button?.title = placeholder
                lastDisplayed = ""
            }
            return
        }

        guard currentLine != lastDisplayed else { return }
        var display = currentLine
        if display.count > maxChars {
            display = String(display.prefix(maxChars - 1)) + "…"
        }
        statusItem.button?.title = display
        lastDisplayed = currentLine
    }

    private func startFetch(track: String, artist: String, duration: Double, trackID: String) {
        fetchQueue.async { [weak self] in
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
}
