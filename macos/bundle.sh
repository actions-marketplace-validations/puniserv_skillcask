#!/bin/sh
# Builds the app and wraps the executable into Skillcask.app, signed ad hoc so it opens by
# double-click on this machine (Gatekeeper still blocks it elsewhere: it is not notarized).
set -eu
cd "$(dirname "$0")"
swift build -c release
app=.build/Skillcask.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Skillcask" "$app/Contents/MacOS/Skillcask"
# Quick Look renders the SVG with WebKit, so the icon needs no tool beyond what macOS ships.
tmp=$(mktemp -d)
qlmanage -t -s 1024 -o "$tmp" icon.svg >/dev/null
mkdir "$tmp/Skillcask.iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.svg.png" --out "$tmp/Skillcask.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$tmp/icon.svg.png" --out "$tmp/Skillcask.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$app/Contents/Resources/Skillcask.icns" "$tmp/Skillcask.iconset"
rm -rf "$tmp"
version=$(sed -n 's/^version = "\(.*\)"/\1/p' ../Cargo.toml | head -n 1)
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Skillcask</string>
    <key>CFBundleIconFile</key><string>Skillcask</string>
    <key>CFBundleIdentifier</key><string>io.github.puniserv.skillcask</string>
    <key>CFBundleName</key><string>Skillcask</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
echo "built $(pwd)/$app"
