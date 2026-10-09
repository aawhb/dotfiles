$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$forbidden = @(
    ('e-' + 'xist'),
    ('tail' + '0058b1'),
    ('dev-' + '01'),
    ('vault-' + '01'),
    ('platform-' + 'ops'),
    ('install' + 'ShellTools'),
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
    'scripts\Install-WindowsTools.ps1',
    'scripts\backup-dotfiles.sh',
    'scripts\restore-dotfiles.sh'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
        throw "Recovery helper is missing: $required"
    }
}
$configTemplate = Get-Content -LiteralPath (Join-Path $root '.chezmoi.toml.tmpl') -Raw
foreach ($required in @(
    'promptMultichoiceOnce',
    'windowsTools',
    'linuxTools',
    'nvm-node-lts',
    'herdr',
    'github-cli',
    'bitwarden-cli',
    'tailscale'
)) {
    if (-not $configTemplate.Contains($required)) {
        throw "Chezmoi config template is missing: $required"
    }
}
if (-not $configTemplate.Contains('$windowsChoices (list "powershell")')) {
    throw 'Windows optional tools must remain unselected by default.'
}
if (-not $configTemplate.Contains(
    '$linuxDefaults := list "blesh" "atuin" "oh-my-posh" "zoxide" "just"')) {
    throw 'Linux optional tools must remain unselected by default.'
}

$windowsInstaller = Get-Content -LiteralPath (
    Join-Path $root 'scripts\Install-WindowsTools.ps1') -Raw
foreach ($required in @(
    "'Microsoft.PowerShell'",
    "'JanDeDobbeleer.OhMyPosh'",
    "'Atuinsh.Atuin'",
    "'ajeetdsouza.zoxide'",
    "'Casey.Just'",
    "'junegunn.fzf'",
    "'Microsoft.VisualStudioCode'",
    "'OpenAI.Codex'",
    "'Obsidian.Obsidian'",
    "'astral-sh.uv'",
    "'Microsoft.AzureCLI'",
    "'CoreyButler.NVMforWindows'",
    "'Herdr.Herdr.Preview'",
    "'GitHub.cli'",
    "'Bitwarden.CLI'",
    "'Tailscale.Tailscale'",
    'nvm install lts',
    'npm install --global',
    'Windows tool setup summary',
    "Status 'failed'",
    "Status 'skipped'"
)) {
    if (-not $windowsInstaller.Contains($required)) {
        throw "Windows installer is missing: $required"
    }
}
if ($windowsInstaller.Contains('Set-ExecutionPolicy')) {
    throw 'Windows installer must not change a persistent execution policy.'
}
if ($windowsInstaller.Contains('--scope user')) {
    throw 'Windows installer must let Winget choose the applicable scope.'
}
if ($windowsInstaller.Contains(".local\state\dotfiles\backups")) {
    throw 'The Windows installer must not accumulate profile-loader backups.'
}

$installerAst = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'scripts\Install-WindowsTools.ps1'), [ref]$tokens, [ref]$errors)
$mergeFunctionAst = $installerAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Merge-PowerShellProfileLoader'
}, $true)
if (-not $mergeFunctionAst) {
    throw 'The Windows installer is missing its profile loader merge function.'
}
. ([scriptblock]::Create($mergeFunctionAst.Extent.Text))

$testLoader = @(
    '# BEGIN dotfiles loader',
    '$managedProfile = "managed profile"',
    '# END dotfiles loader'
) -join "`n"
$expectedTestLoader = $testLoader -replace "`r`n|`n|`r", "`r`n"
$profileBefore = "Personal setup before`r`n"
$profileAfter = "`r`nPersonal setup after`r`n"
$profileWithLoader = $profileBefore +
    "# BEGIN dotfiles loader`r`nOld loader`r`n# END dotfiles loader" +
    $profileAfter
$mergedProfile = Merge-PowerShellProfileLoader `
    -CurrentProfile $profileWithLoader -Loader $testLoader
$expectedProfile = $profileBefore + $expectedTestLoader + $profileAfter
if ($mergedProfile -cne $expectedProfile) {
    throw 'Updating the PowerShell loader did not preserve surrounding profile text.'
}
$appendedProfile = Merge-PowerShellProfileLoader `
    -CurrentProfile "Personal setup before`r`n" -Loader $testLoader
