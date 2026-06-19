//  MusicEngine.swift
//  The brain of the host agent. Polls Apple Music / Spotify, publishes the
//  current state for the menu-bar popover, mirrors it into the App Group for the
//  widget, and executes transport commands that arrive from the widget.
//
//  Threading: ALL AppleScript runs on `scriptQueue` (a serial background queue),
//  never on the main thread. A first Apple Event blocks until the user answers
//  the Automation prompt — doing that off-main keeps the UI and timer alive and
//  prevents the widget's XPC connections from dropping.

import Foundation
import AppKit
import WidgetKit
import Combine
import ServiceManagement

@MainActor
final class MusicEngine: ObservableObject {

    @Published private(set) var nowPlaying: NowPlaying = .nothing
    @Published private(set) var artwork: NSImage?
    /// True if Apple Events were denied (-1743): the user hasn't granted
    /// Automation permission yet. The popover surfaces an onboarding banner.
    @Published private(set) var needsAutomationPermission = false
    /// True once we've successfully scripted at least one running player —
    /// i.e. permission is working. Drives the onboarding → now-playing switch.
    @Published private(set) var hasMusicAccess = false
    /// User preferences (source priority, what to show, launch at login).
    /// Bindable from the settings UI; changes persist, re-evaluate, and refresh
    /// the widget. (didSet does NOT fire for the initial loaded value.)
    @Published var settings: MusicGlassSettings = SharedStore.readSettings() {
        didSet {
            guard settings != oldValue else { return }
            SharedStore.writeSettings(settings)
            if settings.launchAtLogin != oldValue.launchAtLogin {
                applyLaunchAtLogin(settings.launchAtLogin)
            }
            // Only re-read the players when the chosen-source logic changes;
            // pure display toggles just need the widget to reload (it re-reads
            // settings itself). Avoids an AppleScript round-trip per toggle.
            if settings.sourcePriority != oldValue.sourcePriority {
                pollAsync(forceReload: true)
            }
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        }
    }

    private let scriptQueue = DispatchQueue(label: "com.anmol.musicglass.script", qos: .userInitiated)
    private var timer: Timer?
    private var isPolling = false
    private var pollToken = 0
    private var lastArtworkTrackKey: String?
    private var preferredSource: NowPlaying.Source = .appleMusic
    private let pollInterval: TimeInterval = 2.0

    // MARK: - Lifecycle

    func start() {
        pollAsync()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollAsync() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling (work happens off-main on scriptQueue)

    func pollAsync(forceReload: Bool = false) {
        guard !isPolling else { return }
        isPolling = true
        pollToken &+= 1
        let token = pollToken
        let preferred = preferredSource
        let priority = settings.sourcePriority
        let lastArtKey = lastArtworkTrackKey

        // Watchdog: a hung/blocked Apple Event must never freeze polling forever.
        // If this attempt hasn't completed in 5s, release the gate so the next
        // Timer tick can retry (the stuck read still drains on the serial queue).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.pollToken == token, self.isPolling else { return }
            self.isPolling = false
        }

        scriptQueue.async { [weak self] in
            let snapshot = MusicEngine.readSnapshot(priority: priority, preferred: preferred, lastArtworkTrackKey: lastArtKey)
            DispatchQueue.main.async {
                guard let self, self.pollToken == token else { return }
                self.apply(snapshot, forceReload: forceReload)
                self.isPolling = false
            }
        }
    }

    // MARK: - Reading (nonisolated; runs on scriptQueue)

    struct Snapshot {
        var nowPlaying: NowPlaying
        var permissionDenied: Bool   // a running player returned -1743
        var accessConfirmed: Bool    // a running player's script ran (permission OK)
        var artwork: ArtworkResult
    }

    enum ArtworkResult {
        case unchanged
        case cleared
        case image(NSImage, Data)   // decoded image + PNG bytes for the container
        case spotify(URL)           // download on the main side
    }

    private enum ReadResult {
        case success(NowPlaying, spotifyArtworkURL: String?)
        case denied
        case empty
    }

