//  SharedStore.swift
//  The cross-process bridge between the host agent and the widget extension.
//
//  Both targets are sandboxed and share ONE App Group container. On macOS 26 the
//  App Group identifier MUST be Team-ID-prefixed (e.g. "ABCDE12345.group.…").
//  We never hardcode the team ID: the entitlements file uses
//  "$(TeamIdentifierPrefix)group.com.anmol.musicglass" and we read the fully
//  resolved value back at runtime from our own code-signing entitlements.
//
//  Data flow:
//    host  --writes-->  nowplaying.json + artwork.png   (widget reads)
//    widget --writes-->  pendingCommand (UserDefaults)   (host reads & executes)
//           --posts---->  Darwin notification            (wakes the host)

import Foundation
import Security

enum SharedStore {

    /// Reverse-DNS base used for the app group and notification names.
    private static let base = "com.anmol.musicglass"

    /// The fully-resolved, Team-ID-prefixed App Group identifier for THIS process,
    /// read from our own entitlements. Both targets resolve to the same value
    /// because they share a team and an identical entitlement string.
    static let appGroupID: String = resolveAppGroupID()

    /// Darwin notification posted by the widget to wake the host agent.
    static let commandNotificationName = "\(base).command"
    /// Darwin notification the host posts after state changes (optional signal).
    static let stateNotificationName = "\(base).statechanged"

    /// The widget kind string (must match the WidgetConfiguration).
    static let widgetKind = "MusicGlassWidget"

    // MARK: - Containers

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var nowPlayingFileURL: URL? {
        containerURL?.appendingPathComponent("nowplaying.json")
    }

    static var artworkFileURL: URL? {
        containerURL?.appendingPathComponent("artwork.png")
    }

    // MARK: - Now-playing state (host writes, widget reads)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func writeNowPlaying(_ np: NowPlaying) {
        guard let url = nowPlayingFileURL, let data = try? encoder.encode(np) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readNowPlaying() -> NowPlaying? {
        guard let url = nowPlayingFileURL,
              let data = try? Data(contentsOf: url),
              let np = try? decoder.decode(NowPlaying.self, from: data)
        else { return nil }
        return np
    }

    // MARK: - Settings (host writes, both read)

    // Stored as a FILE (not UserDefaults), so the widget always reads the current
    // value — App-Group UserDefaults can serve a stale cached copy across processes.
    static var settingsFileURL: URL? {
        containerURL?.appendingPathComponent("settings.json")
    }

    static func writeSettings(_ settings: MusicGlassSettings) {
        guard let url = settingsFileURL, let data = try? encoder.encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readSettings() -> MusicGlassSettings {
        guard let url = settingsFileURL,
              let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(MusicGlassSettings.self, from: data)
        else { return .default }
        return settings
    }

    // MARK: - Command queue (widget writes, host reads)

    private static let pendingCommandKey = "pendingCommands"

    /// Append a command. Stored as an ORDERED list so rapid taps don't overwrite
    /// each other (the old single-slot key dropped all but the last command).
    static func enqueueCommand(_ command: PlaybackCommand) {
        guard let defaults, let data = try? encoder.encode(command) else { return }
        var list = (defaults.array(forKey: pendingCommandKey) as? [Data]) ?? []
        list.append(data)
        defaults.set(list, forKey: pendingCommandKey)
    }

    /// Reads and clears ALL pending commands in FIFO order (host side).
    static func dequeueAllCommands() -> [PlaybackCommand] {
        guard let defaults,
              let list = defaults.array(forKey: pendingCommandKey) as? [Data]
        else { return [] }
        defaults.removeObject(forKey: pendingCommandKey)
        return list.compactMap { try? decoder.decode(PlaybackCommand.self, from: $0) }
    }

    // MARK: - Darwin notifications

    /// Post the wake signal to the host. Darwin notifications carry no payload —
    /// the actual command travels through `enqueueCommand`.
    static func postCommandNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(commandNotificationName as CFString),
            nil, nil, true)
    }

    static func postStateNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(stateNotificationName as CFString),
            nil, nil, true)
    }

    // MARK: - App Group resolution

    private static func resolveAppGroupID() -> String {
        // Preferred: read the resolved (TeamID-prefixed) value from our own
        // code-signing entitlements. This is correct in both the host and the
        // widget because the linker baked the same expanded string into each.
        if let task = SecTaskCreateFromSelf(nil),
           let value = SecTaskCopyValueForEntitlement(
               task, "com.apple.security.application-groups" as CFString, nil),
           let groups = value as? [String],
           // Require an exact suffix match — don't bind to an unrelated group.
           let first = groups.first(where: { $0.hasSuffix("group.\(base)") }) {
            return first
        }
        // Resolution failed → the entitlement is missing/misnamed and the shared
        // container can't work. Fail loudly instead of silently returning a
        // non-functional (non-Team-ID-prefixed) id that breaks host↔widget sync.
        NSLog("[MusicGlass] FATAL: could not resolve App Group entitlement; shared container unavailable. Check signing/entitlements.")
        assertionFailure("App Group entitlement unresolved")
        return "group.\(base)"
    }
}

/// A transport command sent from the widget to the host agent.
struct PlaybackCommand: Codable, Equatable {
    enum Action: String, Codable {
        case playPause
        case next
        case previous
        case seekForward   // jump the playhead +15s
        case seekBackward  // jump the playhead -15s
        case seekTo        // jump to `value` (0...1 fraction of the track)
        case toggleRepeat  // toggle repeat on/off
        case toggleShuffle // toggle shuffle on/off
    }

    /// The widget always targets `.active` — the host controls whatever source
    /// it most recently reported as now-playing.
    enum Target: String, Codable {
        case active
        case appleMusic
        case spotify
    }

    var action: Action
    var target: Target
    /// Payload for `.seekTo` — a 0...1 fraction of the track duration.
    var value: Double? = nil
    var timestamp: TimeInterval
}
