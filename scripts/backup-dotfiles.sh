#!/usr/bin/env bash
set -euo pipefail

apply=false
output_root=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/migrations
while (($#)); do
    case $1 in
        --apply) apply=true ;;
        --output-root)
            shift
            (($#)) || { echo "--output-root requires a path" >&2; exit 2; }
            output_root=$1
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

targets=(
    "$HOME/.bashrc"
    "$HOME/.gitconfig"
    "$HOME/.ssh/config"
    "$HOME/.ssh/config.d/00-dotfiles.conf"
    "$HOME/.ssh/config.d/20-platform-ops.conf"
    "$HOME/.ssh/platform-ops_known_hosts"
    "$HOME/.config/atuin/config.toml"
    "$HOME/.config/atuin/permissions.ai.toml"
    "$HOME/.config/herdr/config.toml"
    "$HOME/.config/dotfiles/bash/bashrc"
    "$HOME/.config/dotfiles/git/config"
    "$HOME/.config/oh-my-posh/emodipt-extend.omp.json"
    "$HOME/.codex/AGENTS.md"
    "$HOME/.codex/config.toml"
    "$HOME/.local/bin/connect-aawhb-atuin"
)

echo "Dotfiles backup preview:"
printf '  %s\n' "${targets[@]}"
$apply || { echo "Preview only. Re-run with --apply."; exit 0; }

run="$output_root/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run/backup"
: > "$run/manifest.tsv"
for index in "${!targets[@]}"; do
    target=${targets[$index]}
    if [[ -f $target ]]; then
        cp -p -- "$target" "$run/backup/$index"
        printf '%s\ttrue\tbackup/%s\n' "$target" "$index" >> "$run/manifest.tsv"
    else
        printf '%s\tfalse\t-\n' "$target" >> "$run/manifest.tsv"
    fi
done

echo "Backup: $run"
echo "Rollback preview: bash scripts/restore-dotfiles.sh '$run'"
echo "Rollback apply: bash scripts/restore-dotfiles.sh '$run' --apply"

