//  OnboardingView.swift
//  Shown in a real, foreground window when MusicGlass still needs Automation
//  permission. A visible/active window is what makes the macOS consent prompt
//  appear reliably (a window-less menu-bar agent can't surface it well).

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var engine: MusicEngine

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.55), .purple.opacity(0.45), .pink.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)

                    Text("Allow MusicGlass to read your music")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("MusicGlass needs permission to read & control **Music** and **Spotify** so it can show what's playing and run the widget's buttons. You'll see a system dialog — click **OK** for each.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        Button {
                            engine.requestAutomationPermission()
                        } label: {
                            Label("Grant Permission", systemImage: "lock.open.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)

                        Button {
                            engine.openAutomationSettings()
                        } label: {
                            Label("Open Automation Settings", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    .padding(.top, 4)

                    Text("If the dialog doesn't appear, open Automation Settings and turn on **Music** and **Spotify** under **MusicGlass**.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
                .frame(width: 380)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(24)
            }
        }
        .frame(width: 440, height: 360)
        .foregroundStyle(.white)
    }
}
