#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/dot_config/dotfiles/bash/bashrc"
bash -n "$root/dot_config/blesh/init.sh"
bash -n "$root/scripts/backup-dotfiles.sh"
bash -n "$root/scripts/restore-dotfiles.sh"

rendered_linux_installer=$(mktemp)
cleanup() {
    rm -f -- "$rendered_linux_installer"
}
trap cleanup EXIT
sed '/^{{.*}}$/d' "$root/run_onchange_after_10-install-linux-tools.sh.tmpl" \
    > "$rendered_linux_installer"
bash -n "$rendered_linux_installer"
test "$(head -n 1 "$rendered_linux_installer")" = '#!/usr/bin/env bash'

for checksum in $(grep -E '^[[:space:]]+[0-9a-f]{64} \\' \
    "$root/run_onchange_after_10-install-linux-tools.sh.tmpl" | awk '{print $1}'); do
    test ${#checksum} -eq 64
done

grep -Fq 'Linux tool setup summary' \
    "$root/run_onchange_after_10-install-linux-tools.sh.tmpl"
grep -Fq 'failures=$((failures + 1))' \
    "$root/run_onchange_after_10-install-linux-tools.sh.tmpl"

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
