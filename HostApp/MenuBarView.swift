//  MenuBarView.swift
//  The menu-bar popover. Runs in the full app context, so it uses REAL Liquid
//  Glass (.glassEffect / GlassEffectContainer / .buttonStyle(.glass)) which
//  renders live here (unlike inside the widget snapshot).

import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var engine: MusicEngine
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingSettings = false

    private var np: NowPlaying { engine.nowPlaying }

    var body: some View {
        ZStack {
            backdrop
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 12) {
                    if engine.needsAutomationPermission { permissionBanner }

                    if showingSettings {
                        SettingsView(engine: engine)
                            .padding(14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
        .foregroundStyle(.primary)
    }

    // MARK: - Backdrop

    @ViewBuilder private var backdrop: some View {
        if let art = engine.artwork, !reduceTransparency {
            Image(nsImage: art)
                .resizable().scaledToFill()
                .frame(width: 320, height: 380)
                .blur(radius: 70).opacity(0.6)
                .clipped()
        } else {
            LinearGradient(colors: [.purple.opacity(0.4), .blue.opacity(0.28), .pink.opacity(0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            artworkThumb
            VStack(alignment: .leading, spacing: 3) {
                Text(np.title.isEmpty ? "Nothing Playing" : np.title)
                    .font(.headline).lineLimit(2)
                if !np.artist.isEmpty {
                    Text(np.artist).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                if !np.album.isEmpty, np.album != np.title {
                    Label(np.album, systemImage: np.source == .spotify ? "music.note.list" : "music.note")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var artworkThumb: some View {
        Group {
            if let art = engine.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.2), .black.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.title).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }

    // MARK: - Progress (live, interpolated between polls)

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let pos = np.estimatedPosition(at: context.date)
            let dur = max(np.durationSeconds, 0.001)
            VStack(spacing: 4) {
                ProgressView(value: min(pos, dur), total: dur).tint(.primary)
                HStack {
                    Text(timeString(pos)).monospacedDigit()
                    Spacer()
                    Text(timeString(np.durationSeconds)).monospacedDigit()
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .opacity(np.source == .none ? 0.3 : 1)
    }

    // MARK: - Transport (circular Liquid Glass buttons; reflows when hidden)

    private var transport: some View {
        HStack(spacing: 12) {
            if engine.settings.showShuffle {
                glassButton("shuffle", size: 13, prominent: np.isShuffling ?? false) {
                    engine.run(.toggleShuffle)
                }
            }
            glassButton("backward.fill", size: 16) { engine.run(.previous) }
            glassButton(np.isPlaying ? "pause.fill" : "play.fill", size: 22, prominent: true) {
                engine.run(.playPause)
            }
            glassButton("forward.fill", size: 16) { engine.run(.next) }
            if engine.settings.showRepeat {
                let mode = np.repeatMode ?? .off
                glassButton(mode.symbol, size: 13, prominent: mode.isActive) {
                    engine.run(.toggleRepeat)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(np.source == .none)
    }

    @ViewBuilder
    private func glassButton(_ symbol: String, size: CGFloat, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        let label = Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: size * 2.4, height: size * 2.4)
            .contentTransition(.symbolEffect(.replace))
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass).buttonBorderShape(.circle)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape.fill").font(.body)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .help(showingSettings ? "Back" : "Settings")

            Text(showingSettings ? "Settings" : np.source.displayName)
                .font(.caption).foregroundStyle(.secondary)

            Spacer()
            Menu {
                Button("Refresh") { engine.pollAsync() }
                Button("Open Automation Settings…") { engine.openAutomationSettings() }
                Divider()
                Button("Quit MusicGlass") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.circle)
            .fixedSize()
        }
    }

    // MARK: - Permission onboarding

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Allow Automation", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text("MusicGlass needs permission to read & control Music and Spotify.")
                .font(.caption).foregroundStyle(.secondary)
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
