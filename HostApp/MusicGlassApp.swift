//  MusicGlassApp.swift
//  The host agent. It normally runs as a no-Dock menu-bar accessory. It only
//  becomes a regular foreground window app when Automation permission is missing
//  — that's the one situation where a window is required so the macOS consent
//  prompt can actually display. Once access is confirmed it drops the Dock icon
//  again and lives purely in the menu bar.

import SwiftUI
import AppKit
import Combine

@main
struct MusicGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: appDelegate.engine)
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = MusicEngine()
    private var onboardingWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon — menu-bar agent
        engine.start()
        CommandRouter.shared.start(engine: engine)
        engine.executePendingCommand()

        // Show the onboarding window (and a Dock icon) only while permission is
        // missing; hide it the moment we confirm we can read a player.
        engine.$hasMusicAccess
            .combineLatest(engine.$needsAutomationPermission)
            .receive(on: RunLoop.main)
            .sink { [weak self] hasAccess, needsPermission in
                if hasAccess {
                    self?.dismissOnboarding()
                } else if needsPermission {
                    self?.presentOnboarding()
                }
            }
            .store(in: &cancellables)

        // First-run safety net: if we haven't gained access shortly after launch
        // and a player is running, surface the prompt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.engine.hasMusicAccess, MusicEngine.anyPlayerRunning() else { return }
            self.presentOnboarding()
        }
    }

    private func presentOnboarding() {
        guard onboardingWindow == nil else { return }
        NSApp.setActivationPolicy(.regular)   // allow a real foreground window + Dock

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "MusicGlass"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView(engine: engine))
        onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        engine.requestAutomationPermission()
    }

    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        NSApp.setActivationPolicy(.accessory)   // back to a no-Dock menu-bar agent
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false   // keep serving the widget after the onboarding window closes
    }
}
