# Shared Linux tool pins and installation logic. This file is included in the
# automatic installer and sourced by the explicit update command.

declare -Ar LINUX_TOOL_KIND=(
    [blesh]=archive-xz
    [atuin]=archive-gzip
    [oh-my-posh]=file
    [zoxide]=archive-gzip
    [just]=archive-gzip
    [herdr]=file
    [bitwarden-cli]=archive-zip
    [tailscale]=system
)
declare -Ar LINUX_TOOL_VERSION=(
    [blesh]=0.4.0-devel3
    [atuin]=18.19.0
    [oh-my-posh]=30.6.5
    [zoxide]=0.10.0
    [just]=1.58.0
    [herdr]=0.9.1
    [bitwarden-cli]=2026.7.0
)
declare -Ar LINUX_TOOL_URL=(
    [blesh]=https://github.com/akinomyoga/ble.sh/releases/download/v0.4.0-devel3/ble-0.4.0-devel3.tar.xz
    [atuin]=https://github.com/atuinsh/atuin/releases/download/v18.19.0/atuin-x86_64-unknown-linux-gnu.tar.gz
    [oh-my-posh]=https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v30.6.5/posh-linux-amd64
    [zoxide]=https://github.com/ajeetdsouza/zoxide/releases/download/v0.10.0/zoxide-0.10.0-x86_64-unknown-linux-musl.tar.gz
    [just]=https://github.com/casey/just/releases/download/1.58.0/just-1.58.0-x86_64-unknown-linux-musl.tar.gz
    [herdr]=https://github.com/herdrdev/herdr/releases/download/v0.9.1/herdr-linux-x86_64
    [bitwarden-cli]=https://github.com/bitwarden/clients/releases/download/cli-v2026.7.0/bw-linux-2026.7.0.zip
)
declare -Ar LINUX_TOOL_SHA256=(
    [blesh]=c8612ee612bc6b10dbfd6e85c6cbdfd7caf152a12d1f9de22ea0a9d735b3080c
    [atuin]=4d7559ada42407ee8ddc62349acf134dd297568d032c45a746a7aef8a6860648
    [oh-my-posh]=079febf68932744a6c8d05179a2798bca083613275eca6de41b1efe9c82e15c8
    [zoxide]=2d93385b99f3e82cf2701609a1bffcad863fbeb75aa3fe7eb6be4d29be68b1ae
    [just]=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d
    [herdr]=2a02fed16beb651ef006e1d43f048f652ca4dc58ad053cd2d44450563d5c54b7
    [bitwarden-cli]=7a35145e205952f7434d2370da359543145ae0c45ba1af0fe9bdd99d40a00180
)
declare -Ar LINUX_TOOL_BINARY=(
    [blesh]=ble.sh
    [atuin]=atuin
    [oh-my-posh]=oh-my-posh
    [zoxide]=zoxide
    [just]=just
    [herdr]=herdr
    [bitwarden-cli]=bw
)
declare -Ar LINUX_TOOL_COMMAND=(
    [atuin]=atuin
    [oh-my-posh]=oh-my-posh
    [zoxide]=zoxide
    [just]=just
    [herdr]=herdr
    [bitwarden-cli]=bw
)
declare -Ar LINUX_TOOL_VERSION_ARGUMENT=(
    [atuin]=--version
    [oh-my-posh]=version
    [zoxide]=--version
    [just]=--version
    [herdr]=--version
    [bitwarden-cli]=--version
)
declare -Ar LINUX_TOOL_TARGET=(
    [blesh]=share/blesh
    [atuin]=bin/atuin
    [oh-my-posh]=bin/oh-my-posh
    [zoxide]=bin/zoxide
    [just]=bin/just
    [herdr]=bin/herdr
    [bitwarden-cli]=bin/bw
)

LINUX_TOOL_RESULTS=()
LINUX_TOOL_FAILURES=0
LINUX_TOOL_TMP_ROOT=
LINUX_TOOL_SKIP_REASON=
LINUX_TOOL_ACTIVE_PATH=
LINUX_TOOL_ACTIVE_VERSION=

linux_tool_record_result() {
    local name=$1 status=$2 detail=$3
    LINUX_TOOL_RESULTS+=("$name|$status|$detail")
    if [[ $status == failed ]]; then
        LINUX_TOOL_FAILURES=$((LINUX_TOOL_FAILURES + 1))
    fi
}

linux_tool_download_and_verify() {
    local url=$1 checksum=$2 destination=$3

    curl --fail --location --silent --show-error "$url" --output "$destination" || return 1
    printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status
}

