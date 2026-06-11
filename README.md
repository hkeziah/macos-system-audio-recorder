# System Audio Recorder — macOS Menu Bar App

Records your Mac's system audio (not just the microphone) from the menu bar.

## Quick Start

```bash
# 1. Install BlackHole (one-time setup):
#    Download from: https://github.com/ExistentialAudio/BlackHole/releases
#    Install the .pkg and restart your Mac.

# 2. Set up routing (one-time setup):
#    Open Audio MIDI Setup → '+' → Create Multi-Output Device
#    Check both "BlackHole 2ch" and "MacBook Pro Speakers"
#    Right-click the Multi-Output Device → "Use This Device For Sound Output"
#    (This lets you hear audio while recording)

# 3. Build and launch:
chmod +x build.sh
./build.sh
open build/SystemAudioRecorder.app
```

## How It Works

- Lives in your menu bar: **◎** (idle) / **●** (recording)
- Captures from BlackHole virtual audio driver via CoreAudio HAL AudioUnit
- Saves timestamped WAV files to `~/Desktop/SystemAudio/`
- Click to start/stop — finished recordings open in Finder
- Settings: choose output folder, get setup instructions

## Files

| File | Purpose |
|------|---------|
| `SystemAudioRecorder.swift` | Complete app source (single file) |
| `build.sh` | Compiles, creates .app bundle |
| `build/SystemAudioRecorder.app` | Built app (after running build.sh) |

## Requirements

- macOS 13+ (Ventura or later)
- [BlackHole](https://github.com/ExistentialAudio/BlackHole/releases) virtual audio driver
- Xcode Command Line Tools (`xcode-select --install`)

## Troubleshooting

**"BlackHole Not Found" on launch** — Install BlackHole, restart your Mac.

**Recording is silent** — Make sure your system output is set to the Multi-Output Device (not directly to speakers). Check Audio MIDI Setup.

**No audio in recording but I hear it** — The Multi-Output Device must include BlackHole. If BlackHole is unchecked in the Multi-Output, audio won't be captured.

**App doesn't appear in Dock** — Correct. It's menu-bar-only (LSUIElement = true). Look for ◎ in your menu bar.
