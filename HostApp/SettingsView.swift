//  SettingsView.swift
//  Settings shown inside the menu-bar popover (gear toggle). Modeled on
//  MacMediaKeyForwarder's menu: a source-priority choice, plus what-to-show
//  toggles and launch-at-login. Bindings write straight to engine.settings,
//  whose didSet persists them and refreshes the widget.

import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: MusicEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Priority", systemImage: "arrow.up.arrow.down.circle.fill") {
                Picker("Priority", selection: $engine.settings.sourcePriority) {
                    ForEach(MusicGlassSettings.SourcePriority.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(priorityHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.4)

            section("Show in Widget", systemImage: "rectangle.on.rectangle.angled") {
                toggle("Album name", $engine.settings.showAlbum)
                toggle("Progress bar", $engine.settings.showProgressBar)
                toggle("Source badge", $engine.settings.showSourceBadge)
                toggle("Blurred artwork background", $engine.settings.showArtworkBackground)
            }

            Divider().opacity(0.4)

            toggle("Launch at Login", $engine.settings.launchAtLogin)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, systemImage: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
    }

    private var priorityHint: String {
        switch engine.settings.sourcePriority {
        case .auto:       return "Shows whichever player is currently playing."
        case .appleMusic: return "Always prefers Apple Music when it has a track."
        case .spotify:    return "Always prefers Spotify when it has a track."
        }
    }
}
