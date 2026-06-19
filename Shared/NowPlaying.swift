//  NowPlaying.swift
//  Shared between the host app and the widget extension.
//
//  This is the single source of truth that the host app writes (after polling
//  Apple Music / Spotify) and the widget reads to render its timeline.

import Foundation

/// A snapshot of the system's current music playback, as observed by the host app.
struct NowPlaying: Codable, Equatable {

    enum Source: String, Codable {
        case appleMusic
        case spotify
        case none

        var displayName: String {
            switch self {
            case .appleMusic: return "Apple Music"
            case .spotify:    return "Spotify"
            case .none:       return "Nothing playing"
            }
        }
    }

    enum PlaybackState: String, Codable {
        case playing
        case paused
        case stopped
    }

    var source: Source
    var state: PlaybackState
    var title: String
    var artist: String
    var album: String

    /// Player position in seconds at the moment `updatedAt` was captured.
    var positionSeconds: Double
    /// Track length in seconds.
    var durationSeconds: Double

    /// Filename of the artwork PNG inside the shared container (nil if none).
    /// The host always writes to a single file and bumps `artworkToken` so the
    /// widget knows to invalidate its cached image.
    var artworkFilename: String?

    /// A stable token identifying the *current track's* artwork. The widget uses
    /// this to decide when to reload the album-art image (it changes per track).
    var artworkToken: String

    /// Wall-clock time the host captured this snapshot. The widget extrapolates
    /// the live position from this for the progress bar/timer.
    var updatedAt: Date

    var isPlaying: Bool { state == .playing }

    /// A stable identity for the current track (source + metadata), independent
    /// of position. Used for artwork-change detection and display de-duping.
    var trackKey: String { "\(source.rawValue)|\(title)|\(artist)|\(album)" }

    /// Live-extrapolated position: where the playhead *should* be right now,
    /// assuming uninterrupted playback since `updatedAt`. Clamped to duration.
    /// The widget can't poll continuously, so it estimates from the last snapshot.
    func estimatedPosition(at now: Date) -> Double {
        guard isPlaying, durationSeconds > 0 else { return min(positionSeconds, durationSeconds) }
        let elapsed = now.timeIntervalSince(updatedAt)
        return min(max(0, positionSeconds + elapsed), durationSeconds)
    }

    /// The wall-clock Date at which the track is projected to end (for a live
    /// countdown via `Text(timerInterval:)` in the widget).
    func projectedEndDate(from now: Date) -> Date {
        let remaining = max(0, durationSeconds - estimatedPosition(at: now))
        return now.addingTimeInterval(remaining)
    }

    /// The wall-clock Date the current track *started* (position 0), projected
    /// from the snapshot. Used to drive `ProgressView(timerInterval:)`.
    var projectedStartDate: Date {
        updatedAt.addingTimeInterval(-positionSeconds)
    }

    static let nothing = NowPlaying(
        source: .none,
        state: .stopped,
        title: "Nothing playing",
        artist: "",
        album: "",
        positionSeconds: 0,
        durationSeconds: 0,
        artworkFilename: nil,
        artworkToken: "none",
        updatedAt: Date()
    )

    /// Static sample used by widget previews and the gallery snapshot.
    static let placeholder = NowPlaying(
        source: .appleMusic,
        state: .playing,
        title: "Liquid Dreams",
        artist: "The Glassworks",
        album: "Refraction",
        positionSeconds: 72,
        durationSeconds: 213,
        artworkFilename: nil,
        artworkToken: "placeholder",
        updatedAt: Date()
    )
}
