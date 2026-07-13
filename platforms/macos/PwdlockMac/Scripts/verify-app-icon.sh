#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
icns_path="${1:-$project_root/Resources/AppIcon.icns}"
ffmpeg_bin="${FFMPEG_BIN:-$(command -v ffmpeg || true)}"
temporary_dir="$(mktemp -d /private/tmp/PwdlockIconVerification.XXXXXX)"

trap 'rm -rf "$temporary_dir"' EXIT

[[ -s "$icns_path" ]] || {
    printf 'Missing application icon: %s\n' "$icns_path" >&2
    exit 1
}
[[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || {
    printf 'ffmpeg is required to verify the application icon.\n' >&2
    exit 1
}

magic="$(dd if="$icns_path" bs=1 count=4 2>/dev/null)"
[[ "$magic" == icns ]] || {
    printf 'Invalid ICNS header: %s\n' "$icns_path" >&2
    exit 1
}
file_size="$(stat -f '%z' "$icns_path")"
total_length_hex="$(dd if="$icns_path" bs=1 skip=4 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')"
total_length=$((16#$total_length_hex))
[[ "$total_length" -eq "$file_size" ]] || {
    printf 'ICNS length mismatch: header=%s file=%s.\n' "$total_length" "$file_size" >&2
    exit 1
}

offset=8
seen_types=''
rendition="$temporary_dir/ic10.png"
while (( offset < total_length )); do
    chunk_type="$(dd if="$icns_path" bs=1 skip="$offset" count=4 2>/dev/null)"
    chunk_length_hex="$(dd if="$icns_path" bs=1 skip=$((offset + 4)) count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    chunk_length=$((16#$chunk_length_hex))
    (( chunk_length >= 8 && offset + chunk_length <= total_length )) || {
        printf 'Invalid ICNS chunk %s at offset %s.\n' "$chunk_type" "$offset" >&2
        exit 1
    }
    seen_types+=" $chunk_type"
    if [[ "$chunk_type" == ic10 ]]; then
        dd if="$icns_path" of="$rendition" bs=1 skip=$((offset + 8)) count=$((chunk_length - 8)) 2>/dev/null
    fi
    offset=$((offset + chunk_length))
done

for required_type in icp4 icp5 icp6 ic07 ic08 ic09 ic10; do
    [[ " $seen_types " == *" $required_type "* ]] || {
        printf 'Missing ICNS chunk: %s.\n' "$required_type" >&2
        exit 1
    }
done
[[ -s "$rendition" ]] || {
    printf 'Missing 1024px ICNS rendition: %s\n' "$rendition" >&2
    exit 1
}

alpha_min="$(
    "$ffmpeg_bin" -hide_banner -loglevel info -i "$rendition" \
        -vf 'format=rgba,alphaextract,signalstats,metadata=mode=print' \
        -frames:v 1 -f null - 2>&1 \
        | rg -o 'YMIN=[0-9]+' \
        | cut -d= -f2
)"
read -r red green blue < <(
    "$ffmpeg_bin" -hide_banner -loglevel error -i "$rendition" \
        -vf 'scale=1:1:flags=area,format=rgb24' \
        -frames:v 1 -f rawvideo - \
        | od -An -tu1
)

[[ "$alpha_min" == 255 ]] || {
    printf 'Icon alpha is not fully opaque (YMIN=%s).\n' "$alpha_min" >&2
    exit 1
}
(( red >= 100 && red >= green + 40 && red >= blue + 40 )) || {
    printf 'Icon artwork is missing or unexpectedly dark (RGB mean: %s %s %s).\n' "$red" "$green" "$blue" >&2
    exit 1
}

printf 'App icon verification passed: opaque RGBA, RGB mean %s %s %s.\n' "$red" "$green" "$blue"
