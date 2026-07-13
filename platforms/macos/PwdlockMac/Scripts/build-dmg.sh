#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$project_root/dist"
app_bundle="$dist_dir/Pwdlock.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
frameworks_dir="$contents_dir/Frameworks"
resources_dir="$contents_dir/Resources"
stage_dir="$dist_dir/dmg-stage"
source_icon="$project_root/Resources/AppIcon.icns"

for command in swift otool install_name_tool codesign hdiutil lipo; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Required command is unavailable: %s\n' "$command" >&2
        exit 1
    }
done

[[ -s "$source_icon" ]] || {
    printf 'Application icon is missing: %s\n' "$source_icon" >&2
    exit 1
}

rm -rf "$dist_dir"
mkdir -p "$macos_dir" "$frameworks_dir" "$resources_dir" "$stage_dir"

cd "$project_root"
swift build -c release --product PwdlockMacApp
release_bin_dir="$(swift build -c release --show-bin-path)"
source_executable="$release_bin_dir/PwdlockMacApp"
bundle_executable="$macos_dir/PwdlockMacApp"

[[ -f "$source_executable" ]] || {
    printf 'Release executable was not produced: %s\n' "$source_executable" >&2
    exit 1
}

supported_architectures="$(lipo -archs "$source_executable")"
architecture_label="${supported_architectures// /-}"
dmg_path="$dist_dir/Pwdlock-macOS-${architecture_label}.dmg"

install -m 755 "$source_executable" "$bundle_executable"
cp "$project_root/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$source_icon" "$resources_dir/AppIcon.icns"
printf '%s\n' \
    '密码锁 macOS 发布包' \
    '' \
    "支持的架构：${supported_architectures}" \
    '此包不是通用二进制文件。' \
    'x86_64 版本需要在具备 x86_64 Homebrew 依赖的环境中单独构建。' \
    > "$dist_dir/README.txt"

is_system_dependency() {
    case "$1" in
        /System/* | /usr/lib/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dependencies_of() {
    otool -L "$1" | awk 'NR > 1 { print $1 }'
}

rpaths_of() {
    otool -l "$1" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { reading_rpath = 1; next }
        reading_rpath && $1 == "path" { print $2; reading_rpath = 0 }
    '
}

resolve_dependency() {
    local owner="$1"
    local dependency="$2"
    local owner_dir
    local candidate
    local rpath
    local relative_path

    owner_dir="$(cd "$(dirname "$owner")" && pwd)"

    case "$dependency" in
        /*)
            [[ -f "$dependency" ]] && {
                printf '%s\n' "$dependency"
                return 0
            }
            ;;
        @loader_path/*)
            candidate="$owner_dir/${dependency#@loader_path/}"
            [[ -f "$candidate" ]] && {
                printf '%s\n' "$candidate"
                return 0
            }
            ;;
        @executable_path/*)
            candidate="$(dirname "$source_executable")/${dependency#@executable_path/}"
            [[ -f "$candidate" ]] && {
                printf '%s\n' "$candidate"
                return 0
            }
            ;;
        @rpath/*)
            relative_path="${dependency#@rpath/}"
            while IFS= read -r rpath; do
                rpath="${rpath//@loader_path/$owner_dir}"
                rpath="${rpath//@executable_path/$(dirname "$source_executable")}" 
                candidate="$rpath/$relative_path"
                [[ -f "$candidate" ]] && {
                    printf '%s\n' "$candidate"
                    return 0
                }
            done < <(rpaths_of "$owner")

            candidate="$owner_dir/$relative_path"
            [[ -f "$candidate" ]] && {
                printf '%s\n' "$candidate"
                return 0
            }
            ;;
    esac

    return 1
}

declare -a scan_queue
declare -a scanned_sources
scan_queue=("$source_executable")
scanned_sources=()

already_scanned() {
    local candidate="$1"
    local known

    for known in "${scanned_sources[@]-}"; do
        [[ "$known" == "$candidate" ]] && return 0
    done
    return 1
}

copy_dependency() {
    local source_path="$1"
    local destination="$frameworks_dir/$(basename "$source_path")"

    if [[ ! -f "$destination" ]]; then
        cp -L "$source_path" "$destination"
        chmod 755 "$destination"
    fi
}

queue_index=0
while (( queue_index < ${#scan_queue[@]} )); do
    owner="${scan_queue[$queue_index]}"
    queue_index=$((queue_index + 1))

    already_scanned "$owner" && continue
    scanned_sources+=("$owner")

    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        is_system_dependency "$dependency" && continue

        if ! resolved_dependency="$(resolve_dependency "$owner" "$dependency")"; then
            printf 'Unable to resolve third-party dependency %s referenced by %s\n' \
                "$dependency" "$owner" >&2
            exit 1
        fi

        copy_dependency "$resolved_dependency"
        scan_queue+=("$resolved_dependency")
    done < <(dependencies_of "$owner")
done

rewrite_dependencies() {
    local target="$1"
    local reference_prefix="$2"
    local skip_first_dependency="$3"
    local dependency
    local first_dependency=1
    local basename
    local replacement

    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        if [[ "$skip_first_dependency" == "yes" && "$first_dependency" -eq 1 ]]; then
            first_dependency=0
            continue
        fi
        first_dependency=0

        is_system_dependency "$dependency" && continue
        basename="$(basename "$dependency")"
        [[ -f "$frameworks_dir/$basename" ]] || continue
        replacement="$reference_prefix/$basename"
        [[ "$dependency" == "$replacement" ]] || \
            install_name_tool -change "$dependency" "$replacement" "$target"
    done < <(dependencies_of "$target")
}

remove_external_rpaths() {
    local target="$1"
    local rpath

    while IFS= read -r rpath; do
        case "$rpath" in
            /System/* | /usr/lib/* | @*)
                ;;
            *)
                install_name_tool -delete_rpath "$rpath" "$target"
                ;;
        esac
    done < <(rpaths_of "$target")
}

rewrite_dependencies "$bundle_executable" "@rpath" "no"
remove_external_rpaths "$bundle_executable"
if ! rpaths_of "$bundle_executable" | grep -Fxq '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$bundle_executable"
fi

while IFS= read -r -d '' dylib; do
    install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib"
    rewrite_dependencies "$dylib" "@loader_path" "yes"
    remove_external_rpaths "$dylib"
done < <(find "$frameworks_dir" -type f -name '*.dylib' -print0)

if otool -L "$bundle_executable" "$frameworks_dir"/*.dylib | \
    grep -E '^[[:space:]]+/(opt/homebrew|usr/local)/'; then
    printf 'Bundled binaries still reference an absolute Homebrew path.\n' >&2
    exit 1
fi

while IFS= read -r -d '' dylib; do
    codesign -s - --force --timestamp=none "$dylib"
done < <(find "$frameworks_dir" -type f -name '*.dylib' -print0)
codesign -s - --force --deep --timestamp=none "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

cp -R "$app_bundle" "$stage_dir/Pwdlock.app"
cp "$dist_dir/README.txt" "$stage_dir/README.txt"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname Pwdlock -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path"
rm -rf "$stage_dir"

printf 'Created app bundle: %s\nCreated disk image: %s\n' "$app_bundle" "$dmg_path"
