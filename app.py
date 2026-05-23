import rumps
import subprocess
import requests
import threading
import time
import re
from urllib.parse import quote


# ============ CONFIG (you can change this) ============
MAX_CHARS = 70              # Max characters of the lyric line shown in the menu bar
POLL_INTERVAL = 0.4         # Seconds. How often to check song position (lower = smoother but heavier)
TRACK_CHECK_INTERVAL = 2.0  # Seconds. How often to check if the track changed
PLACEHOLDER = "♪ Lyrics"    # Default text when nothing is playing
# ===================================================================

HEADERS = {
    "User-Agent": "SpotifyLyricsMenuBar v1.0 (personal use)"
}


class SpotifyLyrics(rumps.App):
    def __init__(self):
        super().__init__(PLACEHOLDER, quit_button="Quit")
        self.current_track_id = None
        self.lyrics = []          # List of (timestamp_seconds, line)
        self.is_synced = False
        self.last_displayed = ""
        self.running = True

        # Menu items
        self.menu = [
            rumps.MenuItem("Now Playing: -"),
            None,
            rumps.MenuItem("Refresh Lyrics", callback=self.force_refresh),
        ]

        # Start background threads
        threading.Thread(target=self.track_watcher, daemon=True).start()
        threading.Thread(target=self.lyrics_updater, daemon=True).start()

    # ---------- Spotify via AppleScript ----------
    def applescript(self, script):
        """Run AppleScript and return its output."""
        try:
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True, text=True, timeout=2
            )
            return result.stdout.strip()
        except Exception:
            return ""

    def is_spotify_running(self):
        out = self.applescript('application "Spotify" is running')
        return out == "true"

    def get_spotify_state(self):
        """Return dict: {playing, track, artist, position, duration, id} or None."""
        if not self.is_spotify_running():
            return None
        script = '''
        tell application "Spotify"
            if player state is playing or player state is paused then
                set t to name of current track
                set a to artist of current track
                set p to player position
                set d to (duration of current track) / 1000
                set i to id of current track
                set s to player state as string
                return t & "||" & a & "||" & p & "||" & d & "||" & i & "||" & s
            else
                return ""
            end if
        end tell
        '''
        out = self.applescript(script)
        if not out or "||" not in out:
            return None
        try:
            parts = out.split("||")
            return {
                "track": parts[0],
                "artist": parts[1],
                "position": float(parts[2].replace(",", ".")),
                "duration": float(parts[3].replace(",", ".")),
                "id": parts[4],
                "playing": parts[5] == "playing",
            }
        except (ValueError, IndexError):
            return None

    # ---------- Fetch lyrics from lrclib.net ----------
    def fetch_lyrics(self, track, artist, duration):
        """Fetch synced lyrics from lrclib.net. Return list of (seconds, line)."""
        try:
            # Clean track name (strip "feat.", "(Remastered)", etc. for a better hit rate)
            clean_track = re.sub(r"\s*[\(\[].*?[\)\]]\s*", "", track).strip()
            clean_artist = artist.split(",")[0].strip()  # Use only the first artist

            url = (
                f"https://lrclib.net/api/get"
                f"?track_name={quote(clean_track)}"
                f"&artist_name={quote(clean_artist)}"
                f"&duration={int(duration)}"
            )
            r = requests.get(url, headers=HEADERS, timeout=5)

            # Fallback: if no match with duration, try the search endpoint without it
            if r.status_code != 200:
                url2 = f"https://lrclib.net/api/search?track_name={quote(clean_track)}&artist_name={quote(clean_artist)}"
                r2 = requests.get(url2, headers=HEADERS, timeout=5)
                if r2.status_code == 200 and r2.json():
                    data = r2.json()[0]
                else:
                    return [], False
            else:
                data = r.json()

            synced = data.get("syncedLyrics")
            plain = data.get("plainLyrics")

            if synced:
                return self.parse_lrc(synced), True
            elif plain:
                # Unsynced fallback: distribute lines across the duration with estimated timing
                lines = [l for l in plain.split("\n") if l.strip()]
                if not lines or duration <= 0:
                    return [], False
                step = duration / len(lines)
                return [(i * step, l) for i, l in enumerate(lines)], False
            return [], False
        except Exception:
            return [], False

    def parse_lrc(self, lrc_text):
        """Parse LRC format: [mm:ss.xx] line."""
        result = []
        pattern = re.compile(r"\[(\d+):(\d+\.?\d*)\](.*)")
        for line in lrc_text.split("\n"):
            m = pattern.match(line)
            if m:
                minutes = int(m.group(1))
                seconds = float(m.group(2))
                text = m.group(3).strip()
                total = minutes * 60 + seconds
                if text:  # Skip empty lines
                    result.append((total, text))
        result.sort(key=lambda x: x[0])
        return result

    # ---------- Background threads ----------
    def track_watcher(self):
        """Watch for track changes and fetch new lyrics."""
        while self.running:
            state = self.get_spotify_state()
            if state and state["id"] != self.current_track_id:
                self.current_track_id = state["id"]
                self.menu["Now Playing: -"].title = f"♪ {state['track']} — {state['artist']}"
                self.title = "Loading lyrics..."
                lyrics, synced = self.fetch_lyrics(
                    state["track"], state["artist"], state["duration"]
                )
                self.lyrics = lyrics
                self.is_synced = synced
                if not lyrics:
                    self.title = "♪ (no lyrics found)"
            elif not state:
                self.current_track_id = None
                self.lyrics = []
                self.title = PLACEHOLDER
                self.menu["Now Playing: -"].title = "Now Playing: -"
            time.sleep(TRACK_CHECK_INTERVAL)

    def lyrics_updater(self):
        """Update the menu bar lyric line based on the current song position."""
        while self.running:
            if self.lyrics and self.current_track_id:
                state = self.get_spotify_state()
                if state and state["playing"]:
                    pos = state["position"]
                    current_line = ""
                    for t, line in self.lyrics:
                        if t <= pos:
                            current_line = line
                        else:
                            break
                    if current_line and current_line != self.last_displayed:
                        display = current_line
                        if len(display) > MAX_CHARS:
                            display = display[:MAX_CHARS - 1] + "…"
                        self.title = display
                        self.last_displayed = current_line
            time.sleep(POLL_INTERVAL)

    def force_refresh(self, _):
        """Manual refresh when the matched lyrics are wrong."""
        self.current_track_id = None  # Trigger re-fetch on the next loop iteration


if __name__ == "__main__":
    SpotifyLyrics().run()