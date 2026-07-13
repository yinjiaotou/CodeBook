#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_root="$(cd "$project_root/../../.." && pwd)"
source_image="$repository_root/image/icon.jpg"
output_icon="${1:-$project_root/Resources/AppIcon.icns}"
ffmpeg_bin="${FFMPEG_BIN:-/opt/homebrew/bin/ffmpeg}"
temporary_dir="$(mktemp -d /private/tmp/PwdlockAppIcon.XXXXXX)"
iconset_dir="$temporary_dir/AppIcon.iconset"
temporary_icon="$temporary_dir/AppIcon.icns"

trap 'rm -rf "$temporary_dir"' EXIT

[[ -s "$source_image" ]] || {
    printf 'Source image is missing: %s\n' "$source_image" >&2
    exit 1
}
if [[ ! -x "$ffmpeg_bin" ]]; then
    ffmpeg_bin="$(command -v ffmpeg || true)"
fi
[[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || {
    printf 'ffmpeg is required to generate the application icon.\n' >&2
    exit 1
}

mkdir -p "$iconset_dir"

render_icon() {
    local size="$1"
    local name="$2"

    "$ffmpeg_bin" -y -hide_banner -loglevel error -i "$source_image" \
        -vf "scale=${size}:${size}:flags=lanczos" \
        -frames:v 1 -pix_fmt rgba "$iconset_dir/$name"
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

swift "$project_root/Scripts/create-icns.swift" "$temporary_icon" \
    "$iconset_dir/icon_16x16.png" \
    "$iconset_dir/icon_16x16@2x.png" \
    "$iconset_dir/icon_32x32@2x.png" \
    "$iconset_dir/icon_128x128.png" \
    "$iconset_dir/icon_128x128@2x.png" \
    "$iconset_dir/icon_256x256@2x.png" \
    "$iconset_dir/icon_512x512@2x.png"
mv -f "$temporary_icon" "$output_icon"

printf 'Generated application icon: %s\n' "$output_icon"
