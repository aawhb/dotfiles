$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$forbidden = @(
    ('e-' + 'xist'),
    ('tail' + '0058b1'),
    ('dev-' + '01'),
    ('vault-' + '01'),
    ('BEGIN OPENSSH ' + 'PRIVATE KEY'),
    ('BW_' + 'SESSION='),
    ('ATUIN_' + 'SESSION')
)
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]'
}
foreach ($file in $files) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($value in $forbidden) {
        if ($content.Contains($value, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Public source contains forbidden private text '$value' in $($file.FullName)."
        }
    }
    if ($content.Contains([char]0x2014)) {
        throw "File contains an em dash: $($file.FullName)"
    }
}

$powerShellFiles = Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' -Force
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        throw "PowerShell parse errors in $($file.FullName): $($errors.Message -join ', ')"
    }
}

foreach ($required in @(
    'scripts\Backup-Dotfiles.ps1',
    'scripts\Restore-Dotfiles.ps1',
    'scripts\backup-dotfiles.sh',
    'scripts\restore-dotfiles.sh'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
        throw "Recovery helper is missing: $required"
    }
}

$profile = Get-Content -LiteralPath (
    Join-Path $root 'dot_config\dotfiles\powershell\profile.ps1') -Raw
foreach ($required in @(
    'PredictionSource History',
    'PredictionViewStyle InlineView',
    'oh-my-posh init pwsh',
    'zoxide init powershell',
    'atuin init powershell --disable-up-arrow --disable-ai'
)) {
    if (-not $profile.Contains($required)) {
        throw "PowerShell profile is missing: $required"
    }
}

$sshConfig = Get-Content -LiteralPath (
    Join-Path $root 'private_dot_ssh\modify_private_config') -Raw
if ($sshConfig -notmatch '(?m)^# BEGIN dotfiles includes\r?\nHost \*\r?\nInclude ') {
    throw 'The SSH include block must reset Host context before loading fragments.'
}

'Public dotfiles tests passed.'
