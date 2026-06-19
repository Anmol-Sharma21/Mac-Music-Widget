# MusicGlass 🎵🫧

A **macOS 26 (Tahoe) WidgetKit music widget** with Liquid Glass, plus a tiny
menu-bar agent that powers it. It shows what's playing in **Apple Music** *or*
**Spotify** (auto-detected) and lets you **play / pause / skip** right from the
widget. The widget is **size-adaptive**: small shows a couple of controls, large
shows full transport + a live progress bar. Resize it any time with macOS's
**Edit Widget**.

> Built and verified against macOS 26.5.1 / Swift 6.3 toolchain.

---

## Why there are two pieces

WidgetKit widgets are sandboxed snapshots — they **can't** send Apple Events to
control Music/Spotify (the system denies it and can't even show the permission
prompt). So MusicGlass is split:

```
┌─────────────────────────┐         App Group container          ┌────────────────────┐
│  Host (menu-bar agent)   │  ── nowplaying.json + artwork.png ──▶ │   Widget (WidgetKit) │
│  • polls Music/Spotify   │                                       │  • renders glass UI  │
│  • holds Automation perm │  ◀── pendingCommand ── + Darwin ───── │  • buttons = intents │
│  • runs transport cmds   │        notification (wake)            └────────────────────┘
└─────────────────────────┘
```

- **Host** is an `LSUIElement` agent (no Dock icon, just a menu-bar item). It
  reads now-playing via `NSAppleScript`, writes a shared snapshot + album art,
  and executes the transport commands the widget asks for. Its popover uses
  **real, live Liquid Glass** (`.glassEffect`).
- **Widget** reads the shared snapshot and renders. Its buttons are **App
  Intents** that drop a command in the shared container and post a Darwin
  notification to wake the host. (Real `.glassEffect()` is currently buggy
  *inside* widgets, so the widget uses the **system Liquid Glass chrome** +
  blurred-art background + `.ultraThinMaterial` panels instead.)

---

## Requirements

- **macOS 26 (Tahoe) or later.**
- **Xcode 26+** — *required* to build WidgetKit widgets (Command Line Tools
  alone can't). Install from the App Store, then run it once to finish setup.
- An **Apple ID** signed into Xcode. A **free personal team is enough** for local
  use. (Heads-up: free-team signing **expires after 7 days** — when the widget
  goes stale, just rebuild from Xcode.)
- Homebrew (for `xcodegen`) — already installed on this machine.

---

## Setup (first run)

```bash
cd "MusicGlass"

# 1) Sign into Xcode first: Xcode ▸ Settings ▸ Accounts ▸ add your Apple ID,
#    then Manage Certificates… ▸ + ▸ "Apple Development".

# 2) Record your Team ID and generate the project:
./Scripts/set-team.sh      # writes Config/Signing.xcconfig + generates the project
./Scripts/bootstrap.sh     # (or just this — it installs xcodegen & opens Xcode)
```

If `set-team.sh` can't find a team yet, open `MusicGlass.xcodeproj` and pick your
team in **Signing & Capabilities** for **both** the *Host* and *Widget* targets.

### Run it

1. In Xcode, select the **Host** scheme and press **⌘R**. A 🎵 icon appears in
   your menu bar.
2. Click it → **Grant Permission** → approve the macOS prompts to let MusicGlass
   control **Music** and **Spotify**. (First time only.)
3. Start playing something in Music or Spotify — the popover shows it with live
   glass + working controls.

### Add the widget

1. **Control-click the desktop** (or open Notification Center) → **Edit Widgets**.
2. Find **MusicGlass**, pick a size tab (**Small / Medium / Large / Extra Large**),
   and drag it out.
3. **To change size/controls later:** Control-click the widget → **Edit Widget**,
   or remove it and drag out a different size. Small = art + play/pause; larger
   sizes add the artist/album, a live progress bar, and previous/next.

---

## How the glass works

- **In the widget:** macOS 26 draws the Liquid Glass *container* around the
  widget automatically. We fill it with a **full-bleed blurred album cover** and
  float text/controls on **frosted Material** — the “glass” look you see is the
  system chrome + Material, which is the supported path today.
- **In the host popover:** this runs in a normal app process, where
  `.glassEffect()` / `GlassEffectContainer` / `.buttonStyle(.glass)` render
  *live*, so the popover is the place to enjoy true Liquid Glass.

> Why not real glass in the widget? As of macOS 26.0, `.glassEffect()` inside a
> widget is buggy (renders solid white/black, hides text). When Apple fixes it,
> swapping the Material panels for `.glassEffect()` in `MusicWidget.swift` is a
> one-line change per panel.

---

## What's where

```
MusicGlass/
├─ project.yml                 # XcodeGen spec (app + widget extension)
├─ Config/Signing.xcconfig     # your DEVELOPMENT_TEAM lives here
├─ Shared/                     # compiled into BOTH targets
│  ├─ NowPlaying.swift         # the shared state model
│  └─ SharedStore.swift        # App Group container + command queue + Darwin notif
├─ HostApp/
│  ├─ MusicGlassApp.swift      # @main, MenuBarExtra, AppDelegate
│  ├─ MenuBarView.swift        # the live Liquid Glass popover
│  ├─ MusicEngine.swift        # polls players, writes state, runs commands
│  ├─ MusicScripts.swift       # verified AppleScript for Music + Spotify
│  ├─ AppleScriptRunner.swift  # in-process NSAppleScript execution
│  ├─ CommandRouter.swift      # Darwin-notification listener
│  └─ HostApp.entitlements
├─ Widget/
│  ├─ MusicWidgetBundle.swift  # @main widget bundle
│  ├─ MusicWidget.swift        # provider + size-adaptive glass views
│  ├─ MusicControlIntents.swift# App Intents for the buttons
│  └─ Widget.entitlements
└─ Scripts/{bootstrap,set-team}.sh
```

---

## Limitations (by design, from WidgetKit)

- **No drag-to-scrub.** Widgets only support button/toggle taps — no sliders or
  gestures. The progress bar is **live but not draggable**. (The host popover
  could add scrubbing later; widgets fundamentally can't.)
- Controls are **button-only** via App Intents; after a tap the widget reloads.
- The **host agent must be running** to action the widget's buttons. Use the
  popover's **⋯ ▸ Launch at Login** to keep it alive across restarts.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Widget never appears in the gallery / shows then vanishes | The app group must be **Team-ID-prefixed** (it is, via `$(TeamIdentifierPrefix)`). Make sure both targets use **the same team**. |
| Widget stuck / stale after ~a week | Free-team profiles expire in 7 days — **rebuild from Xcode**. |
| Buttons do nothing | The host agent isn't running, or Automation wasn't granted. Launch the Host, click 🎵 ▸ **Grant Permission**. |
| “Nothing playing” though music is on | Approve the Automation prompt for that specific app (Music *and* Spotify are separate grants). |
| Signing errors | Run `./Scripts/set-team.sh`, or set the team for both targets in Xcode. |