    nonisolated static func readSnapshot(priority: MusicGlassSettings.SourcePriority,
                                         preferred: NowPlaying.Source,
                                         lastArtworkTrackKey: String?) -> Snapshot {
        var candidates: [(np: NowPlaying, artURL: String?)] = []
        var permissionDenied = false
        var accessConfirmed = false

        // Run the real read. The first one blocks until the user answers the TCC
        // prompt — fine here because we're on the background scriptQueue, and the
        // app is a normal foreground window so the prompt actually displays.
        for app in [MusicApp.appleMusic, .spotify] where isRunning(app) {
            switch readState(app) {
            case .success(let np, let art): candidates.append((np, art)); accessConfirmed = true
            case .empty:                    accessConfirmed = true   // script ran, nothing playing
            case .denied:                   permissionDenied = true
            }
        }

        let chosen = choose(from: candidates.map(\.np), priority: priority, preferred: preferred) ?? .nothing
        // Spotify artwork URL captured in the SAME read (no second Apple Event).
        let chosenArtURL = candidates.first(where: { $0.np.trackKey == chosen.trackKey })?.artURL

        var artwork: ArtworkResult = .unchanged
        if chosen.trackKey != lastArtworkTrackKey {
            switch chosen.source {
            case .none:
                artwork = .cleared
            case .appleMusic:
                if let data = AppleScriptRunner.runForData(MusicScripts.appleMusicArtwork),
                   let image = NSImage(data: data),
                   let png = pngData(from: image) {
                    artwork = .image(image, png)
                } else {
                    artwork = .cleared
                }
            case .spotify:
                if let urlString = chosenArtURL, let url = URL(string: urlString) {
                    artwork = .spotify(url)
                } else {
                    artwork = .cleared
                }
            }
        }

        return Snapshot(nowPlaying: chosen, permissionDenied: permissionDenied,
                        accessConfirmed: accessConfirmed, artwork: artwork)
    }

    nonisolated static func isRunning(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
    }

    nonisolated static func anyPlayerRunning() -> Bool {
        isRunning(.appleMusic) || isRunning(.spotify)
    }

    nonisolated private static func readState(_ app: MusicApp) -> ReadResult {
        let source = (app == .appleMusic) ? MusicScripts.appleMusicRead : MusicScripts.spotifyRead
        let result: String
        do {
            result = try AppleScriptRunner.run(source)
        } catch {
            return AppleScriptRunner.isPermissionError(error) ? .denied : .empty
        }

        if result == "stopped" || result.isEmpty { return .empty }
        let f = result.components(separatedBy: MusicScripts.sep)
        guard f.count >= 6 else { return .empty }

        let state: NowPlaying.PlaybackState =
            f[0] == "playing" ? .playing : (f[0] == "paused" ? .paused : .stopped)
        let rawDuration = Double(f[5]) ?? 0
        // Spotify reports duration in MILLISECONDS; Apple Music in seconds.
        let duration = (app == .spotify) ? rawDuration / 1000.0 : rawDuration

        // Music:   …dur␟songRepeat␟shuffleEnabled
        // Spotify: …dur␟artworkURL␟repeating␟shuffling
        var isRepeating: Bool?
        var isShuffling: Bool?
        var spotifyArt: String?
        if app == .appleMusic {
            if f.count >= 7 { isRepeating = (f[6] != "off") }
            if f.count >= 8 { isShuffling = (f[7] == "true") }
        } else {
            if f.count >= 7, !f[6].isEmpty { spotifyArt = f[6] }
            if f.count >= 8 { isRepeating = (f[7] == "true") }
            if f.count >= 9 { isShuffling = (f[8] == "true") }
        }

        var np = NowPlaying(
            source: app.source,
            state: state,
            title: f[1],
            artist: f[2],
            album: f[3],
            positionSeconds: Double(f[4]) ?? 0,
            durationSeconds: duration,
            isRepeating: isRepeating,
            isShuffling: isShuffling,
            artworkFilename: SharedStore.artworkFileURL?.lastPathComponent,
            artworkToken: "",
            updatedAt: Date()
        )
        np.artworkToken = np.trackKey
        return .success(np, spotifyArtworkURL: spotifyArt)
    }

    /// Pick which player to show. Explicit priority always prefers that source
    /// when it has a current track; otherwise rank playing > paused > stopped,
    /// breaking ties toward the previously-shown source, then Apple Music.
    nonisolated private static func choose(from candidates: [NowPlaying],
                                           priority: MusicGlassSettings.SourcePriority,
                                           preferred: NowPlaying.Source) -> NowPlaying? {
        guard !candidates.isEmpty else { return nil }
        switch priority {
        case .appleMusic:
            return candidates.first(where: { $0.source == .appleMusic }) ?? candidates.first
        case .spotify:
            return candidates.first(where: { $0.source == .spotify }) ?? candidates.first
        case .auto:
            func rank(_ s: NowPlaying.PlaybackState) -> Int {
                switch s { case .playing: return 2; case .paused: return 1; case .stopped: return 0 }
            }
            return candidates.max { a, b in
                if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
                if a.source == preferred { return false }
                if b.source == preferred { return true }
                return a.source == .spotify  // Apple Music wins the final tie
            }
        }
    }

    nonisolated private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Applying state (main actor)