linux_tool_extract_version() {
    local text=$1 version
    version=$(printf '%s\n' "$text" \
        | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}(-[[:alnum:]][[:alnum:].-]*)?' \
        | head -n 1 || true)
    [[ -n $version ]] || return 1
    printf '%s\n' "${version#v}"
}

linux_tool_blesh_version() {
    local file=$1 declaration
    declaration=$(sed -nE \
        's/^[[:space:]]*_ble_init_version=([^[:space:]]+).*/\1/p' "$file" \
        | head -n 1 || true)
    [[ -n $declaration ]] || return 1
    linux_tool_extract_version "$declaration"
}

linux_tool_version_is_newer() {
    local current=${1#v} pinned=${2#v}
    local current_core pinned_core current_pre pinned_pre newest

    current=${current%%+*}
    pinned=${pinned%%+*}
    current_core=${current%%-*}
    pinned_core=${pinned%%-*}
    current_pre=
    pinned_pre=
    [[ $current == *-* ]] && current_pre=${current#*-}
    [[ $pinned == *-* ]] && pinned_pre=${pinned#*-}

    if [[ $current_core == "$pinned_core" ]]; then
        if [[ -z $current_pre && -n $pinned_pre ]]; then
            return 0
        fi
        if [[ -n $current_pre && -z $pinned_pre ]]; then
            return 1
        fi
        [[ -n $current_pre ]] || return 1
        newest=$(printf '%s\n%s\n' "$current_pre" "$pinned_pre" | LC_ALL=C sort -V | tail -n 1)
        [[ $newest == "$current_pre" && $current_pre != "$pinned_pre" ]]
        return
    fi

    newest=$(printf '%s\n%s\n' "$current_core" "$pinned_core" | LC_ALL=C sort -V | tail -n 1)
    [[ $newest == "$current_core" && $current_core != "$pinned_core" ]]
}

linux_tool_local_target() {
    local name=$1
    printf '%s/%s\n' "$HOME/.local" "${LINUX_TOOL_TARGET[$name]}"
}

linux_tool_target_version() {
    local name=$1 target output
    target=$(linux_tool_local_target "$name")
    if [[ $name == blesh ]]; then
        [[ -r $target/ble.sh ]] || return 1
        linux_tool_blesh_version "$target/ble.sh"
        return
    else
        [[ -x $target ]] || return 1
        output=$("$target" "${LINUX_TOOL_VERSION_ARGUMENT[$name]}" 2>&1) || return 1
    fi
    linux_tool_extract_version "$output"
}

linux_tool_path_is_local() {
    local candidate=$1 local_root real_candidate
    local_root=$(realpath -m -- "$HOME/.local") || return 1
    real_candidate=$(realpath -e -- "$candidate") || return 1
    [[ $real_candidate == "$local_root/"* ]]
}

linux_tool_active_path() {
    local name=$1 command_name active expected active_real expected_real target
    LINUX_TOOL_SKIP_REASON=
    LINUX_TOOL_ACTIVE_PATH=

    if [[ $name == blesh ]]; then
        target=$(linux_tool_local_target "$name")
        active=$target/ble.sh
        if [[ -L $target || -L $active ]]; then
            LINUX_TOOL_SKIP_REASON='The ble.sh target is a symlink-managed installation.'
            return 1
        fi
        if [[ ! -r $active ]]; then
            LINUX_TOOL_SKIP_REASON='No installed ~/.local ble.sh tree was found.'
            return 1
        fi
        if ! linux_tool_path_is_local "$active"; then
            LINUX_TOOL_SKIP_REASON='The ble.sh target does not resolve inside ~/.local.'
            return 1
        fi
        LINUX_TOOL_ACTIVE_PATH=$active
        return 0
    fi

    command_name=${LINUX_TOOL_COMMAND[$name]}
    if [[ $(type -t "$command_name" 2>/dev/null || true) != file ]]; then
        LINUX_TOOL_SKIP_REASON="No active external $command_name command was found."
        return 1
    fi
    active=$(type -P "$command_name" 2>/dev/null || true)
    if [[ -z $active ]]; then
        LINUX_TOOL_SKIP_REASON="No active external $command_name command was found."
        return 1
    fi
    expected=$(linux_tool_local_target "$name")
    if [[ ! -x $expected ]]; then
        LINUX_TOOL_SKIP_REASON="No installed ~/.local/bin/$command_name was found."
        return 1
    fi
    if [[ -L $expected ]]; then
        LINUX_TOOL_SKIP_REASON="$command_name is a symlink-managed installation."
        return 1
    fi
    active_real=$(realpath -e -- "$active" 2>/dev/null || true)
    expected_real=$(realpath -e -- "$expected" 2>/dev/null || true)
    if [[ -z $active_real || $active_real != "$expected_real" ]] || \
        ! linux_tool_path_is_local "$active"; then
        LINUX_TOOL_SKIP_REASON="$command_name is not resolving to its active ~/.local installation."
        return 1
    fi
    LINUX_TOOL_ACTIVE_PATH=$active
}

linux_tool_active_version() {
    local name=$1 output
    LINUX_TOOL_ACTIVE_VERSION=
    linux_tool_active_path "$name" || return 1
    if [[ $name == blesh ]]; then
        LINUX_TOOL_ACTIVE_VERSION=$(linux_tool_blesh_version "$LINUX_TOOL_ACTIVE_PATH") || {
            LINUX_TOOL_SKIP_REASON='Could not parse the active ble.sh version declaration.'
            return 1
        }
        return 0
    else
        output=$("$LINUX_TOOL_ACTIVE_PATH" "${LINUX_TOOL_VERSION_ARGUMENT[$name]}" 2>&1) || {
            LINUX_TOOL_SKIP_REASON="Could not read the active ${LINUX_TOOL_COMMAND[$name]} version."
            return 1
        }
    fi
    LINUX_TOOL_ACTIVE_VERSION=$(linux_tool_extract_version "$output") || {
        LINUX_TOOL_SKIP_REASON="Could not parse the active $name version."
        return 1
    }
}

linux_tool_install_archive_binary() {
    local name=$1 archive_suffix=$2
    local target archive extract_root staged source
    target=$(linux_tool_local_target "$name")
    archive=$LINUX_TOOL_TMP_ROOT/$name.$archive_suffix
    extract_root=$LINUX_TOOL_TMP_ROOT/$name-extract
    staged=$target.new.$$

    if [[ $archive_suffix == tar.xz ]]; then
        if ! linux_tool_download_and_verify "${LINUX_TOOL_URL[$name]}" \
            "${LINUX_TOOL_SHA256[$name]}" "$archive"; then
            linux_tool_record_result "$name" failed 'Download or checksum verification failed.'
            return
        fi
        mkdir -p "$extract_root"
        if ! tar -xJf "$archive" -C "$extract_root"; then
            linux_tool_record_result "$name" failed 'Archive extraction failed. Ensure xz support is installed.'
            return
        fi
        source=$(find "$extract_root" -mindepth 1 -maxdepth 1 -type d -print -quit)
        if [[ -z $source || ! -r $source/ble.sh ]] || \
            ! grep -Fq "${LINUX_TOOL_VERSION[$name]}" "$source/ble.sh"; then
            linux_tool_record_result "$name" failed 'Archive did not contain the expected pinned ble.sh tree.'
            return
        fi
        mkdir -p "$(dirname "$target")"
        if ! mv "$source" "$staged"; then
            linux_tool_record_result "$name" failed 'Could not stage the verified ble.sh tree.'
            return
        fi
        if [[ -e $target ]] && ! mv "$target" "$target.old.$$"; then
            rm -rf -- "$staged"
            linux_tool_record_result "$name" failed 'Could not preserve the existing ble.sh tree.'
            return
        fi
        if ! mv "$staged" "$target"; then
            if [[ -e $target.old.$$ ]]; then
                mv "$target.old.$$" "$target"
            fi
            rm -rf -- "$staged"
            linux_tool_record_result "$name" failed 'Could not activate the verified ble.sh tree.'
            return
        fi
        [[ ! -e $target.old.$$ ]] || rm -rf -- "$target.old.$$"
        linux_tool_record_result "$name" installed "Installed version ${LINUX_TOOL_VERSION[$name]}."
        return
    fi

    mkdir -p "$extract_root"
    if ! linux_tool_download_and_verify "${LINUX_TOOL_URL[$name]}" \
        "${LINUX_TOOL_SHA256[$name]}" "$archive"; then
        linux_tool_record_result "$name" failed 'Download or checksum verification failed.'
        return
    fi
    if [[ $archive_suffix == zip ]]; then
        if ! command -v unzip > /dev/null 2>&1; then
            linux_tool_record_result "$name" failed 'Installation requires unzip.'
            return
        fi
        if ! unzip -q "$archive" -d "$extract_root"; then
            linux_tool_record_result "$name" failed 'Archive extraction failed.'
            return
        fi
    elif ! tar -xzf "$archive" -C "$extract_root"; then
        linux_tool_record_result "$name" failed 'Archive extraction failed.'
        return
    fi
    source=$(find "$extract_root" -type f -name "${LINUX_TOOL_BINARY[$name]}" -print -quit)
    if [[ -z $source ]]; then
        linux_tool_record_result "$name" failed "Archive did not contain ${LINUX_TOOL_BINARY[$name]}."
        return
    fi
    mkdir -p "$(dirname "$target")"
    if ! install -m 0755 "$source" "$staged"; then
        linux_tool_record_result "$name" failed 'Could not install the verified binary.'
        return
    fi
    if ! "$staged" "${LINUX_TOOL_VERSION_ARGUMENT[$name]}" 2>&1 \
        | grep -Fq "${LINUX_TOOL_VERSION[$name]}"; then
        rm -f -- "$staged"
        linux_tool_record_result "$name" failed 'Installed binary did not pass its pinned version check.'
        return
    fi
    if ! mv -f -- "$staged" "$target"; then
        rm -f -- "$staged"
        linux_tool_record_result "$name" failed 'Could not activate the verified binary.'
        return
    fi
    linux_tool_record_result "$name" installed "Installed version ${LINUX_TOOL_VERSION[$name]}."
}

linux_tool_install_file_binary() {
    local name=$1 target download staged
    target=$(linux_tool_local_target "$name")
    download=$LINUX_TOOL_TMP_ROOT/$name
    staged=$target.new.$$

    if ! linux_tool_download_and_verify "${LINUX_TOOL_URL[$name]}" \
        "${LINUX_TOOL_SHA256[$name]}" "$download"; then
        linux_tool_record_result "$name" failed 'Download or checksum verification failed.'
        return
    fi
    mkdir -p "$(dirname "$target")"
    if ! install -m 0755 "$download" "$staged"; then
        linux_tool_record_result "$name" failed 'Could not install the verified binary.'
        return
    fi
    if ! "$staged" "${LINUX_TOOL_VERSION_ARGUMENT[$name]}" 2>&1 \
        | grep -Fq "${LINUX_TOOL_VERSION[$name]}"; then
        rm -f -- "$staged"
        linux_tool_record_result "$name" failed 'Installed binary did not pass its pinned version check.'
        return
    fi
    if ! mv -f -- "$staged" "$target"; then
        rm -f -- "$staged"
        linux_tool_record_result "$name" failed 'Could not activate the verified binary.'
        return
    fi
    linux_tool_record_result "$name" installed "Installed version ${LINUX_TOOL_VERSION[$name]}."
}

linux_tool_install_tailscale() {
    local installer=$LINUX_TOOL_TMP_ROOT/tailscale-install.sh

    if command -v tailscale > /dev/null 2>&1; then
        linux_tool_record_result tailscale available 'Tailscale is already installed.'
        return
    fi
    if ! command -v curl > /dev/null 2>&1; then
        linux_tool_record_result tailscale failed 'Installation requires curl.'
        return
    fi
    if [[ $EUID -ne 0 ]] && ! command -v sudo > /dev/null 2>&1; then
        linux_tool_record_result tailscale failed 'Installation requires sudo when not running as root.'
        return
    fi
    if ! curl --fail --location --silent --show-error \
        https://tailscale.com/install.sh --output "$installer"; then
        linux_tool_record_result tailscale failed 'Could not download the official installer.'
        return
    fi
    if ! sh "$installer"; then
        linux_tool_record_result tailscale failed 'The official installer failed.'
        return
    fi
    hash -r
    if ! command -v tailscale > /dev/null 2>&1; then
        linux_tool_record_result tailscale failed 'Installation did not expose the command.'
        return
    fi
    linux_tool_record_result tailscale installed 'Installed Tailscale. Run tailscale up to enroll this machine.'
}

linux_tool_install_one() {
    local name=$1 current target
    if [[ ! ${LINUX_TOOL_KIND[$name]+defined} ]]; then
        linux_tool_record_result "$name" failed 'No Linux installer is defined for this selected tool.'
        return
    fi
    if [[ ${LINUX_TOOL_KIND[$name]} == system ]]; then
        linux_tool_install_tailscale
        return
    fi
    target=$(linux_tool_local_target "$name")
    if [[ -L $target || ( $name == blesh && -L $target/ble.sh ) ]]; then
        linux_tool_record_result "$name" skipped 'The ~/.local target is symlink-managed; leaving its owner in control.'
        return
    fi

    if current=$(linux_tool_target_version "$name"); then
        if [[ $current == "${LINUX_TOOL_VERSION[$name]}" ]]; then
            linux_tool_record_result "$name" available "Version $current is already installed."
            return
        fi
        if linux_tool_version_is_newer "$current" "${LINUX_TOOL_VERSION[$name]}"; then
            linux_tool_record_result "$name" available \
                "Version $current is newer than repository pin ${LINUX_TOOL_VERSION[$name]}; leaving it installed."
            return
        fi
    fi

    case ${LINUX_TOOL_KIND[$name]} in
        archive-xz) linux_tool_install_archive_binary "$name" tar.xz ;;
        archive-gzip) linux_tool_install_archive_binary "$name" tar.gz ;;
        archive-zip) linux_tool_install_archive_binary "$name" zip ;;
        file) linux_tool_install_file_binary "$name" ;;
    esac
}

