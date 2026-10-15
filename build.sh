#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
output_dir="${LUME_OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$output_dir"
# iCloud/File Provider can attach FinderInfo in Documents while codesign runs.
# Build/sign on a local temporary volume, then copy the signed bundle.
staging="$(mktemp -d /private/tmp/lume-build.XXXXXX)"
app="$staging/Lume.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/.build"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$SWIFT_MODULECACHE_PATH" \
  Sources/*.swift -o "$app/Contents/MacOS/Lume" \
  -framework AppKit -framework SwiftUI -framework CoreBluetooth -framework Security -framework ServiceManagement -lsqlite3
cp Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp LICENSE "$app/Contents/Resources/LICENSE"
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --sign - --identifier dev.jonatas.lume --requirements '=designated => identifier "dev.jonatas.lume"' "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --noextattr --norsrc --keepParent "$app" "$output_dir/Lume-macOS.zip"
print -r -- "$app" > "$PWD/.build/last-app-path"
print "App assinado: $app"
print "Entrega: $output_dir/Lume-macOS.zip"
