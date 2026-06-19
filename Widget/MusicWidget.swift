//  MusicWidget.swift
//  The WidgetKit widget. macOS 26 draws the Liquid Glass *chrome* around the
//  widget; we provide a full-bleed blurred-artwork background plus frosted
//  panels (real .glassEffect() is currently buggy inside widgets). The view
//  adapts to the widget size and to the user's show/hide settings.

import WidgetKit
import SwiftUI
import AppKit
import AppIntents

// MARK: - Timeline

// The entry holds ONLY Codable data (NowPlaying + settings) — never a SwiftUI
// Image, which does NOT survive WidgetKit's entry serialization. Artwork is
// loaded from the shared container in the VIEW at render time. Settings are read
// ONCE here so a single render is internally consistent (and not decoded N times).
struct MusicEntry: TimelineEntry {
    let date: Date
    let nowPlaying: NowPlaying
    let settings: MusicGlassSettings
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry {
        MusicEntry(date: Date(), nowPlaying: .placeholder, settings: .default)
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
        MusicEntry(date: Date(),
                   nowPlaying: SharedStore.readNowPlaying() ?? .nothing,
                   settings: SharedStore.readSettings())
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
        }
        .configurationDisplayName("MusicGlass")
        .description("Now Playing from Apple Music & Spotify, wrapped in Liquid Glass.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Background

/// Full-bleed blurred artwork (or a gradient) with a legibility scrim.
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
    private var settings: MusicGlassSettings { entry.settings }

    var body: some View {
        // Load artwork ONCE per render; reuse for both the cover and the backdrop.
        let art = loadArtworkImage(for: np)
        return content(art: art)
            .foregroundStyle(.white)
            .containerBackground(for: .widget) {
                ArtworkBackground(artwork: settings.showArtworkBackground ? art : nil)
            }
    }

    @ViewBuilder
    private func content(art: Image?) -> some View {
        switch family {
        case .systemSmall:  smallLayout(art: art)
        case .systemMedium: mediumLayout(art: art)
        default:            largeLayout(art: art)
        }
    }

    // Small: cover + title + a single play/pause control.
    private func smallLayout(art: Image?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cover(size: 44, art: art)
            Spacer(minLength: 0)
            Text(np.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(np.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Spacer()
                playPauseButton(diameter: 38, glyph: 16)
            }
        }
    }

    // Medium: a large cover on the left, with text + controls vertically
    // centered beside it. Centering keeps it balanced whether or not the
    // progress bar / shuffle / repeat are shown.
    private func mediumLayout(art: Image?) -> some View {
        HStack(spacing: 16) {
            cover(size: 104, art: art)
            VStack(alignment: .leading, spacing: 7) {
                Spacer(minLength: 0)
                if settings.showSourceBadge { sourceBadge }
                metadata
                if settings.showProgressBar { seekBar }
                transportRow(diameter: 30, glyph: 13)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }

    // Large / extra-large: cover + metadata + (optional) progress + transport,
    // vertically centered so the layout stays balanced when controls are hidden.
    private func largeLayout(art: Image?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                cover(size: family == .systemExtraLarge ? 150 : 110, art: art)
                VStack(alignment: .leading, spacing: 6) {
                    if settings.showSourceBadge { sourceBadge }
                    metadata
                }
                Spacer(minLength: 0)
            }
            if settings.showProgressBar { seekBar }
            transportRow(diameter: 44, glyph: 18)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Pieces

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(np.title).font(.headline).lineLimit(2)
            Text(np.artist).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            if settings.showAlbum, !np.album.isEmpty, np.album != np.title {
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

    private func cover(size: CGFloat, art: Image?) -> some View {
        Group {
            if let art {
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
        .id(np.trackKey)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var seekSegments: Int { 24 }

    /// A long progress bar you can TAP anywhere on to jump to that spot. Widgets
    /// can't drag/slide, so the bar is overlaid with invisible segment buttons,
    /// each seeking to its fraction of the track.
    @ViewBuilder private var seekBar: some View {
        if np.source != .none, np.durationSeconds > 0 {
            VStack(spacing: 4) {
                ZStack {
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
                    Group {
                        if np.isPlaying {
                            Text(timerInterval: np.projectedStartDate...np.projectedEndDate(from: entry.date),
                                 countsDown: false)
                        } else {
                            Text(timeString(np.positionSeconds))
                        }
                    }
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    Spacer()
                    Text(timeString(np.durationSeconds)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    // Transport: optional shuffle · prev · play/pause · next · optional repeat.
    // Hidden controls are omitted entirely, so the row reflows and stays centered.
    private func transportRow(diameter: CGFloat, glyph: CGFloat) -> some View {
        HStack(spacing: diameter * 0.5) {
            if settings.showShuffle {
                toggleButton(ToggleShuffleIntent(), symbol: "shuffle",
                             isOn: np.isShuffling ?? false,
                             diameter: diameter * 0.82, glyph: glyph * 0.85)
            }
            intentButton(PreviousTrackIntent(), symbol: "backward.fill", diameter: diameter, glyph: glyph)
            playPauseButton(diameter: diameter * 1.18, glyph: glyph * 1.2)
            intentButton(NextTrackIntent(), symbol: "forward.fill", diameter: diameter, glyph: glyph)
            if settings.showRepeat {
                let mode = np.repeatMode ?? .off
                toggleButton(ToggleRepeatIntent(), symbol: mode.symbol,
                             isOn: mode.isActive,
                             diameter: diameter * 0.82, glyph: glyph * 0.85)
            }
        }
        .disabled(np.source == .none)
    }

    private func playPauseButton(diameter: CGFloat, glyph: CGFloat) -> some View {
        intentButton(PlayPauseIntent(),
                     symbol: np.isPlaying ? "pause.fill" : "play.fill",
                     diameter: diameter, glyph: glyph)
    }

    /// Plain transport button: white glyph on a dark translucent disc.
    private func intentButton<I: AppIntent>(_ intent: I, symbol: String,
                                            diameter: CGFloat, glyph: CGFloat) -> some View {
        Button(intent: intent) {
            discGlyph(symbol, glyph: glyph, diameter: diameter, isOn: false)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .buttonStyle(.plain)
    }

    /// Toggle button (shuffle/repeat): fills white when ON so its state is clear.
    private func toggleButton<I: AppIntent>(_ intent: I, symbol: String, isOn: Bool,
                                            diameter: CGFloat, glyph: CGFloat) -> some View {
        Button(intent: intent) {
            discGlyph(symbol, glyph: glyph, diameter: diameter, isOn: isOn)
        }
        .buttonStyle(.plain)
    }

    private func discGlyph(_ symbol: String, glyph: CGFloat, diameter: CGFloat, isOn: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: glyph, weight: .bold))
            .foregroundStyle(isOn ? .black : .white)
            .shadow(color: .black.opacity(isOn ? 0 : 0.5), radius: 2, y: 1)
            .frame(width: diameter, height: diameter)
            // Dark disc normally; filled white when ON. (NOT .ultraThinMaterial,
            // which renders near-white in a widget and hides white glyphs.)
            .background(Circle().fill(isOn ? .white.opacity(0.92) : .black.opacity(0.30)))
            .overlay(Circle().strokeBorder(.white.opacity(isOn ? 0 : 0.45), lineWidth: 1))
            .contentShape(.circle)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
