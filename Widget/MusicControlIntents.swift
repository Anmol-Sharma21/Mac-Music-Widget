//  MusicControlIntents.swift
//  App Intents backing the widget's transport buttons.
//
//  CRITICAL: a sandboxed widget extension CANNOT reliably send Apple Events to
//  Music/Spotify (denied with -1743, and it can't even raise the TCC prompt).
//  So these intents do only sandbox-safe work: stash the command in the App
//  Group and post a Darwin notification. The running host agent performs the
//  actual control. We render optimistic state via a reload.

import AppIntents
import WidgetKit
import Foundation

private func dispatch(_ action: PlaybackCommand.Action, value: Double? = nil) {
    let command = PlaybackCommand(
        action: action,
        target: .active,
        value: value,
        timestamp: Date().timeIntervalSince1970
    )
    SharedStore.enqueueCommand(command)
    SharedStore.postCommandNotification()
    WidgetCenter.shared.reloadAllTimelines()
}

struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play / Pause"
    func perform() async throws -> some IntentResult {
        dispatch(.playPause)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    func perform() async throws -> some IntentResult {
        dispatch(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    func perform() async throws -> some IntentResult {
        dispatch(.previous)
        return .result()
    }
}

/// Seek to a fraction (0...1) of the track — used by the tappable progress bar.
/// Each invisible segment of the bar carries a different fraction.
struct SeekToPositionIntent: AppIntent {
    static let title: LocalizedStringResource = "Seek To Position"

    @Parameter(title: "Fraction") var fraction: Double

    init() {}
    init(fraction: Double) { self.fraction = fraction }

    func perform() async throws -> some IntentResult {
        dispatch(.seekTo, value: fraction)
        return .result()
    }
}
