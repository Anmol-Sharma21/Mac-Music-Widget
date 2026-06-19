//  MusicGlassSettings.swift
//  User preferences, stored in the App Group so BOTH the host (which applies
//  source priority) and the widget (which applies "what to show") can read them.

import Foundation

struct MusicGlassSettings: Codable, Equatable {

    /// Which player wins when more than one is active.
    enum SourcePriority: String, Codable, CaseIterable, Identifiable {
        case auto        // whatever is actually playing (ties → most recent)
        case appleMusic  // always prefer Apple Music when it has a track
        case spotify     // always prefer Spotify when it has a track

        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto:       return "Automatic"
            case .appleMusic: return "Apple Music"
            case .spotify:    return "Spotify"
            }
        }
    }

    var sourcePriority: SourcePriority = .auto

    // What to show in the widget.
    var showAlbum: Bool = true
    var showProgressBar: Bool = true
    var showSourceBadge: Bool = true
    var showArtworkBackground: Bool = true   // blurred album-art backdrop vs. plain gradient

    // Behavior.
    var launchAtLogin: Bool = false

    static let `default` = MusicGlassSettings()
}
