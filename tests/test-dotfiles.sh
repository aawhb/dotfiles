#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/dot_config/dotfiles/bash/bashrc"
bash -n "$root/dot_config/blesh/init.sh"
bash -n "$root/scripts/backup-dotfiles.sh"
bash -n "$root/scripts/restore-dotfiles.sh"

test -f "$root/private_dot_ssh/modify_private_config"
test -f "$root/private_dot_ssh/private_config.d/private_00-dotfiles.conf"

if grep -RIl $'\xE2\x80\x94' "$root" --exclude-dir=.git | grep -q .; then
    echo "The source contains an em dash." >&2
    exit 1
fi

for forbidden in "e-""xist" "tail""0058b1" "dev-""01" "vault-""01" \
    "BEGIN OPENSSH ""PRIVATE KEY"; do
    if grep -RIl --exclude-dir=.git "$forbidden" "$root" | grep -q .; then
        echo "Public source contains forbidden private text: $forbidden" >&2
        exit 1
    fi
done

echo "Public dotfiles tests passed."
