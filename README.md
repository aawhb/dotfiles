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
- zoxide navigation
- portable Git defaults and a per-device Git identity
- an OpenSSH include directory without private hosts or keys

Atuin keeps recording and searching locally without a server. This public source
does not configure a sync address. A private downstream may add synchronization.

## Bootstrap

Install chezmoi, then initialize this repository without applying anything:

```powershell
winget install --id twpayne.chezmoi --exact --scope user
chezmoi init aawhb/dotfiles
chezmoi diff
```

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
chezmoi init aawhb/dotfiles
chezmoi diff
```

During initialization, choose whether chezmoi should install the optional shell
tools. Tool installation is off by default. On Windows, the opt-in installer uses
Winget. On supported Linux systems, checksum-pinned upstream releases are
installed under `~/.local/bin` because the required tools and versions are not
consistently available from all supported distro repositories.

After reviewing the diff and listed scripts:

```text
chezmoi apply --dry-run --verbose
chezmoi apply --verbose
chezmoi verify
```

Authentication remains native to each tool. Use browser login for GitHub and
Tailscale, generate SSH keys on each device, and do not add histories, tokens,
sessions, private keys, or command databases to this repository.

## Daily workflow

```text
chezmoi update
chezmoi diff
chezmoi apply
chezmoi cd
```

The small loader in the PowerShell profile is installed by an idempotent chezmoi
script because the Windows Documents Known Folder may be redirected to OneDrive.
The substantive profile remains under `~/.config/dotfiles/powershell/profile.ps1`.
Bash keeps the distro-owned `.bashrc` and adds only a marked source block.

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

