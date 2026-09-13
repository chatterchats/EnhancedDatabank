#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEBUG_DIR="${ENHANCED_DATABANK_DEBUG_DIR:-$SCRIPT_DIR/debug}"
UE4SS_DIR="${UE4SS_DIR:-${1:-}}"

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

exit "$log_missing"
