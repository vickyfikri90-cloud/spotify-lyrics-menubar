# Lyrics Menu Bar

A lightweight native macOS menu bar app that shows time-synced lyrics for the song currently playing in **Spotify** or **Apple Music** — no login, no API key, no setup beyond a couple of clicks.

![macOS](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

Built natively with Swift + AppKit. Uses ~50 MB of RAM, negligible CPU.

---

## Download & Install (for everyone)

You don't need to install Xcode, Python, or anything else. Just download the app.

### 1. Download the latest release

Head to the [**Releases page**](../../releases/latest) and download **`LyricsMenuBar.dmg`**.

### 2. Install

1. Double-click the downloaded `LyricsMenuBar.dmg`.
2. A small window opens with the app icon and an **Applications** shortcut. **Drag** `LyricsMenuBar` into the **Applications** folder.
3. Eject the disk image (drag it to Trash from the Finder sidebar, or right-click → Eject).

### 3. First launch (important!)

Because this app is open-source and not paid into Apple's $99/year developer program, macOS will refuse to open it the first time and show a warning like:

> *"LyricsMenuBar" cannot be opened because Apple cannot check it for malicious software.*

That's just macOS being cautious — it doesn't mean anything is wrong. To open the app the first time:

1. Open **Finder → Applications**.
2. **Right-click** (or Control-click) on `LyricsMenuBar` → choose **Open**.
3. A new dialog appears with an **Open** button — click it.
4. From now on, the app launches normally.

> If you instead see *"LyricsMenuBar is damaged and can't be opened"*, your browser stripped the signature during download. Fix it with this command in **Terminal**:
> ```bash
> xattr -cr /Applications/LyricsMenuBar.app
> ```
> Then try the right-click → Open step again.

### 4. Grant permission to read Spotify / Music

The first time you play a song, macOS will pop up:

> *"LyricsMenuBar" wants access to control "Spotify".*

Click **OK**. (Same dialog appears for the Music app if you use that.)

You can review or revoke this later in **System Settings → Privacy & Security → Automation**.

### 5. Auto-start at login (optional)

Want the app to launch every time you log in?

1. Open **System Settings → General → Login Items & Extensions**.
2. Under **Open at Login**, click **+** and choose `LyricsMenuBar.app`.

Done.

---

## How It Works

- Reads the current track, artist, and playback position via AppleScript from whichever app is active (Spotify or the macOS Music app).
- If both are running, prefers the one that is actually playing.
- Fetches synced lyrics from [lrclib.net](https://lrclib.net) (falls back to plain lyrics with estimated timing when no synced version exists).
- Updates the menu bar title in real time as the song progresses.

## Menu Actions

Click the lyric in the menu bar to open the menu:

| Item | Action |
| --- | --- |
| **Now Playing** | Shows the current track and source (`[Spotify]` or `[Music]`). |
| **Refresh Lyrics** | Force a refetch — useful when the wrong song was matched. |
| **Quit** | Quit the app. |

---

## Troubleshooting

**Nothing appears in the menu bar.**
Check the process is running: open Terminal and run `pgrep -f LyricsMenuBar`. If it's empty, launch the app from `/Applications` again and watch for any macOS dialogs.

**Title stuck at "Loading lyrics…".**
The track probably isn't on lrclib.net. Click the icon → **Refresh Lyrics**. Or test the API in Terminal:

```bash
curl "https://lrclib.net/api/get?track_name=SONG&artist_name=ARTIST&duration=240"
```

If it returns `404`, the song isn't in lrclib's database yet — you can [contribute it](https://lrclib.net/publish).

**Title shows "♪ (no lyrics found)".**
Same as above — lrclib doesn't have lyrics for that track yet.

**"LyricsMenuBar" can't control Spotify / Music.**
Open **System Settings → Privacy & Security → Automation** and tick the **Spotify** (and/or **Music**) checkbox under `LyricsMenuBar`. If you don't see it listed, quit and relaunch the app — macOS will prompt again.

**Lyrics are out of sync.**
- For synced LRC lyrics, timing comes from lrclib — try **Refresh Lyrics**; a better version may exist.
- For plain lyrics (fallback), the app distributes lines evenly across the track duration, so accuracy is approximate.

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
├── Sources/LyricsMenuBar/
│   ├── main.swift                           # Entry point + AppDelegate
│   ├── MenuBarController.swift              # NSStatusItem + timer + menu
│   ├── PlayerReader.swift                   # AppleScript bridge to Spotify/Music
│   └── LyricsFetcher.swift                  # HTTP to lrclib.net + LRC parser
└── LyricsMenuBar.app/                       # Built bundle (gitignored)
```

### Configuration

Tweak the constants at the top of [`Sources/LyricsMenuBar/MenuBarController.swift`](Sources/LyricsMenuBar/MenuBarController.swift):

| Constant | Purpose |
| --- | --- |
| `placeholder` | Text shown when nothing is playing |
| `maxChars` | Max characters shown in the menu bar before truncation |
| `pollInterval` | How often (seconds) to refresh the displayed lyric line |
| `trackCheckInterval` | How often (seconds) to check whether the track changed |

To add or remove player sources, edit `PlayerReader.players` in [`Sources/LyricsMenuBar/PlayerReader.swift`](Sources/LyricsMenuBar/PlayerReader.swift). Rebuild after editing.

---

## Advanced: Auto-Restart with LaunchAgent

If you want the app to restart automatically when it crashes or gets quit (more aggressive than Login Items), register it as a LaunchAgent.

### 1. Create the plist

Save this as `~/Library/LaunchAgents/com.user.lyricsmenubar.plist`. **Replace `/Users/YOURNAME` with your actual home directory.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.lyricsmenubar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/LyricsMenuBar.app/Contents/MacOS/LyricsMenuBar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/YOURNAME/Library/Logs/LyricsMenuBar/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOURNAME/Library/Logs/LyricsMenuBar/stderr.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

### 2. Load it

```bash
mkdir -p ~/Library/Logs/LyricsMenuBar
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.lyricsmenubar.plist
```

### 3. Management

| Action | Command |
| --- | --- |
| Stop and unload | `launchctl bootout gui/$(id -u)/com.user.lyricsmenubar` |
| Restart | `launchctl kickstart -k gui/$(id -u)/com.user.lyricsmenubar` |
| Tail logs | `tail -f ~/Library/Logs/LyricsMenuBar/stderr.log` |

> `KeepAlive: true` makes launchd restart the app no matter how it exits. To truly stop it, use `launchctl bootout` — `kill` alone will be undone within a second.

---

## Notes

- Lyrics availability depends on the [lrclib.net](https://lrclib.net) community database; some tracks may not be found.
- The app polls Spotify/Music locally via AppleScript — your listening data never leaves your machine.
- CPU usage is negligible (~0.4%); memory is ~50 MB resident.
- Built with Swift 6 + AppKit. No Python, no Electron, no Node.
