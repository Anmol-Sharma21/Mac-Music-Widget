//  MusicWidget.swift
//  The WidgetKit widget. macOS 26 draws the Liquid Glass *chrome* around the
//  widget; we provide a full-bleed blurred-artwork background plus frosted
//  Material panels (real .glassEffect() is currently buggy inside widgets, so
//  we don't use it here). The view adapts its controls to the widget size.

import WidgetKit
import SwiftUI
import AppKit
import AppIntents

// MARK: - Timeline

// NOTE: the entry holds ONLY the Codable NowPlaying — no Image. WidgetKit
// serializes timeline entries, and a SwiftUI Image does NOT survive that round
// trip (it comes back nil), which is why the artwork vanished. The artwork is
// loaded from the shared container in the VIEW at render time instead.
struct MusicEntry: TimelineEntry {
    let date: Date
    let nowPlaying: NowPlaying
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry {
        MusicEntry(date: Date(), nowPlaying: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        let entry = currentEntry()
        let np = entry.nowPlaying

        // Safety-net refresh in 30s; if playing, also refresh just after the
        // track is projected to finish so we pick up the next song promptly. The
        // host reloads us immediately on real changes — this is only a fallback.
        var reload = Date().addingTimeInterval(30)
        if np.isPlaying, np.durationSeconds > 0 {
            reload = min(reload, np.projectedEndDate(from: Date()).addingTimeInterval(1))
        }
        completion(Timeline(entries: [entry], policy: .after(reload)))
    }

    private func currentEntry() -> MusicEntry {
        MusicEntry(date: Date(), nowPlaying: SharedStore.readNowPlaying() ?? .nothing)
    }
}

/// Loads the current artwork from the shared container at render time.
/// Returns nil when there's no art file (track has none / nothing playing).
func loadArtworkImage(for np: NowPlaying) -> Image? {
    guard np.source != .none,
          let url = SharedStore.artworkFileURL,
          FileManager.default.fileExists(atPath: url.path),
          let nsImage = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: nsImage)
}

// MARK: - Widget

