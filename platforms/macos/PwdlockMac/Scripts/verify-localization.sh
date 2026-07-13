#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_info_plist="$project_root/Resources/Info.plist"
app_bundle="${1:-$project_root/dist/Pwdlock.app}"
bundle_info_plist="$app_bundle/Contents/Info.plist"
source_icon="$project_root/Resources/AppIcon.icns"
bundle_icon="$app_bundle/Contents/Resources/AppIcon.icns"

failures=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

require_plist_value() {
    local plist="$1"
    local key="$2"
    local expected="$3"
    local actual

    actual="$(plist_value "$plist" "$key")"
    [[ "$actual" == "$expected" ]] || fail "$plist must set $key to $expected (found: ${actual:-missing})"
}

[[ -f "$source_info_plist" ]] || fail "missing source Info.plist: $source_info_plist"
require_plist_value "$source_info_plist" CFBundleDevelopmentRegion zh-Hans
require_plist_value "$source_info_plist" CFBundleDisplayName 密码锁
require_plist_value "$source_info_plist" CFBundleName 密码锁
require_plist_value "$source_info_plist" CFBundleIconFile AppIcon
[[ -s "$source_icon" ]] || fail "missing source application icon: $source_icon"

visible_english_pattern='(Text|Button|SecureField|TextField|LabeledContent|Section|Picker|Label|Menu|ContentUnavailableView|confirmationDialog|alert)\("[^"\\]*(Create|Master|Confirm|Unlock|Pwdlock|Category|Categories|Logins|Search|New Login|Restore|Change Password|Auto-Lock|Settings|Lock|Select|Delete|Cancel|Username|Password|Hide|Reveal|Copy|Clipboard|Website|Notes|Edit|Title|Add|Save|Current|Use at least|Lost)[^"\\]*"|prompt: "Search titles"|errorMessage = "[^"\\]*(Passwords|Master|Please|Unable)[^"\\]*"|"(Hide|Reveal)"|var title: String \{ "[^"\\]*minutes[^"\\]*" \}'
if rg -n --glob '*.swift' "$visible_english_pattern" "$project_root/Sources/PwdlockMacApp"; then
    fail "English user-visible literals remain in PwdlockMacApp sources"
fi

[[ -f "$bundle_info_plist" ]] || fail "missing built Info.plist: $bundle_info_plist"
if [[ -f "$bundle_info_plist" ]]; then
    require_plist_value "$bundle_info_plist" CFBundleDevelopmentRegion zh-Hans
    require_plist_value "$bundle_info_plist" CFBundleDisplayName 密码锁
    require_plist_value "$bundle_info_plist" CFBundleName 密码锁
    require_plist_value "$bundle_info_plist" CFBundleIconFile AppIcon
fi
[[ -s "$bundle_icon" ]] || fail "missing bundled application icon: $bundle_icon"

if (( failures > 0 )); then
    exit 1
fi

printf 'Localization and app icon verification passed for %s\n' "$app_bundle"
