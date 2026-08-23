[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $HOME '.local\state\dotfiles\migrations'),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$targets = @(
    $PROFILE.CurrentUserCurrentHost,
    (Join-Path $HOME '.gitconfig'),
    (Join-Path $HOME '.ssh\config'),
    (Join-Path $HOME '.ssh\config.d\00-dotfiles.conf'),
    (Join-Path $HOME '.ssh\config.d\20-platform-ops.conf'),
    (Join-Path $HOME '.ssh\platform-ops_known_hosts'),
    (Join-Path $HOME '.config\atuin\config.toml'),
    (Join-Path $HOME '.config\atuin\permissions.ai.toml'),
    (Join-Path $HOME '.config\herdr\config.toml'),
    (Join-Path $HOME '.config\dotfiles\powershell\profile.ps1'),
    (Join-Path $HOME '.config\dotfiles\git\config'),
    (Join-Path $HOME '.config\oh-my-posh\emodipt-extend.omp.json'),
    (Join-Path $HOME '.codex\AGENTS.md'),
    (Join-Path $HOME '.codex\config.toml'),
    (Join-Path $HOME '.local\bin\Connect-AawhbAtuin.ps1'),
    (Join-Path $HOME '.local\bin\herdr.cmd')
) | Select-Object -Unique

'Dotfiles backup preview:'
$targets | ForEach-Object { "  $_" }
if (-not $Apply) {
    'Preview only. Re-run with -Apply.'
    return
}

$run = Join-Path $OutputRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
$backup = Join-Path $run 'backup'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$manifest = for ($index = 0; $index -lt $targets.Count; $index++) {
    $target = [IO.Path]::GetFullPath($targets[$index])
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    $backupName = "$index"
    if ($exists) {
        Copy-Item -LiteralPath $target -Destination (Join-Path $backup $backupName)
    }
    [pscustomobject]@{
        Target = $target
        Existed = $exists
        Backup = if ($exists) { "backup/$backupName" } else { $null }
    }
}
$manifest | ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath (Join-Path $run 'manifest.json')

"Backup: $run"
"Rollback preview: pwsh -NoLogo -NoProfile -File scripts/Restore-Dotfiles.ps1 -RunPath '$run'"
"Rollback apply: pwsh -NoLogo -NoProfile -File scripts/Restore-Dotfiles.ps1 -RunPath '$run' -Apply"

