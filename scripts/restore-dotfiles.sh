#!/usr/bin/env bash
set -euo pipefail

(($#)) || { echo "Usage: $0 RUN_PATH [--apply]" >&2; exit 2; }
run=$(realpath -- "$1")
shift
apply=false
if (($#)); then
    [[ $1 == --apply && $# -eq 1 ]] || { echo "Unknown argument" >&2; exit 2; }
    apply=true
fi
manifest="$run/manifest.tsv"
[[ -f $manifest ]] || { echo "Backup manifest does not exist: $manifest" >&2; exit 1; }

echo "Dotfiles restore preview:"
while IFS=$'\t' read -r target existed backup; do
    [[ $target == "$HOME/"* ]] || {
        echo "Restore target is outside the home directory: $target" >&2
        exit 1
    }
    if [[ $existed == true ]]; then
        echo "  restore: $target"
    else
        echo "  remove newly managed file: $target"
    fi
done < "$manifest"
$apply || { echo "Preview only. Re-run with --apply."; exit 0; }

while IFS=$'\t' read -r target existed backup; do
    if [[ $existed == true ]]; then
        source_path=$(realpath -- "$run/$backup")
        [[ $source_path == "$run/backup/"* && -f $source_path ]] || {
            echo "Invalid backup source: $source_path" >&2
            exit 1
        }
        mkdir -p "$(dirname "$target")"
        cp -p -- "$source_path" "$target"
    elif [[ -f $target ]]; then
        rm -f -- "$target"
    fi
done < "$manifest"
echo "Dotfiles targets restored. Tool binaries and application state were preserved."