    private func apply(_ snapshot: Snapshot, forceReload: Bool = false) {
        needsAutomationPermission = snapshot.permissionDenied
        if snapshot.accessConfirmed {
            hasMusicAccess = true
        } else if snapshot.permissionDenied {
            hasMusicAccess = false   // a running player was denied → allow onboarding to reappear
        }

        let previous = nowPlaying
        let next = snapshot.nowPlaying
        if next.source != .none { preferredSource = next.source }
        nowPlaying = next
        SharedStore.writeNowPlaying(next)

        switch snapshot.artwork {
        case .unchanged:
            break
        case .cleared:
            artwork = nil
            lastArtworkTrackKey = next.trackKey
            removeArtworkFile()
        case .image(let image, let png):
            artwork = image
            lastArtworkTrackKey = next.trackKey
            if let url = SharedStore.artworkFileURL { try? png.write(to: url, options: .atomic) }
        case .spotify(let url):
            lastArtworkTrackKey = next.trackKey
            // Clear the previous track's art immediately so the widget shows a
            // placeholder (not the old cover) until the new one downloads.
            artwork = nil
            removeArtworkFile()
            downloadSpotifyArtwork(url, for: next.trackKey)
        }

        let meaningful = forceReload
            || next.trackKey != previous.trackKey
            || next.state != previous.state
            || next.source != previous.source
            || next.isRepeating != previous.isRepeating
            || next.isShuffling != previous.isShuffling
        if meaningful {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        }
    }

    private func downloadSpotifyArtwork(_ url: URL, for trackKey: String) {
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  let png = MusicEngine.pngData(from: image) else { return }
            await MainActor.run {
                guard let self, self.nowPlaying.trackKey == trackKey else { return }
                self.artwork = image
                if let fileURL = SharedStore.artworkFileURL { try? png.write(to: fileURL, options: .atomic) }
                WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
            }
        }
    }

    private func removeArtworkFile() {
        if let url = SharedStore.artworkFileURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Commands (from the widget, or the popover)

    /// Drain ALL pending commands in order (rapid taps no longer collapse to one;
    /// also covers Darwin-notification coalescing where N posts deliver once).
    func executePendingCommand() {
        for command in SharedStore.dequeueAllCommands() {
            execute(command)
        }
    }

    /// Convenience for the popover's own buttons.
    func run(_ action: PlaybackCommand.Action) {
        execute(PlaybackCommand(action: action, target: .active, timestamp: 0))
    }

    func execute(_ command: PlaybackCommand) {
        guard let app = resolve(command.target) else { return }
        let script: String
        switch command.action {
        case .playPause:     script = MusicScripts.control(app, .playPause)
        case .next:          script = MusicScripts.control(app, .nextTrack)
        case .previous:      script = MusicScripts.control(app, .previousTrack)
        case .seekForward:   script = MusicScripts.seek(app, by: 15)
        case .seekBackward:  script = MusicScripts.seek(app, by: -15)
        case .seekTo:
            guard nowPlaying.durationSeconds > 0 else { return }
            let fraction = min(max(command.value ?? 0, 0), 1)
            script = MusicScripts.seekTo(app, position: fraction * nowPlaying.durationSeconds)
        case .toggleRepeat:  script = MusicScripts.setRepeat(app, on: !(nowPlaying.isRepeating ?? false))
        case .toggleShuffle: script = MusicScripts.setShuffle(app, on: !(nowPlaying.isShuffling ?? false))
        }
        scriptQueue.async { [weak self] in
            _ = try? AppleScriptRunner.run(script)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // forceReload guarantees the widget refreshes even for changes
                // (seek/repeat/shuffle) that don't alter track/state/source.
                Task { @MainActor in self?.pollAsync(forceReload: true) }
            }
        }
    }

    private func resolve(_ target: PlaybackCommand.Target) -> MusicApp? {
        switch target {
        case .appleMusic: return .appleMusic
        case .spotify:    return .spotify
        case .active:
            switch nowPlaying.source {
            case .appleMusic: return .appleMusic
            case .spotify:    return .spotify
            case .none:
                if MusicEngine.isRunning(.appleMusic) { return .appleMusic }
                if MusicEngine.isRunning(.spotify)    { return .spotify }
                return nil
            }
        }
    }

    // MARK: - Permission onboarding

    /// Bring the app forward and send a real Apple Event to each running player.
    /// The first send surfaces the Automation (TCC) consent prompt; because the
    /// app is a normal foreground window, the dialog actually displays. Runs on
    /// the background queue since it blocks until the user answers.
    func requestAutomationPermission() {
        NSApp.activate(ignoringOtherApps: true)
        scriptQueue.async { [weak self] in
            for app in [MusicApp.appleMusic, .spotify] where MusicEngine.isRunning(app) {
                let read = (app == .appleMusic) ? MusicScripts.appleMusicRead : MusicScripts.spotifyRead
                _ = try? AppleScriptRunner.run(read)
            }
            DispatchQueue.main.async { Task { @MainActor in self?.pollAsync() } }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MusicGlass: launch-at-login change failed: \(error)")
        }
    }

    /// Opens System Settings → Privacy & Security → Automation as a fallback.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
