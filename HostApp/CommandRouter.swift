//  CommandRouter.swift
//  Observes the Darwin notification the widget posts when the user taps a
//  transport button, then asks the engine to run the queued command.
//
//  CFNotificationCenter's callback is a C function pointer that cannot capture
//  Swift context, so we route through a singleton. Darwin notifications are
//  delivered on the run loop they were registered on (the main run loop here).

import Foundation

final class CommandRouter: @unchecked Sendable {
    static let shared = CommandRouter()
    private weak var engine: MusicEngine?

    private init() {}

    @MainActor
    func start(engine: MusicEngine) {
        self.engine = engine

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, _, _, _ in commandRouterDidFire() },
            SharedStore.commandNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    fileprivate func fire() {
        Task { @MainActor in self.engine?.executePendingCommand() }
    }
}

/// Free function invoked by the C notification callback.
private func commandRouterDidFire() {
    CommandRouter.shared.fire()
}
