#!/bin/bash
set -e

CERT="NightfallDev"
PACKAGE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cert) CERT="$2"; shift ;;
        --package) PACKAGE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# 1. Build the binary
swift build -c release

# 2. Assemble the .app bundle
rm -rf Nightfall.app
mkdir -p Nightfall.app/Contents/MacOS
mkdir -p Nightfall.app/Contents/Resources

cp .build/release/Nightfall Nightfall.app/Contents/MacOS/

# 3. Icon — only if Assets/icon.png is present
if [ -f Assets/icon.png ]; then
    mkdir -p Nightfall.iconset
    sips -z 16   16   Assets/icon.png --out Nightfall.iconset/icon_16x16.png        > /dev/null
    sips -z 32   32   Assets/icon.png --out Nightfall.iconset/icon_16x16@2x.png     > /dev/null
    sips -z 32   32   Assets/icon.png --out Nightfall.iconset/icon_32x32.png        > /dev/null
    sips -z 64   64   Assets/icon.png --out Nightfall.iconset/icon_32x32@2x.png     > /dev/null
    sips -z 128  128  Assets/icon.png --out Nightfall.iconset/icon_128x128.png      > /dev/null
    sips -z 256  256  Assets/icon.png --out Nightfall.iconset/icon_128x128@2x.png   > /dev/null
    sips -z 256  256  Assets/icon.png --out Nightfall.iconset/icon_256x256.png      > /dev/null
    sips -z 512  512  Assets/icon.png --out Nightfall.iconset/icon_256x256@2x.png   > /dev/null
    sips -z 512  512  Assets/icon.png --out Nightfall.iconset/icon_512x512.png      > /dev/null
    sips -z 1024 1024 Assets/icon.png --out Nightfall.iconset/icon_512x512@2x.png   > /dev/null
    iconutil -c icns Nightfall.iconset -o Nightfall.app/Contents/Resources/Nightfall.icns
    rm -rf Nightfall.iconset
    echo "✅ Icon compiled"
else
    echo "⚠️ Assets/icon.png not found — skipping icon (place a 256×256 PNG there)"
fi

# 4. Info.plist
cat > Nightfall.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Nightfall</string>
    <key>CFBundleDisplayName</key>
    <string>Nightfall</string>
    <key>CFBundleIdentifier</key>
    <string>com.personal.nightfall</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Nightfall</string>
    <key>CFBundleIconFile</key>
    <string>Nightfall</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Nightfall needs to capture the screen so you can take screenshots.</string>
</dict>
</plist>
EOF

# 5. Code-sign
xattr -cr Nightfall.app
codesign --force --deep --sign "$CERT" Nightfall.app
echo "✅ Certified: $CERT"

# 6. Optional .dmg
if [ "$PACKAGE" = true ]; then
    rm -rf dmg_tmp Nightfall.dmg
    mkdir -p dmg_tmp
    cp -r Nightfall.app dmg_tmp/
    ln -s /Applications dmg_tmp/Applications
    hdiutil create \
        -volname "Nightfall" \
        -srcfolder dmg_tmp \
        -ov \
        -format UDZO \
        Nightfall.dmg
    rm -rf dmg_tmp
    echo "✅ Nightfall.dmg compiled"
fi

echo "🌙 Done. Open Nightfall.app or drop it into /Applications."
