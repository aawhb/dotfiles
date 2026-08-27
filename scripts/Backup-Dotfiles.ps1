[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $HOME '.local\state\dotfiles\migrations'),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Get-PowerShell7ProfilePath {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pwsh) {
        $path = (& $pwsh.Source -NoLogo -NoProfile -Command '$PROFILE.CurrentUserCurrentHost' |
            Select-Object -First 1).Trim()
        if ($path) {
            return $path
        }
    }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    return Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
}

$targets = @(
    (Get-PowerShell7ProfilePath),
    (Join-Path $HOME '.gitconfig'),
    (Join-Path $HOME '.ssh\config'),
    (Join-Path $HOME '.ssh\config.d\00-dotfiles.conf'),
    (Join-Path $HOME '.config\atuin\config.toml'),
    (Join-Path $HOME '.config\dotfiles\powershell\profile.ps1'),
    (Join-Path $HOME '.config\dotfiles\git\config'),
    (Join-Path $HOME '.config\oh-my-posh\emodipt-extend.omp.json')
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
"Rollback preview: powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-Dotfiles.ps1 -RunPath '$run'"
"Rollback apply: powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-Dotfiles.ps1 -RunPath '$run' -Apply"
