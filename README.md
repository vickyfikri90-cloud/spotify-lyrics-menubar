# Lyrics Menu Bar

A lightweight native macOS menu bar app that shows time-synced lyrics for the song currently playing in **Spotify** or **Apple Music** — no login or API key required.

![macOS](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

Built with Swift + AppKit. Uses ~50 MB of RAM, negligible CPU.

## How It Works

- Reads the current track, artist, and playback position via AppleScript from whichever app is active (Spotify or the macOS Music app).
- If both are running, prefers the one that is actually playing.
- Fetches synced lyrics from [lrclib.net](https://lrclib.net) (falls back to plain lyrics with estimated timing when no synced version exists).
- Updates the menu bar title in real time as the song progresses.

## Requirements

- macOS 12 (Monterey) or newer
- The **Spotify desktop app** and/or the **Music app** (web players are not supported)
- An internet connection (lyrics are fetched on demand)
- **To build from source**: Xcode Command Line Tools (`xcode-select --install`) — no full Xcode required

---

## Quick Start (Build from Source)

### 1. Clone the repo

```bash
git clone https://github.com/<your-fork>/lyrics-menubar.git
cd lyrics-menubar
```

### 2. Build the .app

```bash
./build.sh
```

This runs `swift build -c release`, assembles a `.app` bundle, and applies ad-hoc code signing. Output: `LyricsMenuBar.app` in the project root.

### 3. Move it to /Applications (optional but recommended)

```bash
mv LyricsMenuBar.app /Applications/
```

### 4. Launch

```bash
open /Applications/LyricsMenuBar.app
```

You'll see a `♪ Lyrics` icon appear in the menu bar. Play a song in Spotify or Music and the title updates to the current lyric line.

### 5. Grant Automation permission (first run only)

The first time the app reads playback state, macOS will pop up:

> "LyricsMenuBar" wants access to control "Spotify".

Click **OK**. You can review or change this later in **System Settings → Privacy & Security → Automation**.

> **Note:** Because the build is ad-hoc signed, macOS Gatekeeper may show "cannot be opened" on the first launch. Either right-click → **Open**, or go to **System Settings → Privacy & Security** and click **Open Anyway**.

---

## Auto-Start at Login

The easiest way — no scripts or plists needed:

1. Open **System Settings → General → Login Items & Extensions**.
2. Under **Open at Login**, click `+` and choose `LyricsMenuBar.app`.
3. Done. The app will launch every time you log in.

If you prefer a LaunchAgent (auto-restart on crash, more control), see [Advanced: LaunchAgent](#advanced-launchagent) below.

---

## Menu Actions

Click the menu bar title to open the menu:

| Item | Action |
| --- | --- |
| **Now Playing** | Shows the current track and source (`[Spotify]` or `[Music]`). |
| **Refresh Lyrics** | Force a refetch — useful when the wrong song was matched. |
| **Quit** | Quit the app. |

---

## Configuration

Tweak the constants at the top of [`Sources/LyricsMenuBar/MenuBarController.swift`](Sources/LyricsMenuBar/MenuBarController.swift):

| Constant | Purpose |
| --- | --- |
| `placeholder` | Text shown when nothing is playing |
| `maxChars` | Max characters shown in the menu bar before truncation |
| `pollInterval` | How often (seconds) to refresh the displayed lyric line |
| `trackCheckInterval` | How often (seconds) to check whether the track changed |

To add or remove player sources, edit `PlayerReader.players` in [`Sources/LyricsMenuBar/PlayerReader.swift`](Sources/LyricsMenuBar/PlayerReader.swift).

After editing, rebuild:

```bash
./build.sh
```

---

## Project Layout

```
.
├── Package.swift                            # Swift Package Manager manifest
├── Info.plist                               # Bundle metadata (LSUIElement = background app)
├── build.sh                                 # Compile + assemble .app
├── Sources/LyricsMenuBar/
│   ├── main.swift                           # Entry point + AppDelegate
│   ├── MenuBarController.swift              # NSStatusItem + timer + menu
│   ├── PlayerReader.swift                   # AppleScript bridge to Spotify/Music
│   └── LyricsFetcher.swift                  # HTTP to lrclib.net + LRC parser
└── LyricsMenuBar.app/                       # Built bundle (gitignored)
```

---

## Advanced: LaunchAgent

If you want the app to restart automatically when it crashes or is quit, register it as a LaunchAgent instead of using Login Items.

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

### 2. Create the log directory and load the agent

```bash
mkdir -p ~/Library/Logs/LyricsMenuBar
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.lyricsmenubar.plist
```

### 3. Management commands

| Action | Command |
| --- | --- |
| Stop and unload | `launchctl bootout gui/$(id -u)/com.user.lyricsmenubar` |
| Restart the running app | `launchctl kickstart -k gui/$(id -u)/com.user.lyricsmenubar` |
| Tail logs | `tail -f ~/Library/Logs/LyricsMenuBar/stderr.log` |

> **Important:** `KeepAlive: true` makes the agent restart the app no matter how it exits. If you ever want to truly stop it, use `launchctl bootout` — `kill` alone will be undone within a second.

---

## Troubleshooting

**Nothing appears in the menu bar.**
Check the process is running: `pgrep -f LyricsMenuBar`. If empty, launch again with `open /Applications/LyricsMenuBar.app` and watch for any macOS dialogs.

**"LyricsMenuBar can't be opened because Apple cannot check it for malicious software."**
The build is ad-hoc signed (no developer certificate). Either right-click the `.app` → **Open** and confirm once, or open **System Settings → Privacy & Security** and click **Open Anyway** under the warning.

**Title stuck at "Loading lyrics…".**
The track may not exist on lrclib.net. Click the icon → **Refresh Lyrics**. Or test the API:

```bash
curl "https://lrclib.net/api/get?track_name=SONG&artist_name=ARTIST&duration=240"
```

If you get `404`, the song isn't in the database yet — you can [contribute it](https://lrclib.net/publish).

**Title shows "♪ (no lyrics found)".**
Same as above — lrclib doesn't have it.

**"LyricsMenuBar" can't control Spotify / Music.**
Open **System Settings → Privacy & Security → Automation** and tick the Spotify (and/or Music) checkbox under `LyricsMenuBar`. If you don't see it listed, launch the app fresh so macOS prompts you.

**Lyrics are out of sync.**
- For synced LRC lyrics, the timing comes from lrclib — try **Refresh Lyrics** in case a better version is available.
- For plain lyrics, the app distributes lines evenly across the track duration, so accuracy is approximate.

---

## Notes

- Lyrics availability depends on the [lrclib.net](https://lrclib.net) community database; some tracks may not be found.
- The app polls Spotify/Music locally via AppleScript — your listening data never leaves your machine.
- CPU usage is negligible (~0.4%); memory is ~50 MB resident.
