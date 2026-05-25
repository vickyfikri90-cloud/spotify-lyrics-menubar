# Lyrics Menu Bar

A lightweight macOS menu bar app that shows time-synced lyrics for the song currently playing in **Spotify** or **Apple Music** — no login or API key required.

![macOS](https://img.shields.io/badge/macOS-12%2B-blue) ![Python](https://img.shields.io/badge/Python-3.8%2B-yellow)

## How It Works

- Reads the current track, artist, and playback position via AppleScript from whichever app is active (Spotify or the macOS Music app).
- If both are running, prefers the one that is actually playing.
- Fetches synced lyrics from [lrclib.net](https://lrclib.net) (falls back to plain lyrics with estimated timing when no synced version exists).
- Updates the menu bar title in real time as the song progresses.

## Requirements

- macOS 12+ with the **Spotify desktop app** and/or the **Music app** (web players are not supported).
- Python 3.8 or newer (the system `/usr/bin/python3` on recent macOS is fine).
- An internet connection (lyrics are fetched on-demand from lrclib.net).

---

## Quick Start (Manual Run)

Use this if you just want to try the app once before setting up auto-start.

### 1. Clone or download the project

```bash
git clone https://github.com/<your-fork>/lyrics-menubar.git
cd lyrics-menubar
```

Or download the ZIP from GitHub and extract it somewhere stable like `~/Applications/lyrics-menubar`.

### 2. Install Python dependencies

```bash
pip3 install -r requirements.txt
```

If `pip3` is not found, install it with `python3 -m ensurepip --upgrade` or use Homebrew (`brew install python`).

### 3. Run the app

```bash
python3 app.py
```

The current lyric line appears in the menu bar. Click the icon to see the now-playing track (prefixed with `[Spotify]` or `[Music]`) or trigger **Refresh Lyrics** if the wrong song was matched.

### 4. Grant Automation permission (first run only)

The first time the app tries to read playback state, macOS will pop up a dialog like:

> "Python" wants access to control "Spotify".

Click **OK**. You can review or change this later under **System Settings → Privacy & Security → Automation**.

---

## Auto-Start at Login (Recommended)

To make the app start automatically every time you log in — and restart itself if it ever quits — register it as a macOS **LaunchAgent**.

### 1. Make sure the project lives in a stable location

A LaunchAgent runs from a fixed path. Move the folder to somewhere it won't be deleted (e.g. `~/Applications/lyrics-menubar`):

```bash
mkdir -p ~/Applications
mv /path/to/lyrics-menubar ~/Applications/
```

### 2. Create the LaunchAgent plist

Create the file `~/Library/LaunchAgents/com.user.lyricsmenubar.plist` with the following contents. **Replace `/Users/YOURNAME` with your actual home directory** (run `echo $HOME` to check).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.lyricsmenubar</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Users/YOURNAME/Applications/lyrics-menubar/app.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/YOURNAME/Applications/lyrics-menubar</string>

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

Quick reference for the important keys:

| Key | Why it matters |
| --- | --- |
| `RunAtLoad` | Start the app immediately when the LaunchAgent is loaded (i.e. at login). |
| `KeepAlive: true` | Always restart the app if it exits — even after a clean quit. Without this, clicking **Quit** in the menu bar would disable auto-start until your next reboot. |
| `ProcessType: Interactive` | Required for menu bar / GUI processes. |
| `StandardOutPath` / `StandardErrorPath` | Captures logs for troubleshooting. |

### 3. Create the log directory

```bash
mkdir -p ~/Library/Logs/LyricsMenuBar
```

### 4. Load the LaunchAgent

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.lyricsmenubar.plist
```

The app should appear in the menu bar within a second or two.

### 5. Verify it's running

```bash
launchctl print gui/$(id -u)/com.user.lyricsmenubar | grep -E "state|pid"
```

You should see `state = running` and a PID. Done — it will now auto-launch every time you log in.

---

## Managing the LaunchAgent

| Action | Command |
| --- | --- |
| Stop and unload | `launchctl bootout gui/$(id -u)/com.user.lyricsmenubar` |
| Reload after editing the plist | `launchctl bootout gui/$(id -u)/com.user.lyricsmenubar && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.lyricsmenubar.plist` |
| Restart the running app | `launchctl kickstart -k gui/$(id -u)/com.user.lyricsmenubar` |
| Tail logs | `tail -f ~/Library/Logs/LyricsMenuBar/stderr.log` |
| Uninstall | `launchctl bootout gui/$(id -u)/com.user.lyricsmenubar && rm ~/Library/LaunchAgents/com.user.lyricsmenubar.plist` |

---

## Configuration

Tweak the constants at the top of [`app.py`](app.py):

| Constant | Purpose |
| --- | --- |
| `MAX_CHARS` | Max characters shown in the menu bar before truncation |
| `POLL_INTERVAL` | How often (seconds) to refresh the displayed lyric line |
| `TRACK_CHECK_INTERVAL` | How often (seconds) to check whether the track changed |
| `PLACEHOLDER` | Text shown when nothing is playing |
| `PLAYERS` | Player sources to scan. Remove an entry to disable Spotify or Apple Music. |

After editing, restart the app:

```bash
launchctl kickstart -k gui/$(id -u)/com.user.lyricsmenubar
```

---

## Troubleshooting

**Nothing appears in the menu bar.**
Check that the process is running:
```bash
launchctl print gui/$(id -u)/com.user.lyricsmenubar | grep state
```
If it says `not running`, look at the error log:
```bash
tail -50 ~/Library/Logs/LyricsMenuBar/stderr.log
```

**Title is stuck at "Loading lyrics…"**
The track may not exist on lrclib.net, or `fetch_lyrics` is being blocked. Try:
1. Click the menu bar icon → **Refresh Lyrics**.
2. Manually test the API with the current track and artist:
   ```bash
   curl "https://lrclib.net/api/get?track_name=SONG&artist_name=ARTIST&duration=240"
   ```
3. If you get `404`, the song simply isn't in the database yet. You can [contribute it to lrclib](https://lrclib.net/publish).

**Title shows "♪ (no lyrics found)".**
Same as above — the song isn't on lrclib.net.

**"Python" can't control Spotify / Music.**
Open **System Settings → Privacy & Security → Automation** and tick the Spotify (and/or Music) checkbox under `Python`. If you don't see Python listed, run the app manually once (`python3 app.py`) so macOS prompts you for permission.

**Lyrics out of sync.**
- For LRC (synced) lyrics, timing comes from lrclib — try **Refresh Lyrics** in case a different version exists.
- For plainLyrics fallback, the app distributes lines evenly across the track duration, so accuracy depends on the song.

**App keeps respawning after `launchctl bootout`.**
You're hitting `KeepAlive`. Make sure you used `bootout` (which unloads the LaunchAgent), not just killed the process — `kill` alone will be undone by launchd within a second.

---

## Notes

- Lyrics availability depends on the lrclib.net community database; some tracks may not be found.
- The app runs idle in the background when nothing is playing; CPU usage is negligible.
- AppleScript automation is local-only — your listening data never leaves your machine.
