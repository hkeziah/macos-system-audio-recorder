#!/bin/bash
set -euo pipefail

APP_NAME="SystemAudioRecorder"
BUNDLE_DIR="${APP_NAME}.app"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SRC_DIR/build"

echo "==> Compiling…"
mkdir -p "$BUILD_DIR"

# Detect architecture and build native only
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    echo "  Building for Apple Silicon (arm64)"
    TARGET="arm64-apple-macos13.0"
else
    echo "  Building for Intel (x86_64)"
    TARGET="x86_64-apple-macos13.0"
fi

swiftc \
    -o "$BUILD_DIR/$APP_NAME" \
    "$SRC_DIR/SystemAudioRecorder.swift" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework AudioToolbox \
    -O \
    -target "$TARGET"

echo "==> Creating app bundle…"
rm -rf "$BUILD_DIR/$BUNDLE_DIR"
mkdir -p "$BUILD_DIR/$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUILD_DIR/$BUNDLE_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BUILD_DIR/$BUNDLE_DIR/Contents/MacOS/"

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
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>SystemAudioRecorder captures system audio via BlackHole virtual driver. No microphone audio is recorded.</string>
</dict>
</plist>
PLIST

# Simple icon
ICON_DIR="$BUILD_DIR/icon_tmp"
mkdir -p "$ICON_DIR"
export ICON_DIR

python3 << 'PYEOF'
import struct, zlib, os

def create_png(width, height, filename):
    def chunk(ct, data):
        c = ct + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw_rows = b''
    cx, cy, r = width // 2, height // 2, width // 2 - 20
    for y in range(height):
        raw_rows += b'\x00'
        for x in range(width):
            dx = (x - cx) / r
            dy = (y - cy) / r
            dist = (dx*dx + dy*dy) ** 0.5
            if dist < 0.85:
                # Red tinted center
                val = int(min(1.0, (1.0 - dist) * 1.5) * 255)
                raw_rows += struct.pack('BBBB', val, int(val * 0.3), int(val * 0.3), val)
            elif dist < 1.0:
                alpha = (1.0 - dist) / 0.15
                val = int(max(0, alpha * 255))
                raw_rows += struct.pack('BBBB', val, int(val * 0.3), int(val * 0.3), val)
            else:
                raw_rows += struct.pack('BBBB', 0, 0, 0, 0)

    idat = chunk(b'IDAT', zlib.compress(raw_rows))
    iend = chunk(b'IEND', b'')

    with open(filename, 'wb') as f:
        f.write(header + ihdr + idat + iend)

out = os.path.join(os.environ.get('ICON_DIR', '/tmp/icon_tmp'), 'icon_512.png')
create_png(512, 512, out)
PYEOF

ICONSET="$ICON_DIR/icon.iconset"
mkdir -p "$ICONSET"
if command -v sips &>/dev/null; then
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "$ICON_DIR/icon_512.png" --out "$ICONSET/icon_${size}x${size}.png" &>/dev/null || true
        sips -z $((size*2)) $((size*2)) "$ICON_DIR/icon_512.png" --out "$ICONSET/icon_${size}x${size}@2x.png" &>/dev/null || true
    done
    iconutil -c icns "$ICONSET" -o "$BUILD_DIR/$BUNDLE_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
rm -rf "$ICON_DIR"

chmod +x "$BUILD_DIR/$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

echo ""
echo "========================================"
echo "  Build complete!"
echo "  App: $BUILD_DIR/$BUNDLE_DIR"
echo ""
echo "  Launch: open $BUILD_DIR/$BUNDLE_DIR"
echo "  Or drag to /Applications/"
echo ""
echo "  Recordings save to:"
echo "  /Users/howardkeziah/System-Audio-Recordings/"
echo "========================================"
