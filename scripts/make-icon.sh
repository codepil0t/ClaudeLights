#!/bin/sh
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -eu
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift scripts/make-icon.swift "$work/icon.png"

set_dir="$work/AppIcon.iconset"
mkdir "$set_dir"
for s in 16 32 128 256 512; do
    sips -z $s $s "$work/icon.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$work/icon.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
