#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEBUG_DIR="${ENHANCED_DATABANK_DEBUG_DIR:-$SCRIPT_DIR/debug}"
UE4SS_DIR="${UE4SS_DIR:-${1:-}}"
CRASH_DIR="${SWZC_CRASH_DIR:-}"
CRASH_WINDOW_MINUTES="${CRASH_WINDOW_MINUTES:-15}"

if [[ -z "$UE4SS_DIR" ]]; then
    printf 'Usage: UE4SS_DIR=/path/to/ue4ss %s\n' "$0" >&2
    printf '   or: %s /path/to/ue4ss\n' "$0" >&2
    exit 2
fi

mkdir -p -- "$DEBUG_DIR"

log_missing=0
if [[ -f "$UE4SS_DIR/UE4SS.log" ]]; then
    cp -f -- "$UE4SS_DIR/UE4SS.log" "$DEBUG_DIR/UE4SS.log"
    printf 'Copied UE4SS.log to %s\n' "$DEBUG_DIR/UE4SS.log"
else
    printf 'Warning: UE4SS.log was not found at %s\n' "$UE4SS_DIR/UE4SS.log" >&2
    log_missing=1
fi

mod_log=""
for candidate in \
    "$UE4SS_DIR/Mods/Enhanced Databank/enhanced_databank.log" \
    "$UE4SS_DIR/Mods/EnhancedDatabank/enhanced_databank.log" \
    "$UE4SS_DIR/enhanced_databank.log"; do
    if [[ -f "$candidate" && ( -z "$mod_log" || "$candidate" -nt "$mod_log" ) ]]; then
        mod_log="$candidate"
    fi
done

if [[ -n "$mod_log" ]]; then
    cp -f -- "$mod_log" "$DEBUG_DIR/enhanced_databank.log"
    printf 'Copied enhanced_databank.log to %s\n' "$DEBUG_DIR/enhanced_databank.log"
else
    printf 'Warning: no Enhanced Databank log was found\n' >&2
fi

if [[ -n "$CRASH_DIR" && -d "$CRASH_DIR" ]]; then
    recent_crashes=()
    while IFS= read -r -d '' crash_path; do
        recent_crashes+=("${crash_path##*/}")
    done < <(
        find "$CRASH_DIR" -mindepth 1 -maxdepth 1 -type d \
            -mmin "-$CRASH_WINDOW_MINUTES" -print0
    )

    if ((${#recent_crashes[@]} > 0)); then
        command -v zip >/dev/null 2>&1 || {
            printf 'Error: zip is required to archive recent crashes\n' >&2
            exit 1
        }

        temporary_dir="$(mktemp -d "$DEBUG_DIR/.recent-crashes.XXXXXX")"
        trap 'rm -rf -- "${temporary_dir:-}"' EXIT
        archive_tmp="$temporary_dir/recent-crashes.zip"

        (cd -- "$CRASH_DIR" && zip -qr "$archive_tmp" "${recent_crashes[@]}")
        mv -f -- "$archive_tmp" "$DEBUG_DIR/recent-crashes.zip"
        printf 'Archived %d recent crash folder(s) to %s\n' \
            "${#recent_crashes[@]}" "$DEBUG_DIR/recent-crashes.zip"
    else
        rm -f -- "$DEBUG_DIR/recent-crashes.zip"
        printf 'No crash folders modified in the last %s minutes\n' "$CRASH_WINDOW_MINUTES"
    fi
elif [[ -n "$CRASH_DIR" ]]; then
    rm -f -- "$DEBUG_DIR/recent-crashes.zip"
    printf 'Crash directory is unavailable: %s\n' "$CRASH_DIR"
else
    printf 'SWZC_CRASH_DIR is unset; skipping crash collection\n'
fi

exit "$log_missing"