if ($appendedProfile -cne "Personal setup before`r`n$expectedTestLoader") {
    throw 'The PowerShell loader was not appended after existing profile text.'
}
if ((Merge-PowerShellProfileLoader -CurrentProfile $appendedProfile `
        -Loader $testLoader) -cne $appendedProfile) {
    throw 'The PowerShell loader merge is not idempotent.'
}
foreach ($malformedProfile in @(
    "# BEGIN dotfiles loader`nUnpaired marker",
    "# END dotfiles loader`nUnpaired marker",
    "# END dotfiles loader`n# BEGIN dotfiles loader",
    "# BEGIN dotfiles loader`n# BEGIN dotfiles loader`n# END dotfiles loader"
)) {
    $rejectedMalformedProfile = $false
    try {
        [void](Merge-PowerShellProfileLoader `
            -CurrentProfile $malformedProfile -Loader $testLoader)
    } catch {
        $rejectedMalformedProfile = $true
    }
    if (-not $rejectedMalformedProfile) {
        throw 'Malformed PowerShell loader markers must fail without replacing the profile.'
    }
}

$wrapperPath = Join-Path $root 'run_onchange_after_10-install-windows-tools.cmd.tmpl'
$renderedWrapper = & chezmoi execute-template --source $root `
    --config (Join-Path $root 'tests\fixtures\windows.toml') `
    --file $wrapperPath
if ($LASTEXITCODE -ne 0) {
    throw 'Could not render the Windows installer wrapper.'
}
foreach ($required in @(
    '-ExecutionPolicy Bypass',
    'powershell,atuin,codex,nvm-node-lts,herdr,github-cli,bitwarden-cli,tailscale',
    'scripts\Install-WindowsTools.ps1'
)) {
    if (-not (($renderedWrapper -join "`n").Contains($required))) {
        throw "Rendered Windows wrapper is missing: $required"
    }
}

$linuxTemplatePath = Join-Path $root 'run_onchange_after_10-install-linux-tools.sh.tmpl'
$linuxTemplate = (Get-Content -LiteralPath $linuxTemplatePath -Raw).Replace(
    'eq .chezmoi.os "linux"', 'eq .chezmoi.os "windows"')
$renderedLinux = $linuxTemplate | & chezmoi execute-template --source $root `
    --config (Join-Path $root 'tests\fixtures\linux.toml')
if ($LASTEXITCODE -ne 0) {
    throw 'Could not render the Linux installer template.'
}
$renderedLinuxText = $renderedLinux -join "`n"
if (-not $renderedLinuxText.StartsWith('#!/usr/bin/env bash')) {
    throw 'Rendered Linux installer must start with its shebang.'
}
foreach ($required in @(
    'install_blesh',
    'install_archive_binary atuin',
    'install_file_binary oh-my-posh',
    'install_archive_binary zoxide',
    'install_archive_binary just',
    'install_file_binary herdr 0.9.1',
    'install_zip_binary bitwarden-cli 2026.7.0',
    'install_tailscale',
    'https://tailscale.com/install.sh',
    'Linux tool setup summary'
)) {
    if (-not $renderedLinuxText.Contains($required)) {
        throw "Rendered Linux installer is missing: $required"
    }
}
if ($renderedLinuxText -match '(?m)^[\t ]*(sudo[\t ]+)?tailscale[\t ]+up') {
    throw 'Linux tool installer must not enroll Tailscale automatically.'
}

$backupScript = Get-Content -LiteralPath (
    Join-Path $root 'scripts\Backup-Dotfiles.ps1') -Raw
if (-not $backupScript.Contains("PowerShell\Microsoft.PowerShell_profile.ps1")) {
    throw 'Windows backup must target the PowerShell 7 profile path.'
}
if ($backupScript.Contains('WindowsPowerShell')) {
    throw 'Windows backup must not target the Windows PowerShell 5 profile.'
}
foreach ($privateTarget in @(
    'permissions.ai.toml',
    '.config\herdr',
    '.codex\AGENTS.md',
    '.codex\config.toml',
    'Connect-AawhbAtuin.ps1',
    'herdr.cmd'
)) {
    if ($backupScript.Contains($privateTarget)) {
        throw "Public Windows backup contains a private target: $privateTarget"
    }
}

$bashBackup = Get-Content -LiteralPath (
    Join-Path $root 'scripts\backup-dotfiles.sh') -Raw
foreach ($privateTarget in @(
    'permissions.ai.toml',
    '.config/herdr',
    '.codex/AGENTS.md',
    '.codex/config.toml',
    'connect-aawhb-atuin'
)) {
    if ($bashBackup.Contains($privateTarget)) {
        throw "Public Bash backup contains a private target: $privateTarget"
    }
}

$workflow = Get-Content -LiteralPath (
    Join-Path $root '.github\workflows\ci.yml') -Raw
foreach ($required in @(
    'https://get.chezmoi.io/ps1',
    '.chezmoiversion',
    'GITHUB_PATH'
)) {
    if (-not $workflow.Contains($required)) {
        throw "Windows CI does not provision chezmoi correctly: $required"
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
