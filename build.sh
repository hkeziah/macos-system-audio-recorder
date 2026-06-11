#!/bin/bash
set -euo pipefail

APP_NAME="AudioRecordTranscribe"
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
    "$SRC_DIR/AudioRecordTranscribe.swift" \
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
    <string>AudioRecordTranscribe</string>
    <key>CFBundleIdentifier</key>
    <string>com.keziah.audio-record-transcribe</string>
    <key>CFBundleName</key>
    <string>AudioRecordTranscribe</string>
    <key>CFBundleDisplayName</key>
    <string>Audio Record and Transcribe</string>
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>AudioRecordTranscribe captures system audio via BlackHole virtual driver. No microphone audio is recorded.</string>
</dict>
</plist>
PLIST

# Icon — use pre-made AppIcon.png, generate .icns
echo "==> Generating app icon…"
ICON_SRC="$SRC_DIR/AppIcon.png"
ICON_DIR="$BUILD_DIR/icon_tmp"
mkdir -p "$ICON_DIR"

if [ -f "$ICON_SRC" ]; then
    # Ensure source is proper PNG (handles JPEG-renamed-to-.png)
    echo "  Source: $(file -b "$ICON_SRC")"
    PNGSRC="$ICON_DIR/source.png"
    sips -s format png "$ICON_SRC" --out "$PNGSRC" &>/dev/null && ICON_SRC="$PNGSRC" || true

    ICONSET="$ICON_DIR/icon.iconset"
    mkdir -p "$ICONSET"

    if command -v sips &>/dev/null; then
        sips -z 16   16   "$ICON_SRC" --out "$ICONSET/icon_16x16.png"       &>/dev/null || true
        sips -z 32   32   "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"    &>/dev/null || true
        sips -z 32   32   "$ICON_SRC" --out "$ICONSET/icon_32x32.png"       &>/dev/null || true
        sips -z 64   64   "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"    &>/dev/null || true
        sips -z 128  128  "$ICON_SRC" --out "$ICONSET/icon_128x128.png"     &>/dev/null || true
        sips -z 256  256  "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png"  &>/dev/null || true
        sips -z 256  256  "$ICON_SRC" --out "$ICONSET/icon_256x256.png"     &>/dev/null || true
        sips -z 512  512  "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png"  &>/dev/null || true
        sips -z 512  512  "$ICON_SRC" --out "$ICONSET/icon_512x512.png"     &>/dev/null || true
        sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png"  &>/dev/null || true

        ICNS_PATH="$BUILD_DIR/$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
        iconutil -c icns "$ICONSET" -o "$ICNS_PATH"
        if [ -s "$ICNS_PATH" ]; then
            echo "  Icon created ($(wc -c < "$ICNS_PATH") bytes)"
        else
            echo "  WARNING: iconutil produced empty file"
        fi
    else
        echo "  sips not available — skipping icon"
    fi
else
    echo "  No AppIcon.png found — skipping icon"
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
