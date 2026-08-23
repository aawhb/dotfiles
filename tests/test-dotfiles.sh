#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/dot_config/dotfiles/bash/bashrc"
bash -n "$root/dot_config/blesh/init.sh"

if grep -RIl $'\u2014' "$root" --exclude-dir=.git | grep -q .; then
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
