#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
update_script=$root/scripts/update-linux-tools.sh
real_chezmoi=$(command -v chezmoi || true)
if [[ -z $real_chezmoi ]]; then
    echo 'Linux tool behavior tests require chezmoi.' >&2
    exit 1
fi
system_sha256sum=$(command -v sha256sum)
test_root=$(mktemp -d)
cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT

export HOME=$test_root/home
export TMPDIR=$test_root/tmp
export FAKE_CURL_LOG=$test_root/curl.log
export FAKE_SELECTED_TOOLS=
export FAKE_HERDR_OUTPUT_VERSION=0.9.1
export SYSTEM_SHA256SUM=$system_sha256sum
mkdir -p "$HOME" "$TMPDIR" "$test_root/fake-bin"
base_path=$PATH

cat > "$test_root/fake-bin/chezmoi" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1-} != execute-template ]]; then
    exit 64
fi
printf '%s\n' "$FAKE_SELECTED_TOOLS"
STUB

cat > "$test_root/fake-bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
arguments=$*
output=
while (($#)); do
    if [[ $1 == --output ]]; then
        output=$2
        shift 2
    else
        shift
    fi
done
[[ -n $output ]] || exit 64
printf '%s\n' "$arguments" >> "$FAKE_CURL_LOG"
cat > "$output" <<'BINARY'
#!/usr/bin/env bash
printf 'herdr %s\n' "${FAKE_HERDR_OUTPUT_VERSION:?}"
BINARY
chmod 0755 "$output"
STUB

cat > "$test_root/fake-bin/sha256sum" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1-} == --check && ${2-} == --status ]]; then
    case ${FAKE_SHA256_MODE:-real} in
        pass) exit 0 ;;
        fail) exit 1 ;;
    esac
fi
exec "$SYSTEM_SHA256SUM" "$@"
STUB

chmod 0755 "$test_root/fake-bin/chezmoi" "$test_root/fake-bin/curl" \
    "$test_root/fake-bin/sha256sum"
export PATH="$HOME/.local/bin:$test_root/fake-bin:$base_path"

fail() {
    printf 'Linux tool behavior test failed: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local output=$1 expected=$2
    [[ $output == *"$expected"* ]] || fail "expected output to contain: $expected"
}

assert_no_downloads_or_temporary_files() {
    local first_entry
    [[ ! -s $FAKE_CURL_LOG ]] || fail 'unexpected download request'
    first_entry=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print -quit)
    [[ -z $first_entry ]] || fail 'temporary installer files were not cleaned up'
}

write_herdr_binary() {
    local destination=$1 version=$2
    mkdir -p "$(dirname "$destination")"
    cat > "$destination" <<BINARY
#!/usr/bin/env bash
printf 'herdr %s\\n' '$version'
BINARY
    chmod 0755 "$destination"
}

export FAKE_SELECTED_TOOLS=$'herdr\ntailscale'
preview_output=$(bash "$update_script") || fail 'default preview returned an error'
assert_contains "$preview_output" 'Linux tool update preview:'
grep -Eq '^herdr[[:space:]]+skipped' <<< "$preview_output" || fail 'missing Herdr was not skipped'
grep -Eq '^tailscale[[:space:]]+skipped.*System-managed' <<< "$preview_output" || \
    fail 'system-managed Tailscale was not skipped'
[[ ! -e $HOME/.local ]] || fail 'preview created a ~/.local tree'
assert_no_downloads_or_temporary_files

write_herdr_binary "$test_root/fake-bin/herdr" 0.9.0
export FAKE_SELECTED_TOOLS=herdr
native_output=$(bash "$update_script" --apply) || fail 'native Herdr owner case returned an error'
grep -Eq '^herdr[[:space:]]+skipped.*No installed ~/.local/bin/herdr' <<< "$native_output" || \
    fail 'native Herdr owner was not skipped'
[[ $("$test_root/fake-bin/herdr" --version) == 'herdr 0.9.0' ]] || \
    fail 'native Herdr owner was changed'
assert_no_downloads_or_temporary_files
rm -f -- "$test_root/fake-bin/herdr"

write_herdr_binary "$HOME/.local/bin/herdr" 0.9.0
export FAKE_SELECTED_TOOLS=herdr
preview_output=$(bash "$update_script") || fail 'outdated preview returned an error'
grep -Eq '^herdr[[:space:]]+update-available' <<< "$preview_output" || \
    fail 'preview did not report an available pinned update'
[[ $("$HOME/.local/bin/herdr" --version) == 'herdr 0.9.0' ]] || \
    fail 'default preview changed the installed Herdr binary'
assert_no_downloads_or_temporary_files

rm -rf -- "$HOME/.local"
mkdir -p "$HOME/.local/share/mise/installs/herdr/0.9.0/bin" "$HOME/.local/bin"
write_herdr_binary "$HOME/.local/share/mise/installs/herdr/0.9.0/bin/herdr" 0.9.0
ln -s "$HOME/.local/share/mise/installs/herdr/0.9.0/bin/herdr" "$HOME/.local/bin/herdr"
export FAKE_SELECTED_TOOLS=herdr
rm -f -- "$FAKE_CURL_LOG"
symlink_output=$(bash "$update_script" --apply) || fail 'mise symlink case returned an error'
grep -Eq '^herdr[[:space:]]+skipped.*symlink-managed' <<< "$symlink_output" || \
    fail 'mise-managed Herdr symlink was not skipped'
