#!/bin/sh
# Packages the macOS app: a universal (arm64 + x86_64) release build of the GUI with a universal
# `skillcask` CLI inside, signed, and zipped for download.
#
#   ./bundle.sh                                   # builds both from this repo
#   SKILLCASK_CLI=/path/to/skillcask ./bundle.sh  # bundles a prebuilt CLI instead of building one
#   SIGN_IDENTITY="Developer ID Application: …" ./bundle.sh
#
# Output (git-ignored):
#   .build/Skillcask.app
#     Contents/MacOS/Skillcask        the GUI
#     Contents/Helpers/skillcask      the CLI; `Locator` looks for it here (only inside a .app)
#     Contents/Resources/*.bundle     SwiftPM resource bundles; the generated `Bundle.module` accessor
#                                     looks in `Bundle.main.resourceURL` first, i.e. Contents/Resources
#     Contents/Resources/Skillcask.icns  the icon, rendered from icon.svg
#   .build/Skillcask-<version>-macos-universal.zip
#
# Signing is ad hoc (`SIGN_IDENTITY=-`, the default), inside-out (the helper, then the app; no
# `--deep`) and with the hardened runtime, so the same layout notarizes once it is signed with a
# Developer ID. An ad-hoc build opens on the machine that built it; anywhere else Gatekeeper blocks
# it. Notarization (`xcrun notarytool submit … --wait`, then `xcrun stapler staple`) needs the
# maintainer's Apple Developer account and is not done here. No App Sandbox: the app runs the CLI
# in user directories. The version is `version` in ../Cargo.toml.
#
# The CLI is built with CARGO_ENCODED_RUSTFLAGS empty, which overrides RUSTFLAGS and any
# `[target.*] rustflags` / `[build] rustflags` from the user's cargo config, so a local bundle carries
# the same binary flags as a CI build.
set -eu
# A relative SKILLCASK_CLI is relative to where the script was started, not to macos/.
case "${SKILLCASK_CLI:-}" in
"" | /*) ;;
*) SKILLCASK_CLI=$(pwd)/$SKILLCASK_CLI ;;
esac
cd "$(dirname "$0")"

identity=${SIGN_IDENTITY:--}
bundle_id=io.github.puniserv.skillcask
version=$(sed -n 's/^version = "\(.*\)"/\1/p' ../Cargo.toml | head -n 1)
[ -n "$version" ] || { echo "bundle.sh: no version in ../Cargo.toml" >&2; exit 1; }
app=.build/Skillcask.app
zip=.build/Skillcask-$version-macos-universal.zip

fail() {
    echo "bundle.sh: $*" >&2
    exit 1
}

# Whether $1 holds both slices (this lipo checks one -verify_arch at a time).
universal() {
    lipo "$1" -verify_arch arm64 2>/dev/null && lipo "$1" -verify_arch x86_64 2>/dev/null
}

# 0. Preconditions, before any build: Xcode's toolchain (SwiftUI's macro plugins, `@State`, `@Entry`,
# `#Preview`, ship only with Xcode, not with the Command Line Tools), then the prebuilt CLI is usable, or both
# Rust targets are installed.
case "$(xcrun --find swift 2>/dev/null)" in
*/Xcode*.app/Contents/Developer/*) ;;
*) fail "Skillcask for Mac needs Xcode: the @Entry and #Preview macro plugins ship only with Xcode; sudo xcode-select -s /Applications/Xcode.app" ;;
esac
if [ -n "${SKILLCASK_CLI:-}" ]; then
    cli=$SKILLCASK_CLI
    [ -f "$cli" ] && [ -x "$cli" ] || fail "SKILLCASK_CLI=$cli is not an executable file"
    file -b "$cli" | grep -q '^Mach-O' || fail "SKILLCASK_CLI=$cli is not a Mach-O binary"
    if ! universal "$cli"; then
        echo "bundle.sh: warning: $cli is not universal ($(lipo -archs "$cli")); the app will not find a" \
            "usable CLI on the other architecture" >&2
    fi
elif command -v rustup >/dev/null 2>&1; then
    installed=$(rustup target list --installed)
    for target in aarch64-apple-darwin x86_64-apple-darwin; do
        printf '%s\n' "$installed" | grep -qx "$target" ||
            fail "Rust target $target is not installed: rustup target add $target (or set SKILLCASK_CLI)"
    done
fi

# 1. The GUI, one universal build (SwiftPM builds multi-arch through its Xcode build system).
swift_args="-c release --arch arm64 --arch x86_64"
# shellcheck disable=SC2086 # word splitting of swift_args is intended
swift build $swift_args --product Skillcask
# shellcheck disable=SC2086
bin=$(swift build $swift_args --show-bin-path)
gui=$bin/Skillcask
universal "$gui" || fail "$gui is not universal"
# Only system libraries may be linked dynamically: nothing else is copied into the bundle.
if otool -L "$gui" | sed 1d | grep -qE '@(rpath|executable_path|loader_path)/'; then
    otool -L "$gui" >&2
    fail "$gui links a non-system library; bundle it under Contents/Frameworks first"
fi

# 2. The CLI: prebuilt (checked above), or both darwin targets from this repo joined with lipo.
if [ -z "${SKILLCASK_CLI:-}" ]; then
    target_dir=${CARGO_TARGET_DIR:-../target}
    for target in aarch64-apple-darwin x86_64-apple-darwin; do
        CARGO_ENCODED_RUSTFLAGS='' cargo build --release --locked --manifest-path ../Cargo.toml --target "$target"
    done
    cli=.build/skillcask-universal
    lipo -create -output "$cli" \
        "$target_dir/aarch64-apple-darwin/release/skillcask" \
        "$target_dir/x86_64-apple-darwin/release/skillcask"
fi
cli_version=$("$cli" --version) || fail "$cli --version failed"
case "$cli_version" in
"skillcask $version" | "skillcask $version "*) ;;
"skillcask "*) echo "bundle.sh: warning: the CLI is $cli_version, the app is $version" >&2 ;;
*) fail "$cli --version printed '$cli_version', not 'skillcask <version>'" ;;
esac

# 3. The bundle.
rm -rf "$app" "$zip"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$gui" "$app/Contents/MacOS/Skillcask"
cp "$cli" "$app/Contents/Helpers/skillcask"
chmod 755 "$app/Contents/MacOS/Skillcask" "$app/Contents/Helpers/skillcask"
# The linker records the build machine's toolchain directories (Xcode, the Metal toolchain cryptex) as
# rpaths; nothing in the app loads from them, so only system ones (/usr/lib, /System) and @-relative
# ones stay. install_name_tool edits every slice; the signature it breaks is replaced below.
otool -l "$app/Contents/MacOS/Skillcask" | awk '/cmd LC_RPATH/ { r = 1 } r && $1 == "path" { print $2; r = 0 }' |
    sort -u | while read -r rpath; do
    case "$rpath" in
    @* | /usr/lib/* | /usr/lib | /System/*) ;;
    *) install_name_tool -delete_rpath "$rpath" "$app/Contents/MacOS/Skillcask" ;;
    esac
done
# Every resource bundle the release build produced (test bundles are debug-only, skipped anyway).
found=0
for res in "$bin"/*.bundle; do
    [ -d "$res" ] || continue
    case "$res" in *Tests.bundle) continue ;; esac
    cp -R "$res" "$app/Contents/Resources/"
    found=$((found + 1))
done
[ "$found" -gt 0 ] || fail "no resource bundle in $bin (SkillcaskUI has resources: Bundle.module would crash)"
# The icon: Quick Look renders the SVG with WebKit, so the icon needs no tool beyond what macOS ships.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
qlmanage -t -s 1024 -o "$tmp" icon.svg >/dev/null
[ -f "$tmp/icon.svg.png" ] || fail "qlmanage did not render icon.svg"
mkdir "$tmp/Skillcask.iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.svg.png" --out "$tmp/Skillcask.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$tmp/icon.svg.png" --out "$tmp/Skillcask.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$app/Contents/Resources/Skillcask.icns" "$tmp/Skillcask.iconset"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Skillcask</string>
    <key>CFBundleIconFile</key><string>Skillcask</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Skillcask</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 skillcask contributors. MIT OR Apache-2.0.</string>
</dict>
</plist>
EOF
plutil -lint "$app/Contents/Info.plist" >/dev/null

# 4. Signing, inside-out. A Developer ID signature needs a secure timestamp for notarization.
timestamp=--timestamp=none
[ "$identity" = "-" ] || timestamp=--timestamp
codesign --force --sign "$identity" --options runtime $timestamp \
    --identifier "$bundle_id.cli" "$app/Contents/Helpers/skillcask"
codesign --force --sign "$identity" --options runtime $timestamp "$app"
codesign --verify --strict --verbose=2 "$app"

# 5. The download: ditto keeps the bundle's signature and modes intact.
ditto -c -k --keepParent "$app" "$zip"
echo "built $(pwd)/$app ($cli_version)"
echo "zipped $(pwd)/$zip"
