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
    private let syncOffsetMenuItem: NSMenuItem
    private let syncOffsetLabel: NSTextField
    private let syncOffsetStepper: NSStepper
    private var skipCacheNextFetch = false
    private var isFetching = false

    private var currentTrackID: String?
    private var lastState: PlayerState?
    private var lyrics: [LyricLine] = []
    private var isSyncedLyrics = true
    private var lyricsSource: String?
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
        syncOffsetLabel = NSTextField(labelWithString: "")
        syncOffsetStepper = NSStepper()
        syncOffsetMenuItem = NSMenuItem()
        menuDelegate = MenuBarMenuDelegate()
        super.init()

        statusItem.button?.title = idleTitle
        nowPlayingItem.isEnabled = false
        removeCacheItem.action = #selector(removeCache)
        removeCacheItem.target = self

        configureLyricsMenuItem()
        configureSyncOffsetMenuItem()

        let menu = NSMenu()
        menu.addItem(nowPlayingItem)
        menu.addItem(.separator())
        menu.addItem(lyricsMenuItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Lyrics", action: #selector(forceRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(syncOffsetMenuItem)
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
        lastDisplayed = ""
        pollQueue.async { [weak self] in
            let state = PlayerReader.currentState()
            DispatchQueue.main.async {
                self?.handle(state: state)
            }
        }
    }

    @objc private func syncOffsetChanged(_ sender: NSStepper) {
        AppSettings.syncOffsetSeconds = sender.integerValue
        updateSyncOffsetLabel()
        lastDisplayed = ""
        if let state = lastState, !isFetching, !lyrics.isEmpty {
            updateLyricDisplay(for: state)
        }
    }

    @objc private func removeCache() {
        LyricsCache.removeAll()
        skipCacheNextFetch = true
        currentTrackID = nil
        lyrics = []
        isSyncedLyrics = true
        lyricsSource = nil
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
            lyricsSource = nil
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

        let adjustedPosition = state.position - Double(AppSettings.syncOffsetSeconds)
        let display = truncate(LyricDisplay.syncedStatus(
            lyrics: lyrics,
            at: adjustedPosition,
            source: lyricsSource
        ))

        guard display != lastDisplayed else { return }
        setStatusTitle(display)
        lastDisplayed = display
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
        lyricsSource = nil
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

    private func syncOffsetLabelText() -> String {
        let offset = AppSettings.syncOffsetSeconds
        if offset > 0 {
            return "Sync: +\(offset)s"
        }
        if offset < 0 {
            return "Sync: \(offset)s"
        }
        return "Sync: 0s"
    }

    private func updateSyncOffsetLabel() {
        syncOffsetLabel.stringValue = syncOffsetLabelText()
    }

    private func configureSyncOffsetMenuItem() {
        let containerWidth: CGFloat = 200
        let containerHeight: CGFloat = 24

        syncOffsetLabel.frame = NSRect(x: 12, y: 4, width: 120, height: 16)
        syncOffsetLabel.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        updateSyncOffsetLabel()

        syncOffsetStepper.minValue = -5
        syncOffsetStepper.maxValue = 5
        syncOffsetStepper.increment = 1
        syncOffsetStepper.valueWraps = false
        syncOffsetStepper.autorepeat = true
        syncOffsetStepper.integerValue = AppSettings.syncOffsetSeconds
        syncOffsetStepper.frame = NSRect(x: containerWidth - 60, y: 2, width: 19, height: 22)
        syncOffsetStepper.target = self
        syncOffsetStepper.action = #selector(syncOffsetChanged(_:))

        let view = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        view.addSubview(syncOffsetLabel)
        view.addSubview(syncOffsetStepper)

        syncOffsetMenuItem.view = view
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

    private func applyFetchedLyrics(_ result: LyricsFetchResult, for state: PlayerState) {
        lyrics = result.lines
        isSyncedLyrics = result.isSynced
        lyricsSource = result.source
        plainLyricsText = result.isSynced ? "" : result.lines.map(\.text).joined(separator: "\n")
        lastDisplayed = ""
        updatePlainLyricsMenu()

        if result.lines.isEmpty {
            setStatusTitle("♪ (no lyrics found)")
        } else {
            updateLyricDisplay(for: state)
        }
    }

    private func startFetch(track: String, artist: String, duration: Double, trackID: String) {
        let skipCache = skipCacheNextFetch
        skipCacheNextFetch = false
        fetchQueue.async { [weak self] in
            let result = LyricsFetcher.fetch(
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
                        case .fetchingYTMusic:
                            self.setStatusTitle("Fetching from YouTube...")
                        }
                    }
                }
            )
            DispatchQueue.main.async {
                guard let self = self, self.currentTrackID == trackID else { return }
                self.isFetching = false
                self.updateRemoveCacheTitle()
                if let state = self.lastState, state.id == trackID {
                    self.applyFetchedLyrics(result, for: state)
                } else {
                    self.lyrics = result.lines
                    self.isSyncedLyrics = result.isSynced
                    self.lyricsSource = result.source
                    self.plainLyricsText = result.isSynced ? "" : result.lines.map(\.text).joined(separator: "\n")
                    self.updatePlainLyricsMenu()
                    if result.lines.isEmpty {
                        self.setStatusTitle("♪ (no lyrics found)")
                    }
                }
            }
        }
    }
}
