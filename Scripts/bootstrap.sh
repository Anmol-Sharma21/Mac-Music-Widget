#!/usr/bin/env bash
# Generates MusicGlass.xcodeproj from project.yml and opens it in Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "▸ XcodeGen not found — installing via Homebrew…"
  brew install xcodegen
fi

# Signing.xcconfig is gitignored (holds your Team ID). Seed it from the template
# on a fresh clone so XcodeGen has the config file it references.
if [ ! -f Config/Signing.xcconfig ]; then
  cp Config/Signing.xcconfig.example Config/Signing.xcconfig
  echo "▸ Created Config/Signing.xcconfig from template (set your Team ID next)."
fi

echo "▸ Generating MusicGlass.xcodeproj…"
xcodegen generate

if ! grep -qE 'DEVELOPMENT_TEAM = [A-Z0-9]{10}' Config/Signing.xcconfig 2>/dev/null; then
  echo
  echo "⚠️  No DEVELOPMENT_TEAM set yet. Run ./Scripts/set-team.sh after signing"
  echo "    into Xcode (Settings ▸ Accounts), or pick your team in Xcode's"
  echo "    'Signing & Capabilities' tab for BOTH the Host and Widget targets."
  echo
fi

echo "▸ Opening in Xcode…"
open MusicGlass.xcodeproj
