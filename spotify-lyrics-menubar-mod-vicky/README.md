# Lyrics Menu Bar

A lightweight native macOS menu bar app that shows time-synced lyrics for the song currently playing in **Spotify**, **Apple Music**, **YouTube Music**, or any app that reports to macOS Now Playing — no login, no API key, no setup beyond a couple of clicks.

![macOS](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

Built natively with Swift + AppKit. Uses ~50 MB of RAM, negligible CPU.

---

## Download & Install (for everyone)

You don't need to install Xcode, Python, or anything else. Just download the app.

### 1. Download the latest release

Head to the [**Releases page**](../../releases/latest) and download **`LyricsMenuBar.dmg`**.

### 2. Install
  1. Download `LyricsMenuBar.dmg` below
  2. Open it, drag the app to Applications
  3. Right-click the app in Applications → click "Open Anyway"
  4. If "Open Anyway" button not displayed, go to System Settings -> Privacy & Security
  5. Scroll down until you find this
<img width="476" height="100" alt="Screenshot 2026-05-25 at 20 54 47" src="https://github.com/user-attachments/assets/e85c9461-a168-45b3-87cf-e857b8d4c819" />

6. Click "Open Anyway"
7. Confirm it using your password or touch id
8. Then it should appear "Open Anyway" button like displayed image. Click that
<img width="254" height="342" alt="Screenshot 2026-05-25 at 20 54 54" src="https://github.com/user-attachments/assets/2f29b907-9124-4b9e-82e0-90ee39b27653" />
  
9. And voila it works!
<img width="328" height="133" alt="Screenshot 2026-05-25 at 20 56 48" src="https://github.com/user-attachments/assets/250453c3-39fd-4064-8bbd-bb5e59856bd6" />

### 3. Iimportant!

Because this app is open-source and not paid into Apple's $99/year developer program, macOS will refuse to open it the first time and show a warning like:

> *"LyricsMenuBar" cannot be opened because Apple cannot check it for malicious software.*

That's just macOS being cautious — it doesn't mean anything is wrong.

## How It Works

- Reads track, artist, position, and duration from **Spotify** and **Apple Music** via AppleScript (best track IDs and timing).
- Reads any other Now Playing source (YouTube Music in Safari, Chrome, browser wrappers, etc.) via macOS **MediaRemote**.
- YouTube Music / browser sources use a bundled Swift helper (`/usr/bin/swift`) because macOS blocks MediaRemote for regular app binaries.
- If multiple players are open, prefers the one that is actually playing.
- Fetches lyrics from [lrclib.net](https://lrclib.net) first. If LRCLIB has no synced lyrics (plain text only or nothing found), the app falls back to **YouTube Music** via a lightweight native module (`Sources/YTMusicLyrics/`). When both sources return plain text, the longer version wins. Synced lyrics always beat plain. Results are cached locally by **artist + track** in `~/Library/Application Support/LyricsMenuBar/lyrics-cache.json`.
- Updates the menu bar title in real time as the song progresses.

## Menu Actions

Click the lyric in the menu bar to open the menu:

| Item | Action |
| --- | --- |
| **Now Playing** | Shows the current track and artist. |
| **Refresh Lyrics** | Re-read now playing and resync position/duration — useful when lyrics timing is off or track metadata was stale. Does not re-fetch lyrics. |
| **Remove cache (N songs)** | Clear saved lyrics cache. Count updates when you open the menu. |
| **Quit** | Quit the app. |

---

## Troubleshooting

**Nothing appears in the menu bar.**
Check the process is running: open Terminal and run `pgrep -f LyricsMenuBar`. If it's empty, launch the app from `/Applications` again and watch for any macOS dialogs.

**Title stuck at "Loading lyrics…" or "Fetching from YouTube...".**
The app is looking up lyrics from LRCLIB and/or YouTube Music. Wait a few seconds, or click **Refresh Lyrics**. To test LRCLIB directly in Terminal:

```bash
curl "https://lrclib.net/api/get?track_name=SONG&artist_name=ARTIST&duration=240"
```

If LRCLIB returns `404` and YouTube Music also has no lyrics for that track, the song may genuinely be unavailable.

**Title shows "♪ (no lyrics found)".**
Neither LRCLIB nor YouTube Music returned lyrics for that track. Clear **Remove cache** and skip to another track, then back, if you suspect a bad match.

**"LyricsMenuBar" can't control Spotify / Music.**
Open **System Settings → Privacy & Security → Automation** and tick the **Spotify** (and/or **Music**) checkbox under `LyricsMenuBar`. If you don't see it listed, quit and relaunch the app — macOS will prompt again. YouTube Music and other Now Playing sources do **not** need Automation access.

**YouTube Music / browser wrapper not detected.**
Make sure the song appears in **Control Center → Now Playing** while it plays. If it does, Lyrics Menu Bar can read it. Safari, Chrome, and “Add to Dock” web apps are supported.

**YouTube Music still not detected after rebuild.**
Now Playing uses a helper script that runs via `/usr/bin/swift`. Install Xcode Command Line Tools if needed: `xcode-select --install`. Then rebuild with `./build.sh --no-dmg`, quit the old app, and relaunch from `LyricsMenuBar.app`.

**Lyrics are out of sync.**
- For synced LRC lyrics, timing comes from the player position — try **Refresh Lyrics** to resync now playing if lines are early or late. Use **Sync** in the menu to nudge timing by a few seconds.
- For plain lyrics (fallback), the app shows the full text in the menu; the menu bar shows artist and track instead of scrolling lines.

---

## Build from Source (for developers)

### Requirements

- macOS 12 (Monterey) or newer
- Xcode Command Line Tools: `xcode-select --install`

### Build

```bash
git clone https://github.com/nadialvy/spotify-lyrics-menubar.git
cd spotify-lyrics-menubar
./build.sh
```

This:
1. Runs `swift build -c release`
2. Assembles `LyricsMenuBar.app`
3. Ad-hoc code signs it
4. Produces `LyricsMenuBar.dmg` for distribution

To skip the DMG step (faster during development): `./build.sh --no-dmg`

### Project Layout

```
.
├── Package.swift                            # Swift Package Manager manifest
├── Info.plist                               # Bundle metadata (LSUIElement = background app)
├── build.sh                                 # Compile + assemble .app + create .dmg
├── Sources/
│   ├── LyricsMenuBar/
│   │   ├── main.swift                       # Entry point + AppDelegate
│   │   ├── MenuBarController.swift          # NSStatusItem + timer + menu
│   │   ├── LyricsFetcher.swift              # LRCLIB + YT Music fallback orchestration
│   │   ├── LyricsCache.swift                # Local lyrics cache
│   │   ├── NowPlayingReader.swift           # MediaRemote bridge for any Now Playing app
│   │   └── MediaRemoteHelperClient.swift    # Runs bundled Swift helper subprocess
│   └── YTMusicLyrics/                       # Minimal YT Music lyrics client (Swift native)
│       ├── YTMusicClient.swift              # HTTP + visitor ID bootstrap
│       ├── YTMusicSearch.swift              # Song search → videoId
│       ├── YTMusicLyricsFetcher.swift       # Search → lyrics browseId → synced/plain lyrics
│       └── YTMJSONNav.swift                 # JSON path helper
├── ytmusicapi-main/                         # Dev reference only (not bundled in the app)
├── AppIcon.icon/                            # App icon (Icon Composer); compiled by build.sh
├── Scripts/
│   └── MediaRemoteHelper.swift              # Platform-signed Swift helper for Now Playing
└── LyricsMenuBar.app/                       # Built bundle (gitignored)
```

### Configuration

Tweak the constants at the top of [`Sources/LyricsMenuBar/MenuBarController.swift`](Sources/LyricsMenuBar/MenuBarController.swift):

| Constant | Purpose |
| --- | --- |
| `placeholder` | Text shown when nothing is playing |
| `maxChars` | Max characters shown in the menu bar before truncation |
| `pollInterval` | How often (seconds) to poll the player and refresh the lyric line |

To add or remove player sources, edit `PlayerReader.players` in [`Sources/LyricsMenuBar/PlayerReader.swift`](Sources/LyricsMenuBar/PlayerReader.swift). Rebuild after editing.

--

## Notes

- Lyrics availability depends on [lrclib.net](https://lrclib.net) and YouTube Music; some tracks may not be found on either source.
- The app polls players locally via AppleScript and macOS Now Playing — your listening data never leaves your machine except for lyrics lookups (LRCLIB and YouTube Music).
- CPU usage is negligible (~0.4%); memory is ~50 MB resident.
- Built with Swift 6 + AppKit. No Python, no Electron, no Node.
