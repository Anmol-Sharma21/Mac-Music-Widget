//  MenuBarView.swift
//  The menu-bar popover. This runs in the full app context, so it uses REAL
//  Liquid Glass (.glassEffect / GlassEffectContainer / .buttonStyle(.glass)),
//  which renders live here (unlike inside the widget snapshot).

import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var engine: MusicEngine
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            backdrop
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 14) {
                    if engine.needsAutomationPermission {
                        permissionBanner
                    }
                    if showingSettings {
                        SettingsView(engine: engine)
                            .padding(12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    } else {
                        header
                        progress
                        transport
                    }
                    footer
                }
                .padding(16)
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Backdrop (blurred artwork gives the glass something to refract)

    @ViewBuilder private var backdrop: some View {
        if let art = engine.artwork, !reduceTransparency {
            Image(nsImage: art)
                .resizable()
                .scaledToFill()
                .frame(width: 320, height: 360)
                .blur(radius: 60)
                .opacity(0.55)
                .clipped()
        } else {
            LinearGradient(
                colors: [.purple.opacity(0.35), .blue.opacity(0.25), .pink.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Header (artwork + metadata)

    private var header: some View {
        HStack(spacing: 12) {
            artworkThumb
            VStack(alignment: .leading, spacing: 3) {
                Text(engine.nowPlaying.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(engine.nowPlaying.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !engine.nowPlaying.album.isEmpty {
                    Text(engine.nowPlaying.album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var artworkThumb: some View {
        Group {
            if let art = engine.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Progress (live, interpolated between polls)

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let np = engine.nowPlaying
            let pos = np.estimatedPosition(at: context.date)
            let dur = max(np.durationSeconds, 0.001)
            VStack(spacing: 4) {
                ProgressView(value: min(pos, dur), total: dur)
                    .tint(.primary)
                HStack {
                    Text(timeString(pos)).font(.caption2).monospacedDigit()
                    Spacer()
                    Text(timeString(np.durationSeconds)).font(.caption2).monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
        }
        .opacity(engine.nowPlaying.source == .none ? 0.3 : 1)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 20) {
            controlButton("backward.fill") { engine.run(.previous) }
            controlButton(engine.nowPlaying.isPlaying ? "pause.fill" : "play.fill", large: true) {
                engine.run(.playPause)
            }
            controlButton("forward.fill") { engine.run(.next) }
        }
        .disabled(engine.nowPlaying.source == .none)
    }

    private func controlButton(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 22 : 16, weight: .semibold))
                .frame(width: large ? 52 : 40, height: large ? 52 : 40)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .clipShape(.circle)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "chevron.left.circle.fill" : "gearshape.fill")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "Back" : "Settings")

            if showingSettings {
                Text("Settings").font(.caption).foregroundStyle(.secondary)
            } else {
                Label(engine.nowPlaying.source.displayName,
                      systemImage: engine.nowPlaying.source == .spotify ? "music.note.list" : "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Menu {
                Button("Refresh") { engine.pollAsync() }
                Button("Open Automation Settings") { engine.openAutomationSettings() }
                Divider()
                Button("Quit MusicGlass") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Permission onboarding

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Allow Automation", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text("MusicGlass needs permission to read & control Music and Spotify.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Grant Permission") { engine.requestAutomationPermission() }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 16))
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
