#!/bin/bash
set -euo pipefail

# ─── Build & Package System Audio Recorder ───────────────────────────────
# Run this on your Mac to build the app.

APP_NAME="SystemAudioRecorder"
BUNDLE_DIR="${APP_NAME}.app"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SRC_DIR/build"

echo "==> Compiling Swift source..."
mkdir -p "$BUILD_DIR"

swiftc \
    -o "$BUILD_DIR/$APP_NAME" \
    "$SRC_DIR/SystemAudioRecorder.swift" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework AudioToolbox \
    -O \
    -target arm64-apple-macos13.0 \
    -target x86_64-apple-macos13.0 2>/dev/null || \
swiftc \
    -o "$BUILD_DIR/$APP_NAME" \
    "$SRC_DIR/SystemAudioRecorder.swift" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework AudioToolbox \
    -O

echo "==> Creating app bundle..."
rm -rf "$BUILD_DIR/$BUNDLE_DIR"
mkdir -p "$BUILD_DIR/$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUILD_DIR/$BUNDLE_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$BUILD_DIR/$BUNDLE_DIR/Contents/MacOS/"

# Create Info.plist
cat > "$BUILD_DIR/$BUNDLE_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SystemAudioRecorder</string>
    <key>CFBundleIdentifier</key>
    <string>com.keziah.system-audio-recorder</string>
    <key>CFBundleName</key>
    <string>SystemAudioRecorder</string>
    <key>CFBundleDisplayName</key>
    <string>System Audio Recorder</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>SystemAudioRecorder needs access to your audio input (BlackHole) to record system audio.</string>
</dict>
</plist>
PLIST

# Generate a simple icon (solid circle to match menu bar)
echo "==> Generating app icon..."
ICON_DIR="$BUILD_DIR/icon_tmp"
mkdir -p "$ICON_DIR"

# Create a simple 512x512 PNG with a circle using Python
python3 << 'PYEOF'
import struct, zlib, os

def create_png(width, height, filename):
    """Create a simple circular icon PNG."""
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    # Build image data with a smooth circle
    raw_rows = b''
    cx, cy, r = width // 2, height // 2, width // 2 - 20
    for y in range(height):
        raw_rows += b'\x00'  # filter byte
        for x in range(width):
            dx = (x - cx) / r
            dy = (y - cy) / r
            dist = (dx*dx + dy*dy) ** 0.5
            if dist < 0.92:
                # Gradient from edge to center
                alpha = min(1.0, max(0.0, (1.0 - dist) * 1.5))
                val = int(alpha * 255)
                raw_rows += struct.pack('BBBB', val, val, val, val)
            elif dist < 1.0:
                # Anti-aliased edge
                alpha = (1.0 - dist) / 0.08
                val = int(max(0, alpha * 255))
                raw_rows += struct.pack('BBBB', val, val, val, val)
            else:
                raw_rows += struct.pack('BBBB', 0, 0, 0, 0)

    idat = chunk(b'IDAT', zlib.compress(raw_rows))
    iend = chunk(b'IEND', b'')

    with open(filename, 'wb') as f:
        f.write(header + ihdr + idat + iend)

create_png(512, 512, os.path.join(os.path.dirname(__file__) or '.', 'icon_tmp', 'icon_512.png'))
PYEOF

# Convert to .icns using iconutil (needs a .iconset folder)
ICONSET="$ICON_DIR/icon.iconset"
mkdir -p "$ICONSET"

# Generate various sizes using sips
if command -v sips &>/dev/null; then
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "$ICON_DIR/icon_512.png" --out "$ICONSET/icon_${size}x${size}.png" &>/dev/null || true
        sips -z $((size*2)) $((size*2)) "$ICON_DIR/icon_512.png" --out "$ICONSET/icon_${size}x${size}@2x.png" &>/dev/null || true
    done
    iconutil -c icns "$ICONSET" -o "$BUILD_DIR/$BUNDLE_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

# Clean up temp
rm -rf "$ICON_DIR"

# Set executable bit
chmod +x "$BUILD_DIR/$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

echo ""
echo "========================================"
echo "  Build complete!"
echo "  App: $BUILD_DIR/$BUNDLE_DIR"
echo ""
echo "  To run: open $BUILD_DIR/$BUNDLE_DIR"
echo "  Or drag to /Applications/"
echo "========================================"
echo ""
echo "⚠️  Prerequisites:"
echo "  1. Install BlackHole: https://github.com/ExistentialAudio/BlackHole/releases"
echo "  2. Create Multi-Output Device in Audio MIDI Setup"
echo "     (BlackHole + your speakers — so you can hear while recording)"
echo "  3. Set Multi-Output Device as system output"
echo ""
echo "  The app records to ~/Desktop/SystemAudio/ by default."
echo "  Click ◎ in the menu bar → Settings to change the output folder."
