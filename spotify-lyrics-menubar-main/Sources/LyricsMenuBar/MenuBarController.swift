import Cocoa

final class MenuBarController: NSObject {
    private let idleTitle = "    "
    private let maxChars = 70
    private let pollInterval: TimeInterval = 0.5
    private let lyricsMenuWidth: CGFloat = 280
    private let lyricsMenuHeight: CGFloat = 240

    private let statusItem: NSStatusItem
    private let nowPlayingItem: NSMenuItem
    private let lyricsMenuItem: NSMenuItem
    private let lyricsTextView: NSTextView
    private let removeCacheItem: NSMenuItem
    private var skipCacheNextFetch = false
    private var isFetching = false

    private let preLyricCountdown: TimeInterval = 3

    private var currentTrackID: String?
    private var lastState: PlayerState?
    private var lyrics: [LyricLine] = []
    private var isSyncedLyrics = true
    private var plainLyricsText = ""
    private var lastDisplayed: String = ""

    private var pollTimer: Timer?
    private let pollQueue = DispatchQueue(label: "lyrics.poll", qos: .userInitiated)
    private let fetchQueue = DispatchQueue(label: "lyrics.fetch", qos: .utility)

    private let menuDelegate: MenuBarMenuDelegate

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        nowPlayingItem = NSMenuItem(title: "Now Playing: -", action: nil, keyEquivalent: "")
        lyricsTextView = NSTextView()
        lyricsMenuItem = NSMenuItem()
        removeCacheItem = NSMenuItem(title: "Remove cache (0 songs)", action: nil, keyEquivalent: "")
        menuDelegate = MenuBarMenuDelegate()
        super.init()

        statusItem.button?.title = idleTitle
        nowPlayingItem.isEnabled = false
        removeCacheItem.action = #selector(removeCache)
        removeCacheItem.target = self

        configureLyricsMenuItem()

        let menu = NSMenu()
        menu.addItem(nowPlayingItem)
        menu.addItem(.separator())
        menu.addItem(lyricsMenuItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Lyrics", action: #selector(forceRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(removeCacheItem)

        menu.addItem(.separator())
        menuDelegate.onWillOpen = { [weak self] in self?.updateRemoveCacheTitle() }
        menu.delegate = menuDelegate
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu

        updateRemoveCacheTitle()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        DispatchQueue.main.async { [weak self] in self?.poll() }
    }

    @objc private func forceRefresh() {
        skipCacheNextFetch = true
        currentTrackID = nil
        lyrics = []
        isSyncedLyrics = true
        plainLyricsText = ""
        lastDisplayed = ""
        updatePlainLyricsMenu()
    }

    @objc private func removeCache() {
        LyricsCache.removeAll()
        skipCacheNextFetch = true
        currentTrackID = nil
        lyrics = []
        isSyncedLyrics = true
        plainLyricsText = ""
        lastDisplayed = ""
        updatePlainLyricsMenu()
        updateRemoveCacheTitle()
    }

    private func removeCacheTitle(count: Int = LyricsCache.count) -> String {
        let noun = count == 1 ? "song" : "songs"
        return "Remove cache (\(count) \(noun))"
    }

    private func updateRemoveCacheTitle() {
        let count = LyricsCache.count
        removeCacheItem.title = removeCacheTitle(count: count)
        removeCacheItem.isEnabled = count > 0
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
        guard let state = state, state.playing else {
            enterIdleState()
            return
        }

        lastState = state

        if state.id != currentTrackID {
            currentTrackID = state.id
            lyrics = []
            isSyncedLyrics = true
            plainLyricsText = ""
            lastDisplayed = ""
            isFetching = true
            nowPlayingItem.title = nowPlayingLabel(for: state)
            updatePlainLyricsMenu()
            setStatusTitle("Fetching..")
            startFetch(track: state.track, artist: state.artist, duration: state.duration, trackID: state.id)
            return
        }

        if isFetching || lyrics.isEmpty {
            return
        }

        updateLyricDisplay(for: state)
    }

    private func updateLyricDisplay(for state: PlayerState) {
        if !isSyncedLyrics {
            let display = artistTrackLabel(for: state)
            guard display != lastDisplayed else { return }
            setStatusTitle(display)
            lastDisplayed = display
            return
        }

        var currentLine = ""
        for line in lyrics {
            if line.time <= state.position {
                currentLine = line.text
            } else {
                break
            }
        }

        let display: String
        if currentLine.isEmpty {
            display = preLyricStatus(at: state.position)
        } else {
            display = truncate(currentLine)
        }

        guard display != lastDisplayed else { return }
        setStatusTitle(display)
        lastDisplayed = display
    }

