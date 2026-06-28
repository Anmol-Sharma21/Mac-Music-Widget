//  MenuBarView.swift
//  The menu-bar popover. Runs in the full app context, so it uses REAL Liquid
//  Glass (.glassEffect / .buttonStyle(.glass)) which renders live here. Styled
//  to mirror the widget: full-bleed blurred artwork + scrim, white content,
//  circular glass transport controls.

import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var engine: MusicEngine
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingSettings = false

    private var np: NowPlaying { engine.nowPlaying }

    var body: some View {
        VStack(spacing: 12) {
            if engine.needsAutomationPermission { permissionBanner }

            if showingSettings {
                SettingsView(engine: engine)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                nowPlaying
            }

            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(backdrop)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Backdrop (full-bleed blurred art + scrim, like the widget)

    private var backdrop: some View {
        ZStack {
            if let art = engine.artwork, !reduceTransparency {
                Image(nsImage: art).resizable().scaledToFill().blur(radius: 55)
            } else if reduceTransparency {
                Color(.windowBackgroundColor)
            } else {
                LinearGradient(colors: [.indigo.opacity(0.55), .purple.opacity(0.5), .pink.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Rectangle().fill(.black.opacity(reduceTransparency ? 0 : 0.34))
        }
        .clipped()
    }

    // MARK: - Now playing (white content over the art)

    private var nowPlaying: some View {
        VStack(spacing: 13) {
            header
            progress
            transport
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 14) {
            artworkThumb
            VStack(alignment: .leading, spacing: 3) {
                Text(np.title.isEmpty ? "Nothing Playing" : np.title)
                    .font(.headline).lineLimit(2)
                if !np.artist.isEmpty {
                    Text(np.artist).font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                }
                if !np.album.isEmpty, np.album != np.title {
                    Text(np.album).font(.caption)
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var artworkThumb: some View {
        Group {
            if let art = engine.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.3)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.title)
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }

    // MARK: - Progress (live, interpolated between polls)

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let pos = np.estimatedPosition(at: context.date)
            let dur = max(np.durationSeconds, 0.001)
            VStack(spacing: 4) {
                ProgressView(value: min(pos, dur), total: dur).tint(.white)
                HStack {
                    Text(timeString(pos)).monospacedDigit()
                    Spacer()
                    Text(timeString(np.durationSeconds)).monospacedDigit()
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .opacity(np.source == .none ? 0.3 : 1)
    }

    // MARK: - Transport (minimal white glyphs, native-Music style; reflows when hidden)

    private var transport: some View {
        HStack(spacing: 28) {
            if engine.settings.showShuffle {
                glyphButton("shuffle", size: 17, active: np.isShuffling ?? false) {
                    engine.run(.toggleShuffle)
                }
            }
            glyphButton("backward.fill", size: 28) { engine.run(.previous) }
            glyphButton(np.isPlaying ? "pause.fill" : "play.fill", size: 38) {
                engine.run(.playPause)
            }
            glyphButton("forward.fill", size: 28) { engine.run(.next) }
            if engine.settings.showRepeat {
                let mode = np.repeatMode ?? .off
                glyphButton(mode.symbol, size: 17, active: mode.isActive) {
                    engine.run(.toggleRepeat)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .disabled(np.source == .none)
    }

    @ViewBuilder
    private func glyphButton(_ symbol: String, size: CGFloat,
                             active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                // Soft grey to sit in the glass, not stark white. Brightens when active.
                .foregroundStyle(Color(white: active ? 0.96 : 0.82))
                .frame(width: size + 14, height: size + 14)
                .contentShape(.rect)
                .contentTransition(.symbolEffect(.replace))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .opacity(active || size > 18 ? 1 : 0.7)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape.fill")
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .help(showingSettings ? "Back" : "Settings")

            Text(showingSettings ? "Settings" : np.source.displayName)
                .font(.caption).foregroundStyle(.white.opacity(0.75))

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
        .foregroundStyle(.white)
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
