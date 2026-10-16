#!/usr/bin/env bash
set -uo pipefail

apply=0
case $# in
    0) ;;
    1)
        if [[ $1 == --apply ]]; then
            apply=1
        else
            printf 'Usage: %s [--apply]\n' "${0##*/}" >&2
            exit 2
        fi
        ;;
    *)
        printf 'Usage: %s [--apply]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

if ! command -v chezmoi > /dev/null 2>&1; then
    printf 'chezmoi is required to read the selected linuxTools.\n' >&2
    exit 1
fi

selected_tools=$(chezmoi execute-template \
    '{{ range .linuxTools }}{{ . }}{{ "\n" }}{{ end }}') || {
    printf 'Could not read linuxTools from chezmoi data.\n' >&2
    exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/linux-tools.sh
if ! source "$script_dir/linux-tools.sh"; then
    printf 'Could not load the shared Linux tool installer.\n' >&2
    exit 1
fi

if [[ -n $selected_tools ]]; then
    mapfile -t selected_tools_array <<< "$selected_tools"
else
    selected_tools_array=()
fi
linux_tools_update_selected "$apply" "${selected_tools_array[@]}"