[[ -L $HOME/.local/bin/herdr ]] || fail 'mise-managed Herdr symlink was replaced'
assert_no_downloads_or_temporary_files

rm -rf -- "$HOME/.local"
write_herdr_binary "$HOME/.local/bin/herdr" 0.9.1
rm -f -- "$FAKE_CURL_LOG"
current_output=$(bash "$update_script" --apply) || fail 'current pin case returned an error'
grep -Eq '^herdr[[:space:]]+current' <<< "$current_output" || fail 'current Herdr pin was not recognized'
assert_no_downloads_or_temporary_files

write_herdr_binary "$HOME/.local/bin/herdr" 0.9.2
newer_output=$(bash "$update_script" --apply) || fail 'newer pin case returned an error'
grep -Eq '^herdr[[:space:]]+skipped.*newer than repository pin' <<< "$newer_output" || \
    fail 'newer Herdr was not protected from downgrade'
[[ $("$HOME/.local/bin/herdr" --version) == 'herdr 0.9.2' ]] || \
    fail 'newer Herdr was changed'
assert_no_downloads_or_temporary_files

write_herdr_binary "$HOME/.local/bin/herdr" 0.9.0
export FAKE_SHA256_MODE=real
export FAKE_HERDR_OUTPUT_VERSION=0.9.1
rm -f -- "$FAKE_CURL_LOG"
if checksum_output=$(bash "$update_script" --apply 2>&1); then
    fail 'checksum mismatch unexpectedly succeeded'
fi
assert_contains "$checksum_output" 'Download or checksum verification failed.'
[[ $("$HOME/.local/bin/herdr" --version) == 'herdr 0.9.0' ]] || \
    fail 'checksum failure replaced the old Herdr binary'
[[ -s $FAKE_CURL_LOG ]] || fail 'checksum failure did not use the stub download'
assert_no_temporary_files() {
    local first_entry
    first_entry=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print -quit)
    [[ -z $first_entry ]] || fail 'temporary installer files were not cleaned up'
}
assert_no_temporary_files

rm -rf -- "$HOME/.local"
mkdir -p "$HOME/.local/share/blesh"
cat > "$HOME/.local/share/blesh/ble.sh" <<'BLESH'
# Requires Bash 0.3.0 or newer.
_ble_init_version=0.4.0-devel4+fixture
BLESH
export FAKE_SELECTED_TOOLS=blesh
rm -f -- "$FAKE_CURL_LOG"
blesh_newer_output=$(bash "$update_script" --apply) || \
    fail 'newer ble.sh pin case returned an error'
grep -Eq '^blesh[[:space:]]+skipped.*newer than repository pin' <<< "$blesh_newer_output" || \
    fail 'ble.sh version detection did not use its version declaration'
assert_no_downloads_or_temporary_files
grep -Fq '_ble_init_version=0.4.0-devel4+fixture' "$HOME/.local/share/blesh/ble.sh" || \
    fail 'newer ble.sh fixture changed'

rm -rf -- "$HOME/.local"
export FAKE_SELECTED_TOOLS=herdr
write_herdr_binary "$HOME/.local/bin/herdr" 0.9.0
export FAKE_SHA256_MODE=pass
rm -f -- "$FAKE_CURL_LOG"
apply_output=$(bash "$update_script" --apply) || fail 'fixture apply case returned an error'
grep -Eq '^herdr[[:space:]]+installed' <<< "$apply_output" || \
    fail 'selected Herdr update was not installed'
[[ $("$HOME/.local/bin/herdr" --version) == 'herdr 0.9.1' ]] || \
    fail 'fixture update did not activate the pinned binary'
[[ -s $FAKE_CURL_LOG ]] || fail 'fixture update did not call the stub downloader'
assert_no_temporary_files

fixture_config=$test_root/linux-only.toml
rendered_installer=$test_root/linux-installer.sh
bootstrap_home=$test_root/bootstrap-home
mkdir -p "$bootstrap_home"
cat > "$fixture_config" <<'CONFIG'
[data]
linuxTools = ["herdr"]
CONFIG
"$real_chezmoi" execute-template --source "$root" --config "$fixture_config" \
    --file "$root/run_onchange_after_10-install-linux-tools.sh.tmpl" \
    > "$rendered_installer"
bash -n "$rendered_installer"
if grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?tailscale[[:space:]]+up' \
    "$rendered_installer"; then
    fail 'rendered bootstrap must not enroll Tailscale automatically'
fi
rm -f -- "$FAKE_CURL_LOG"
bootstrap_output=$(HOME="$bootstrap_home" \
    PATH="$bootstrap_home/.local/bin:$test_root/fake-bin:$base_path" \
    TMPDIR="$TMPDIR" FAKE_CURL_LOG="$FAKE_CURL_LOG" \
    FAKE_HERDR_OUTPUT_VERSION=0.9.1 FAKE_SHA256_MODE=pass \
    bash "$rendered_installer") || fail 'rendered bootstrap fixture returned an error'
assert_contains "$bootstrap_output" 'Linux tool setup summary:'
grep -Eq '^herdr[[:space:]]+installed' <<< "$bootstrap_output" || \
    fail 'rendered bootstrap did not install the selected fixture tool'
[[ $("$bootstrap_home/.local/bin/herdr" --version) == 'herdr 0.9.1' ]] || \
    fail 'rendered bootstrap fixture did not activate the selected tool'
[[ -s $FAKE_CURL_LOG ]] || fail 'rendered bootstrap did not use the stub downloader'

echo 'Linux tool behavior tests passed.'