linux_tool_update_one() {
    local name=$1 apply=$2 current
    if [[ ! ${LINUX_TOOL_KIND[$name]+defined} ]]; then
        linux_tool_record_result "$name" skipped 'No Linux installer is defined for this selected tool.'
        return
    fi
    if [[ ${LINUX_TOOL_KIND[$name]} == system ]]; then
        linux_tool_record_result "$name" skipped 'System-managed tool; update through its package owner.'
        return
    fi
    if ! linux_tool_active_version "$name"; then
        linux_tool_record_result "$name" skipped "$LINUX_TOOL_SKIP_REASON"
        return
    fi
    current=$LINUX_TOOL_ACTIVE_VERSION
    if linux_tool_version_is_newer "$current" "${LINUX_TOOL_VERSION[$name]}"; then
        linux_tool_record_result "$name" skipped \
            "Active version $current is newer than repository pin ${LINUX_TOOL_VERSION[$name]}; leaving it installed."
        return
    fi
    if [[ $current == "${LINUX_TOOL_VERSION[$name]}" ]]; then
        linux_tool_record_result "$name" current "Active version $current matches the repository pin."
        return
    fi
    if [[ $apply == 0 ]]; then
        linux_tool_record_result "$name" update-available \
            "Active version $current; repository pin is ${LINUX_TOOL_VERSION[$name]}."
        return
    fi
    linux_tool_install_one "$name"
}

