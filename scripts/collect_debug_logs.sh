#!/usr/bin/env bash

set -euo pipefail

crash_count=3

usage() {
    cat <<'EOF'
Usage: scripts/collect_debug_logs.sh [--crashes COUNT]

Collect the current UE4SS and Enhanced Databank logs plus the newest Unreal
crash reports into the repository's ignored debug directory.

Environment overrides:
  ZCOM_GAME_ROOT   Proton game prefix/install root
  ZCOM_INSTALL_DIR Directory containing SWZeroCompany/Binaries/Win64
EOF
}

while (($# > 0)); do
    case "$1" in
        --crashes)
            [[ $# -ge 2 ]] || { echo "Missing value for --crashes" >&2; exit 2; }
            crash_count="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$crash_count" =~ ^[1-9][0-9]*$ ]] || {
    echo "--crashes must be a positive integer" >&2
    exit 2
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname -- "$script_dir")"
volume_root="$(dirname -- "$(dirname -- "$repo_root")")"

game_root="${ZCOM_GAME_ROOT:-$volume_root/Games/STAR WARS Zero Company (2026)}"
install_dir="${ZCOM_INSTALL_DIR:-$game_root/Star Wars Zero Company}"
win64_dir="$install_dir/SWZeroCompany/Binaries/Win64"
ue4ss_log="$win64_dir/ue4ss/UE4SS.log"
crash_root="$game_root/prefix/drive_c/users/steamuser/AppData/Local/SWZeroCompany/Saved/Crashes"
debug_dir="$repo_root/debug"

probe_candidates=(
    "$win64_dir/ue4ss/Mods/Enhanced_Databank/enhanced_databank.log"
    "$win64_dir/ue4ss/Mods/EnhancedDatabank/enhanced_databank.log"
    "$win64_dir/databank_probe.log"
    "$win64_dir/ue4ss/Mods/EnhancedDatabank/databank_probe.log"
)

[[ -f "$ue4ss_log" ]] || {
    echo "UE4SS log not found: $ue4ss_log" >&2
    exit 1
}

[[ -d "$crash_root" ]] || {
    echo "Crash directory not found: $crash_root" >&2
    exit 1
}

mkdir -p -- "$debug_dir"
cp -- "$ue4ss_log" "$debug_dir/UE4SS.log"

newest_probe=""
for candidate in "${probe_candidates[@]}"; do
    if [[ -f "$candidate" ]] && { [[ -z "$newest_probe" ]] || [[ "$candidate" -nt "$newest_probe" ]]; }; then
        newest_probe="$candidate"
    fi
done

if [[ -n "$newest_probe" ]]; then
    cp -- "$newest_probe" "$debug_dir/enhanced_databank.log"
    cp -- "$newest_probe" "$debug_dir/databank_probe.log"
else
    echo "Warning: no databank_probe.log was found" >&2
fi

mapfile -t crash_dirs < <(
    find "$crash_root" -mindepth 1 -maxdepth 1 -type d -name 'UECC-*' -printf '%T@ %p\n' \
        | sort -nr \
        | head -n "$crash_count" \
        | cut -d' ' -f2-
)

if ((${#crash_dirs[@]} == 0)); then
    echo "Warning: no Unreal crash reports were found" >&2
    rm -f -- "$debug_dir/recent-crashes.zip"
else
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    crash_stage="$temp_dir/recent-crashes"
    mkdir -p -- "$crash_stage"

    for crash_dir in "${crash_dirs[@]}"; do
        crash_name="$(basename -- "$crash_dir")"
        mkdir -p -- "$crash_stage/$crash_name"

        for filename in \
            CrashContext.runtime-xml \
            CrashReportClient.ini \
            UEMinidump.dmp \
            SWZeroCompany.user_settings; do
            if [[ -f "$crash_dir/$filename" ]]; then
                cp -- "$crash_dir/$filename" "$crash_stage/$crash_name/"
            fi
        done
    done

    (
        cd -- "$crash_stage"
        zip -qr "$temp_dir/recent-crashes.zip" .
    )
    mv -f -- "$temp_dir/recent-crashes.zip" "$debug_dir/recent-crashes.zip"
fi

echo "Collected debug files in: $debug_dir"
echo "  UE4SS: $ue4ss_log"
if [[ -n "$newest_probe" ]]; then
    echo "  Probe: $newest_probe"
fi
echo "  Crash reports: ${#crash_dirs[@]} newest from $crash_root"
