[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RunPath,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$run = (Resolve-Path -LiteralPath $RunPath).Path
$manifestPath = Join-Path $run 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Backup manifest does not exist: $manifestPath"
}
$homeRoot = [IO.Path]::GetFullPath($HOME).TrimEnd('\') + '\'
$manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

'Dotfiles restore preview:'
foreach ($item in $manifest) {
    $target = [IO.Path]::GetFullPath([string]$item.Target)
    if (-not $target.StartsWith($homeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Restore target is outside the home directory: $target"
    }
    $action = if ($item.Existed) { 'restore' } else { 'remove newly managed file' }
    "  ${action}: $target"
}
if (-not $Apply) {
    'Preview only. Re-run with -Apply.'
    return
}

foreach ($item in $manifest) {
    $target = [IO.Path]::GetFullPath([string]$item.Target)
    if ($item.Existed) {
        $source = [IO.Path]::GetFullPath((Join-Path $run ([string]$item.Backup)))
        $allowed = [IO.Path]::GetFullPath((Join-Path $run 'backup')).TrimEnd('\') + '\'
        if (-not $source.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Invalid backup source: $source"
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}
'Dotfiles targets restored. Tool binaries and application state were preserved.'