linux_tool_print_summary() {
    local title=$1 result name status detail
    printf '\n%s\n' "$title"
    printf '%-20s %-17s %s\n' Tool Status Detail
    for result in "${LINUX_TOOL_RESULTS[@]}"; do
        IFS='|' read -r name status detail <<< "$result"
        printf '%-20s %-17s %s\n' "$name" "$status" "$detail"
    done
    if ((LINUX_TOOL_FAILURES > 0)); then
        printf '%d selected tool(s) failed.\n' "$LINUX_TOOL_FAILURES" >&2
        return 1
    fi
}

linux_tool_run() {
    local operation=$1 apply=$2 name title needs_temp=0
    shift 2
    LINUX_TOOL_RESULTS=()
    LINUX_TOOL_FAILURES=0
    LINUX_TOOL_TMP_ROOT=

    if [[ $operation == install || $apply == 1 ]]; then
        needs_temp=1
    fi
    if ((needs_temp)); then
        if ! LINUX_TOOL_TMP_ROOT=$(mktemp -d); then
            linux_tool_record_result linux-tools failed 'Could not create a temporary installation directory.'
            linux_tool_print_summary 'Linux tool setup summary:'
            return 1
        fi
        trap linux_tool_cleanup EXIT
    fi

    for name in "$@"; do
        [[ -n $name ]] || continue
        if [[ $operation == install ]]; then
            linux_tool_install_one "$name"
        else
            linux_tool_update_one "$name" "$apply"
        fi
    done

    if [[ $operation == install ]]; then
        title='Linux tool setup summary:'
    elif [[ $apply == 1 ]]; then
        title='Linux tool update summary:'
    else
        title='Linux tool update preview:'
    fi
    if ! linux_tool_print_summary "$title"; then
        linux_tool_cleanup
        return 1
    fi
    linux_tool_cleanup
}

linux_tool_cleanup() {
    if [[ -n $LINUX_TOOL_TMP_ROOT ]]; then
        rm -rf -- "$LINUX_TOOL_TMP_ROOT"
        LINUX_TOOL_TMP_ROOT=
    fi
}

linux_tools_install_selected() {
    linux_tool_run install 1 "$@"
}

linux_tools_update_selected() {
    local apply=$1
    shift
    linux_tool_run update "$apply" "$@"
}
