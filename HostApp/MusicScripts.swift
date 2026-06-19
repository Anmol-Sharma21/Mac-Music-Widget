//  MusicScripts.swift
//  AppleScript sources used by the host app to read and control Apple Music
//  and Spotify. These are run via NSAppleScript — no ScriptingBridge codegen
//  and no generated headers required.
//
//  The read scripts return a single string with fields separated by the ASCII
//  Unit Separator (0x1F), which never appears in track metadata. On "stopped"
//  or no-track they return the literal "stopped".
//
//  Verified empirically against Apple Music on macOS 26: position & duration
//  are both in seconds; artwork is `raw data of artwork 1 of current track`
//  (PNG/JPEG bytes). Spotify's `duration` is in MILLISECONDS (sdef says
//  "seconds" but that is wrong) while `player position` is in seconds.

import Foundation

enum MusicApp: String {
    case appleMusic = "Music"
    case spotify    = "Spotify"

    var bundleID: String {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify:    return "com.spotify.client"
        }
    }

    var source: NowPlaying.Source {
        switch self {
        case .appleMusic: return .appleMusic
        case .spotify:    return .spotify
        }
    }
}

enum MusicCommand: String {
    case playPause     = "playpause"
    case nextTrack     = "next track"
    case previousTrack = "previous track"
    case play          = "play"
    case pause         = "pause"
}

enum MusicScripts {

    /// Field separator (ASCII Unit Separator). Never present in metadata.
    static let sep = "\u{1F}"

    // MARK: - Reading state

    /// Apple Music. Returns:
    /// state␟title␟artist␟album␟position␟duration␟songRepeat␟shuffleEnabled
    static let appleMusicRead = #"""
    tell application "Music"
      try
        set pState to (player state as text)
        if pState is "stopped" then return "stopped"
        set trk to current track
        set sep to (ASCII character 31)
        return pState & sep & (name of trk) & sep & (artist of trk) & sep & (album of trk) & sep & (player position as text) & sep & (duration of trk as text) & sep & (song repeat as text) & sep & (shuffle enabled as text)
      on error errMsg number errNum
        return "stopped"
      end try
    end tell
    """#

    /// Spotify. Returns:
    /// state␟title␟artist␟album␟position␟durationMillis␟artworkURL␟repeating␟shuffling
    static let spotifyRead = #"""
    tell application "Spotify"
      try
        set pState to (player state as text)
        if pState is "stopped" then return "stopped"
        set trk to current track
        set sep to (ASCII character 31)
        return pState & sep & (name of trk) & sep & (artist of trk) & sep & (album of trk) & sep & (player position as text) & sep & (duration of trk as text) & sep & (artwork url of trk) & sep & (repeating as text) & sep & (shuffling as text)
      on error errMsg number errNum
        return "stopped"
      end try
    end tell
    """#

    /// Whether a given app is currently running, without launching it.
    static func isRunning(_ app: MusicApp) -> String {
        #"""
        tell application "System Events" to return ((name of processes) contains "\#(app.rawValue)")
        """#
    }

    // MARK: - Artwork

    /// Apple Music: return the current track's artwork as raw image bytes
    /// (descriptor type 'tdta'). The HOST decodes/writes it into its own App
    /// Group container — Music never touches our container (avoids its sandbox).
    /// Verified on macOS 26: returns 'tdta', NSImage decodes 800×800 PNG.
    static let appleMusicArtwork = #"""
    tell application "Music"
      try
        set trk to current track
        if (count of artworks of trk) is 0 then return missing value
        return raw data of artwork 1 of trk
      on error
        return missing value
      end try
    end tell
    """#

    // MARK: - Control

    /// Build a control script for the given app + command.
    static func control(_ app: MusicApp, _ command: MusicCommand) -> String {
        #"""
        tell application "\#(app.rawValue)" to \#(command.rawValue)
        """#
    }

    /// Seek relative to the current playhead by `delta` seconds (player position
    /// is in seconds for BOTH Music and Spotify). Players clamp out-of-range.
    static func seek(_ app: MusicApp, by delta: Double) -> String {
        #"""
        tell application "\#(app.rawValue)" to set player position to (player position + \#(delta))
        """#
    }

    /// Seek to an absolute position in seconds.
    static func seekTo(_ app: MusicApp, position: Double) -> String {
        #"""
        tell application "\#(app.rawValue)" to set player position to \#(position)
        """#
    }

    /// Set repeat mode. Music's `song repeat` takes off/all/one natively;
    /// Spotify's `repeating` is boolean (off → false, all/one → true).
    static func setRepeat(_ app: MusicApp, mode: NowPlaying.RepeatMode) -> String {
        switch app {
        case .appleMusic:
            return #"tell application "Music" to set song repeat to \#(mode.rawValue)"#
        case .spotify:
            return #"tell application "Spotify" to set repeating to \#(mode == .off ? "false" : "true")"#
        }
    }

    /// Toggle shuffle. Music uses `shuffle enabled`; Spotify uses `shuffling`.
    static func setShuffle(_ app: MusicApp, on: Bool) -> String {
        switch app {
        case .appleMusic:
            return #"tell application "Music" to set shuffle enabled to \#(on ? "true" : "false")"#
        case .spotify:
            return #"tell application "Spotify" to set shuffling to \#(on ? "true" : "false")"#
        }
    }
}