struct MusicGlassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: Provider()) { entry in
            MusicWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ArtworkBackground(artwork: loadArtworkImage(for: entry.nowPlaying))
                }
        }
        .configurationDisplayName("MusicGlass")
        .description("Now Playing from Apple Music & Spotify, wrapped in Liquid Glass.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Background

/// Full-bleed blurred artwork (or a gradient) with a legibility scrim. The
/// system applies its Liquid Glass container chrome on top of this.
private struct ArtworkBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let artwork: Image?

    var body: some View {
        ZStack {
            if let artwork, !reduceTransparency {
                artwork
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .overlay(.black.opacity(0.28))
            } else if reduceTransparency {
                Color(.windowBackgroundColor)
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.6), .purple.opacity(0.5), .pink.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

// MARK: - Adaptive content

struct MusicWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MusicEntry

    private var np: NowPlaying { entry.nowPlaying }
    private var artwork: Image? { loadArtworkImage(for: np) }

    var body: some View {
        switch family {
        case .systemSmall:  smallLayout
        case .systemMedium: mediumLayout
        default:            largeLayout
        }
    }

    // Small: cover + title + a single play/pause control.
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover(size: 44)
            Spacer(minLength: 0)
            Text(np.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(np.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Spacer()
                playPauseButton(diameter: 38, glyph: 16)
            }
        }
        .foregroundStyle(.white)
    }

    // Medium: cover beside metadata + live progress bar + transport with seek.
    private var mediumLayout: some View {
        HStack(spacing: 14) {
            cover(size: 76)
            VStack(alignment: .leading, spacing: 6) {
                metadata
                Spacer(minLength: 0)
                seekBar
                transportRow(diameter: 28, glyph: 12)
                    .frame(maxWidth: .infinity)   // center the 3 buttons under the bar
            }
        }
        .foregroundStyle(.white)
    }

    // Large / extra-large: cover + metadata + live progress + full transport.
    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                cover(size: family == .systemExtraLarge ? 150 : 110)
                VStack(alignment: .leading, spacing: 6) {
                    sourceBadge
                    metadata
                }
                Spacer(minLength: 0)
            }
            seekBar
            transportRow(diameter: 46, glyph: 18)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Pieces

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(np.title).font(.headline).lineLimit(2)
            Text(np.artist).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            if !np.album.isEmpty {
                Text(np.album).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
        }
    }

    private var sourceBadge: some View {
        Label(np.source.displayName,
              systemImage: np.source == .spotify ? "music.note.list" : "music.note")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.black.opacity(0.30), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }

    private func cover(size: CGFloat) -> some View {
        Group {
            if let art = artwork {
                art.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .id(np.trackKey)                       // new identity per track…
        .transition(.opacity.combined(with: .scale(scale: 0.94)))  // …so it crossfades
    }

    private var seekSegments: Int { 24 }

    /// A long progress bar you can TAP anywhere on to jump to that spot. Widgets
    /// can't drag/slide, so the bar is overlaid with invisible segment buttons,
    /// each seeking to its fraction of the track.
    @ViewBuilder private var seekBar: some View {
        if np.source != .none, np.durationSeconds > 0 {
            VStack(spacing: 4) {
                ZStack {
                    // Animated fill — interpolated live by WidgetKit while playing.
                    Group {
                        if np.isPlaying {
                            ProgressView(timerInterval: np.projectedStartDate...np.projectedEndDate(from: entry.date),
                                         countsDown: false)
                                .labelsHidden()
                        } else {
                            ProgressView(value: min(np.positionSeconds, np.durationSeconds),
                                         total: np.durationSeconds)
                        }
                    }
                    .tint(.white)
                    .frame(maxHeight: .infinity, alignment: .center)

                    // Tap-to-seek overlay.
                    HStack(spacing: 0) {
                        ForEach(0..<seekSegments, id: \.self) { i in
                            Button(intent: SeekToPositionIntent(fraction: (Double(i) + 0.5) / Double(seekSegments))) {
                                Color.clear.contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(height: 16)

                HStack {
                    // Live elapsed: Text(timerInterval:) counts up in real time,
                    // anchored to wall-clock, so it stays correct without reloads.
                    Group {
                        if np.isPlaying {
                            Text(timerInterval: np.projectedStartDate...np.projectedEndDate(from: entry.date),
                                 countsDown: false)
                        } else {
                            Text(timeString(np.positionSeconds))
                        }
                    }
                    .monospacedDigit()
                    .contentTransition(.numericText())   // digits roll smoothly
                    Spacer()
                    Text(timeString(np.durationSeconds)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private func transportRow(diameter: CGFloat, glyph: CGFloat) -> some View {
        HStack(spacing: diameter * 0.5) {
            intentButton(PreviousTrackIntent(), symbol: "backward.fill", diameter: diameter, glyph: glyph)
            playPauseButton(diameter: diameter * 1.15, glyph: glyph * 1.2)
            intentButton(NextTrackIntent(), symbol: "forward.fill", diameter: diameter, glyph: glyph)
        }
        .disabled(np.source == .none)
    }

    private func playPauseButton(diameter: CGFloat, glyph: CGFloat) -> some View {
        intentButton(PlayPauseIntent(),
                     symbol: np.isPlaying ? "pause.fill" : "play.fill",
                     diameter: diameter, glyph: glyph)
    }

    private func intentButton<I: AppIntent>(_ intent: I, symbol: String,
                                            diameter: CGFloat, glyph: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .bold))
                .contentTransition(.symbolEffect(.replace.downUp))  // play⇄pause morphs
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .frame(width: diameter, height: diameter)
                // Dark translucent disc (NOT .ultraThinMaterial, which renders
                // near-white in a widget and hides white glyphs).
                .background(Circle().fill(.black.opacity(0.30)))
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
