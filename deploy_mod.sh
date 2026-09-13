#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/src/Enhanced Databank"

if [[ ! -d "$SOURCE_DIR" ]]; then
    printf 'Error: mod source folder not found: %s\n' "$SOURCE_DIR" >&2
    exit 1
fi

if [[ -n "${UE4SS_MODS_DIR:-}" ]]; then
    mods_dir="$UE4SS_MODS_DIR"
elif [[ -n "${UE4SS_DIR:-}" ]]; then
    mods_dir="${UE4SS_DIR%/}/Mods"
elif [[ $# -ge 1 ]]; then
    mods_dir="${1%/}/Mods"
else
    printf 'Usage: UE4SS_DIR=/path/to/ue4ss %s\n' "$0" >&2
    printf '   or: UE4SS_MODS_DIR=/path/to/ue4ss/Mods %s\n' "$0" >&2
    printf '   or: %s /path/to/ue4ss\n' "$0" >&2
    exit 2
fi

destination="$mods_dir/Enhanced Databank"
mkdir -p -- "$destination"
cp -a -- "$SOURCE_DIR/." "$destination/"

printf 'Deployed Enhanced Databank from %s to %s\n' "$SOURCE_DIR" "$destination"