    private func preLyricStatus(at position: Double) -> String {
        guard let firstTime = lyrics.first?.time, position < firstTime else {
            return "..."
        }
        let remaining = firstTime - position
        if remaining <= preLyricCountdown {
            return String(max(1, Int(ceil(remaining))))
        }
        return "..."
    }

    private func truncate(_ text: String) -> String {
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars - 1)) + "…"
    }

    private func enterIdleState() {
        currentTrackID = nil
        lastState = nil
        lyrics = []
        isSyncedLyrics = true
        plainLyricsText = ""
        lastDisplayed = idleTitle
        isFetching = false
        setStatusTitle(idleTitle)
        nowPlayingItem.title = "Now Playing: -"
        updatePlainLyricsMenu()
    }

    private func setStatusTitle(_ title: String) {
        statusItem.button?.title = title
    }

    private func nowPlayingLabel(for state: PlayerState) -> String {
        let artist = state.artist.trimmingCharacters(in: .whitespaces)
        if artist.isEmpty {
            return "♪ \(state.track)"
        }
        return "♪ \(state.track) — \(artist)"
    }

    private func artistTrackLabel(for state: PlayerState) -> String {
        let artist = state.artist.trimmingCharacters(in: .whitespaces)
        if artist.isEmpty {
            return state.track
        }
        return "\(artist) - \(state.track)"
    }

    private func configureLyricsMenuItem() {
        lyricsTextView.isEditable = false
        lyricsTextView.isSelectable = true
        lyricsTextView.drawsBackground = false
        lyricsTextView.textContainerInset = NSSize(width: 8, height: 8)
        lyricsTextView.textContainer?.widthTracksTextView = true
        lyricsTextView.textContainer?.containerSize = NSSize(
            width: lyricsMenuWidth,
            height: .greatestFiniteMagnitude
        )
        lyricsTextView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: lyricsMenuWidth, height: lyricsMenuHeight))
        scrollView.documentView = lyricsTextView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        lyricsMenuItem.view = scrollView
        lyricsMenuItem.isEnabled = false
        updatePlainLyricsMenu()
    }

    private func updatePlainLyricsMenu() {
        let hasPlainLyrics = !isSyncedLyrics && !plainLyricsText.isEmpty
        lyricsMenuItem.isHidden = !hasPlainLyrics
        guard hasPlainLyrics else {
            lyricsTextView.string = ""
            return
        }
        lyricsTextView.string = plainLyricsText
    }

    private func applyFetchedLyrics(_ lines: [LyricLine], isSynced: Bool, for state: PlayerState) {
        lyrics = lines
        isSyncedLyrics = isSynced
        plainLyricsText = isSynced ? "" : lines.map(\.text).joined(separator: "\n")
        lastDisplayed = ""
        updatePlainLyricsMenu()

        if lines.isEmpty {
            setStatusTitle("♪ (no lyrics found)")
        } else {
            updateLyricDisplay(for: state)
        }
    }

    private func startFetch(track: String, artist: String, duration: Double, trackID: String) {
        let skipCache = skipCacheNextFetch
        skipCacheNextFetch = false
        fetchQueue.async { [weak self] in
            let (lines, isSynced) = LyricsFetcher.fetch(
                track: track,
                artist: artist,
                duration: duration,
                skipCache: skipCache,
                onPhase: { phase in
                    DispatchQueue.main.async {
                        guard let self = self, self.currentTrackID == trackID, self.isFetching else { return }
                        switch phase {
                        case .fetching:
                            self.setStatusTitle("Fetching..")
                        case .searching:
                            self.setStatusTitle("Searching..")
                        }
                    }
                }
            )
            DispatchQueue.main.async {
                guard let self = self, self.currentTrackID == trackID else { return }
                self.isFetching = false
                self.updateRemoveCacheTitle()
                if let state = self.lastState, state.id == trackID {
                    self.applyFetchedLyrics(lines, isSynced: isSynced, for: state)
                } else {
                    self.lyrics = lines
                    self.isSyncedLyrics = isSynced
                    self.plainLyricsText = isSynced ? "" : lines.map(\.text).joined(separator: "\n")
                    self.updatePlainLyricsMenu()
                    if lines.isEmpty {
                        self.setStatusTitle("♪ (no lyrics found)")
                    }
                }
            }
        }
    }
}
