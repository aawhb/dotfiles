# dotfiles

An opinionated, work-safe shell baseline managed by
[chezmoi](https://www.chezmoi.io/). It keeps prompt, completion, navigation,
Git defaults, and local command history consistent without assuming access to
private infrastructure.

## Supported systems

- Windows 11 with PowerShell 7
- Debian 13 with Bash
- Ubuntu 24.04 and 26.04 with Bash
- Ubuntu 24.04 under WSL2

macOS is not supported or tested yet. The shared configuration avoids Linux-only
paths and keeps operating-system installation logic isolated so a future Homebrew
adapter will not require a repository redesign.

## What it configures

- Oh My Posh with a tracked `emodipt-extend` theme
- PSReadLine inline history suggestions on PowerShell
- ble.sh inline suggestions and completion on Bash
- Atuin search with local-only history by default
- optional standalone fzf on Windows
- zoxide navigation
- portable Git defaults and a per-device Git identity
- an OpenSSH include directory without private hosts or keys

Atuin keeps recording and searching locally without a server. This public source
does not configure a sync address. A private downstream may add synchronization.

## Bootstrap

### Prerequisites

Windows requires Windows Package Manager and Git. Verify both before installing
chezmoi:

```powershell
winget --version
git --version
```

If Git is missing, install it and open a new PowerShell session so the updated
`PATH` is available:

```powershell
winget install --id Git.Git --exact --source winget
```

Supported Debian and Ubuntu systems require CA certificates, curl, Git, and xz
support:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git unzip xz-utils
```

### Initialize

Install chezmoi, then initialize this repository without applying anything:

```powershell
winget install --id twpayne.chezmoi --exact --source winget
chezmoi --version
chezmoi init aawhb/dotfiles
chezmoi diff
```

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi --version
chezmoi init aawhb/dotfiles
chezmoi diff
```

During initialization, use the multi-select prompt to choose exactly which tools
to install. Press Space to toggle an item and Enter to confirm the selection.
Single-choice prompts, such as `work` versus `personal`, accept a matching key
immediately; they are selectors rather than free-text fields.

PowerShell 7 is the only default Windows selection. If a managed PowerShell 7 is
already available, the installer uses it instead of reinstalling or changing its
scope. Git is a machine prerequisite and is not installed or managed by this
repository. The remaining Windows
choices are Oh My Posh, Atuin, zoxide, just, fzf, VS Code, Codex CLI, Obsidian,
uv, Azure CLI, NVM for Windows with Node.js LTS, Herdr, GitHub CLI, Bitwarden
CLI, and Tailscale. Linux defaults to the five shell tools ble.sh, Atuin, Oh My
Posh, zoxide, and just. Herdr, Bitwarden CLI, and Tailscale are additional
opt-in choices. Re-run `chezmoi init --prompt` to change selections. Deselecting
a tool prevents future install attempts but does not uninstall it.

Windows installations use exact Winget package IDs and verify each CLI from a
fresh PowerShell process. The installer refreshes environment variables and
repairs the user `PATH` from known package locations when needed. NVM installs
and activates Node.js LTS. Codex uses its Winget package first and falls back to
`npm install --global @openai/codex` only when npm is already available. fzf is
installed as a standalone command; Atuin keeps Ctrl-R and PSReadLine keeps inline
history suggestions.

Herdr uses the official `Herdr.Herdr.Preview` Winget package on Windows and a
checksum-verified stable release on Linux. Update the Windows package with:

```powershell
winget upgrade --id Herdr.Herdr.Preview --exact --source winget
```

Do not run `herdr update` for the Winget installation. That command is for
Herdr's direct installer and creates a separate standalone installation.

Bitwarden CLI and Tailscale install only their generic clients when selected.
The installer does not authenticate Bitwarden or enroll the machine in a
Tailnet. Tailscale is opt-in on Linux, where its official system-package
installer may prompt for `sudo`. Managed lab hosts should use the lab's machine
configuration for Tailscale; dotfiles selection supports standalone machines.

Linux tools use the checksum-pinned upstream releases stored in this repository
and install under `~/.local`. Both platform installers continue after an
individual failure, print a complete summary, and then return a failure so the
next `chezmoi apply` retries the incomplete setup.

After reviewing the diff and listed scripts:

```text
chezmoi apply --dry-run --verbose
chezmoi apply --verbose
chezmoi verify
```

Before the first live apply, capture every affected configuration target:

```powershell
$sourceDir = chezmoi source-path
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $sourceDir 'scripts\Backup-Dotfiles.ps1')
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $sourceDir 'scripts\Backup-Dotfiles.ps1') -Apply
```

```bash
source_dir=$(chezmoi source-path)
bash "$source_dir/scripts/backup-dotfiles.sh"
bash "$source_dir/scripts/backup-dotfiles.sh" --apply
```

Each backup prints an exact preview and apply rollback command. Rollback restores
configuration files without deleting tool binaries, history, keys, or application
state.

Authentication remains native to each tool. Use browser or CLI login where
needed, generate SSH keys on each device, and do not add histories, tokens,
sessions, private keys, or command databases to this repository.

### Update an existing installation

When the configuration prompts or data keys change, pull the source without
applying it, regenerate the configuration, and review the result:

```text
chezmoi update --apply=false
chezmoi init --prompt
chezmoi diff
```

Run the backup commands above before accepting changes to managed targets, then
apply explicitly:

```text
chezmoi apply --dry-run --verbose
chezmoi apply --verbose
chezmoi verify
```

Select every tool that should continue to be reconciled. Deselecting a tool
stops future installation attempts but does not uninstall an existing tool.

## Herdr remote sessions

Check which CLI will run before starting or updating Herdr. In PowerShell,
`Get-Command herdr -All` lists available binaries and `herdr status --json`
reports Herdr's local status. On Linux, `command -v herdr` shows the binary
selected by `PATH`. Update a package-managed install through its package owner,
such as Winget or the Linux distribution package manager. Use `herdr update`
only for Herdr's direct standalone installer. A user-local binary at
`~/.local/bin/herdr` can coexist with a distro-owned Herdr without replacing
it; `PATH` selects the shell's active binary. Herdr's saved-machine discovery
also caches a compatible remote executable, so a remote profile can use the
sidecar even when `command -v herdr` resolves the distro binary.

Register an SSH target with
`herdr machine add <ssh-alias> --remote-session <name>`. Named sessions share
Herdr's global configuration. The machine registry and cache stay on the
client; remote session records stay on the remote host. Keep those records out
of a dotfiles repository.

## Daily workflow

```text
chezmoi update --apply=false
chezmoi diff
chezmoi apply
chezmoi cd
```

The Windows bootstrap can start in Windows PowerShell 5, but it re-enters under
PowerShell 7 after locating an existing `pwsh` or installing the selected
PowerShell 7 package. Its execution-policy bypass is
limited to that child process; CurrentUser and LocalMachine policy settings are
not changed. The small profile loader is written only to the path reported by
PowerShell 7, never to the Windows PowerShell 5 profile. This also handles a
Documents Known Folder redirected to OneDrive. If PowerShell 7 is unselected and
absent, application installs continue and profile activation is skipped. The
substantive profile remains under
`~/.config/dotfiles/powershell/profile.ps1`. Bash keeps the distro-owned
`.bashrc` and adds only a marked source block.

## Public and private downstreams

This repository is intended to be a safe upstream. Personal machines can use a
private downstream that contains this full baseline plus private endpoints and
preferences. Every device should initialize exactly one source repository.
Generic changes flow from this repository into the private downstream. Never merge
the private downstream wholesale back into this repository.

## Development

```powershell
pwsh -NoLogo -NoProfile -File tests/Test-Dotfiles.ps1
```

```bash
bash tests/test-dotfiles.sh
```

The tests validate shell syntax, PowerShell parsing, template safety, and the
absence of known private infrastructure identifiers.
