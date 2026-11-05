#!/bin/sh
# Builds "build/Claude Lights.app" (and a zip for releases).
#
#   scripts/build-app.sh            # universal (arm64 + x86_64) if possible
#   UNIVERSAL=0 scripts/build-app.sh  # native architecture only
#   VERSION=1.2.0 scripts/build-app.sh
set -eu
cd "$(dirname "$0")/.."

VERSION=${VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}
UNIVERSAL=${UNIVERSAL:-1}
APP="build/Claude Lights.app"

build() {
    swift build -c release "$@" >&2 && swift build -c release "$@" --show-bin-path
}

if [ "$UNIVERSAL" = "1" ] && BIN=$(build --arch arm64 --arch x86_64 2>/dev/null); then
    echo "Built universal binary"
else
    echo "Universal build unavailable (needs full Xcode); building for $(uname -m)"
    BIN=$(build)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/ClaudeLights" "$APP/Contents/MacOS/ClaudeLights"
cp hooks/claude-lights-hook.sh "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS accepts the bundle (no Apple Developer account needed).
codesign --force --deep --sign - "$APP"

( cd build && rm -f ClaudeLights.zip && ditto -c -k --keepParent "Claude Lights.app" ClaudeLights.zip )

echo "Done: $APP (v$VERSION)"
echo "      build/ClaudeLights.zip"
