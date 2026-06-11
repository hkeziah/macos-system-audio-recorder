# System Audio Recorder

Dead-simple macOS app: click **Start Recording**, click **Stop Recording**. WAV files land in `/Users/howardkeziah/System-Audio-Recordings/`.

## Quick Start

```bash
git clone https://github.com/hkeziah/macos-system-audio-recorder.git
cd macos-system-audio-recorder
chmod +x build.sh
./build.sh
open build/SystemAudioRecorder.app
```

The app opens a small window with a single button. Press Enter or click to start/stop.

## Prerequisites

**BlackHole** — free virtual audio driver that makes system audio recordable.

1. Download from [github.com/ExistentialAudio/BlackHole/releases](https://github.com/ExistentialAudio/BlackHole/releases)
2. Install the .pkg, restart your Mac
3. Open **Audio MIDI Setup** (in /Applications/Utilities/)
4. Click **+** → **Create Multi-Output Device**
5. Check both **"BlackHole 2ch"** and your **speakers**
6. Right-click the Multi-Output Device → **"Use This Device For Sound Output"**

The Multi-Output step is critical — without it, your audio gets captured but you can't hear it while recording.

## How It Works

- Uses CoreAudio HAL (Hardware Abstraction Layer) to capture directly from BlackHole
- No microphone involved — records system audio only
- Saves 16-bit 44.1kHz stereo WAV with timestamped filenames
- Shows elapsed time during recording
- Stops cleanly and reveals the file in Finder

## Requirements

- macOS 13+ (Ventura or later)
- BlackHole virtual audio driver
- Xcode Command Line Tools (`xcode-select --install`)

## Troubleshooting

**"BlackHole Not Installed" alert** — Download and install BlackHole, restart.

**Recording is silent** — Make sure system output is the Multi-Output Device, not just speakers. Check Audio MIDI Setup.

**Can't hear audio during recording** — The Multi-Output Device must include your speakers. Re-create it with both BlackHole and your output device checked.
