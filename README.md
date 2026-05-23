# Spotify Lyrics Menu Bar

A lightweight macOS menu bar app that shows time-synced lyrics for the song currently playing in the Spotify desktop app — no login or API key required.

## How It Works

- Reads the current track, artist, and playback position from Spotify via AppleScript.
- Fetches synced lyrics from [lrclib.net](https://lrclib.net) (falls back to plain lyrics with estimated timing when no synced version exists).
- Updates the menu bar title in real time as the song progresses.

## Requirements

- macOS with the Spotify **desktop app** installed (web player is not supported).
- Python 3.8+

## Install

```bash
pip install -r requirements.txt
```

## Run

```bash
python app.py
```

The current lyric line appears in the menu bar. Click the icon to see the now-playing track or trigger **Refresh Lyrics** if the wrong song was matched.

## Configuration

Tweak the constants at the top of [app.py](app.py):

| Constant | Purpose |
| --- | --- |
| `MAX_CHARS` | Max characters shown in the menu bar before truncation |
| `POLL_INTERVAL` | How often (seconds) to refresh the displayed lyric line |
| `TRACK_CHECK_INTERVAL` | How often (seconds) to check whether the track changed |
| `PLACEHOLDER` | Text shown when nothing is playing |

## Notes

- Lyrics availability depends on the lrclib.net community database; some tracks may not be found.
- Grant Terminal (or your launcher) **Automation** permission for Spotify on first run so AppleScript can read playback state.
