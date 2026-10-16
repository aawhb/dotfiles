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
    'scripts\Update-WindowsTools.ps1',
    'scripts\WindowsToolDefinitions.ps1',
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
    'notepad-plus-plus',
    'lm-studio',
    'k-lite-codec-pack-mega',
    'windhawk',
    'powertoys',
    'zoom',
    'teams',
    'nanazip',
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
$windowsDefinitions = Get-Content -LiteralPath (
    Join-Path $root 'scripts\WindowsToolDefinitions.ps1') -Raw
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
    "'Notepad++.Notepad++'",
    "'ElementLabs.LMStudio'",
    "'CodecGuide.K-LiteCodecPack.Mega'",
    "'RamenSoftware.Windhawk'",
    "'Microsoft.PowerToys'",
    "'Zoom.Zoom.EXE'",
    "'Microsoft.Teams'",
    "'M2Team.NanaZip'",
    "'astral-sh.uv'",
    "'Microsoft.AzureCLI'",
    "'CoreyButler.NVMforWindows'",
    "'Herdr.Herdr.Preview'",
    "'GitHub.cli'",
    "'Bitwarden.CLI'",
    "'Tailscale.Tailscale'",
    'Get-WingetPackageStatus',
    'Test-WingetPackage'
)) {
    if (-not $windowsDefinitions.Contains($required)) {
        throw "Windows tool definitions are missing: $required"
    }
}
. (Join-Path $root 'scripts\WindowsToolDefinitions.ps1')
$installOrder = @(Get-WindowsToolInstallOrder -SelectedTools @(
    'codex', 'notepad-plus-plus', 'nvm-node-lts', 'codex'))
if (($installOrder -join ',') -ne 'powershell,nvm-node-lts,codex,notepad-plus-plus') {
    throw 'Windows installation order must keep prerequisites first and include every unique selection.'
}

$script:WingetInventoryTestMode = 'exact'
function winget {
    $global:LASTEXITCODE = 0
    $arguments = @($args)
    if ($script:WingetInventoryTestMode -eq 'error') {
        $global:LASTEXITCODE = 1
        Write-Output 'Winget inventory error'
        return
    }
    if ($script:WingetInventoryTestMode -eq 'unmatched' -and
        $arguments -contains 'user') {
        Write-Output 'Name Id Version Source'
        Write-Output 'Codex CLI OpenAI.CodexPreview 1.0 winget'
        return
    }
    if ($arguments -contains 'user') {
        Write-Output 'Name Id Version Source'
        Write-Output 'Codex CLI OpenAI.Codex 1.0 winget'
        return
    }
    Write-Output 'No installed package found matching input criteria.'
}
if (-not (Test-WingetPackage -Id 'OpenAI.Codex')) {
    throw 'Winget inventory must recognize an exact package row with single-space columns.'
}
$script:WingetInventoryTestMode = 'unmatched'
$unmatchedInventoryFailed = $false
try {
    [void](Test-WingetPackage -Id 'OpenAI.Codex')
} catch {
    $unmatchedInventoryFailed = $_.Exception.Message.Contains('unmatched')
}
if (-not $unmatchedInventoryFailed) {
    throw 'An unmatched Winget package row must fail verification.'
}
$script:WingetInventoryTestMode = 'error'
$errorInventoryFailed = $false
try {
    [void](Test-WingetPackage -Id 'OpenAI.Codex')
} catch {
    $errorInventoryFailed = $_.Exception.Message.Contains('error')
}
Remove-Item Function:\winget -ErrorAction SilentlyContinue
Remove-Variable WingetInventoryTestMode -Scope Script -ErrorAction SilentlyContinue
if (-not $errorInventoryFailed) {
    throw 'A Winget inventory error must fail verification.'
}
foreach ($required in @(
    'Get-WindowsToolDefinitions',
    'WindowsToolDefinitions.ps1',
    'nvm install lts',
    'Windows tool setup summary',
    "Status 'failed'",
    "Status 'skipped'"
)) {
    if (-not $windowsInstaller.Contains($required)) {
        throw "Windows installer is missing: $required"
    }
}
$windowsUpdater = Get-Content -LiteralPath (
    Join-Path $root 'scripts\Update-WindowsTools.ps1') -Raw
foreach ($required in @(
    '-Apply',
    'Get-SelectedWindowsTools',
    'Get-WingetUpdateCandidate',
    'winget upgrade --id',
    'npm install --global',
    'Node.js LTS version changes are deferred.'
)) {
    if (-not $windowsUpdater.Contains($required)) {
        throw "Windows tool updater is missing: $required"
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
    'scripts\Install-WindowsTools.ps1',
    'definitions-sha256:'
)) {
    if (-not (($renderedWrapper -join "`n").Contains($required))) {
        throw "Rendered Windows wrapper is missing: $required"
    }
}

$updateTemp = Join-Path ([IO.Path]::GetTempPath()) (
    'dotfiles-update-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $updateTemp | Out-Null
$oldPath = $env:Path
$oldLocalAppData = $env:LOCALAPPDATA
$oldDataPath = $env:DOTFILES_TEST_DATA
$oldUpgradeLog = $env:DOTFILES_TEST_UPGRADE_LOG
$oldInstalled = $env:DOTFILES_TEST_INSTALLED
$oldMachine = $env:DOTFILES_TEST_MACHINE
$oldAvailable = $env:DOTFILES_TEST_AVAILABLE
$oldNpmPrefix = $env:DOTFILES_TEST_NPM_PREFIX
$oldNpmRoot = $env:DOTFILES_TEST_NPM_ROOT
$oldNpmLog = $env:DOTFILES_TEST_NPM_LOG
$oldInstallLog = $env:DOTFILES_TEST_INSTALL_LOG
try {
    $dataPath = Join-Path $updateTemp 'data.json'
    $upgradeLog = Join-Path $updateTemp 'winget-upgrades.txt'
    $installLog = Join-Path $updateTemp 'winget-installs.txt'
    $npmLog = Join-Path $updateTemp 'npm-updates.txt'
    $fakeLocalAppData = Join-Path $updateTemp 'local-app-data'
    $wingetLinks = Join-Path $fakeLocalAppData 'Microsoft\WinGet\Links'
    $npmPrefix = Join-Path $updateTemp 'npm-global'
    $npmRoot = Join-Path $npmPrefix 'node_modules'
    $npmPackage = Join-Path $npmRoot '@openai\codex'
    New-Item -ItemType Directory -Path $wingetLinks, $npmPackage | Out-Null
    Set-Content -LiteralPath $dataPath -Value '{"windowsTools":["codex"]}' -NoNewline
    Set-Content -LiteralPath (Join-Path $wingetLinks 'codex.cmd') -Encoding Ascii -Value @(
        '@echo off',
        'echo codex 0.1.0',
        'exit /b 0'
    )
    Set-Content -LiteralPath (Join-Path $updateTemp 'chezmoi.cmd') -Encoding Ascii -Value @(
        '@echo off',
        'if not "%1"=="data" exit /b 1',
        'type "%DOTFILES_TEST_DATA%"',
        'exit /b 0'
    )
    Set-Content -LiteralPath (Join-Path $updateTemp 'winget.cmd') -Encoding Ascii -Value @(
        '@echo off',
        'if "%1"=="list" goto list',
        'if "%1"=="upgrade" goto upgrade',
        'if "%1"=="install" goto install',
        'exit /b 1',
        ':list',
        'echo %* | findstr /I /C:"--scope user" >nul',
        'if not errorlevel 1 goto user_scope',
        'echo %* | findstr /I /C:"--scope machine" >nul',
        'if not errorlevel 1 goto machine_scope',
        'goto missing',
        ':user_scope',
        'if not "%DOTFILES_TEST_INSTALLED%"=="true" goto missing',
        'echo %* | findstr /I /C:"--upgrade-available" >nul',
        'if not errorlevel 1 if "%DOTFILES_TEST_AVAILABLE%"=="false" goto current',
        'goto row',
        ':machine_scope',
        'if not "%DOTFILES_TEST_INSTALLED%"=="true" goto missing',
        'if not "%DOTFILES_TEST_MACHINE%"=="true" goto missing',
        'goto row',
        ':row',
        'echo Name                 Id                 Version  Available  Source',
        'echo Codex CLI OpenAI.Codex 0.1.0 0.2.0 winget',
        'exit /b 0',
        ':current',
        'echo Name                 Id                 Version  Available  Source',
        'exit /b 0',
        ':missing',
        'echo No installed package found.',
        'exit /b 0',
        ':upgrade',
        'echo %*>>"%DOTFILES_TEST_UPGRADE_LOG%"',
        'exit /b 0',
        ':install',
        'echo %*>>"%DOTFILES_TEST_INSTALL_LOG%"',
        'exit /b 0'
    )
    Set-Content -LiteralPath (Join-Path $updateTemp 'npm.cmd') -Encoding Ascii -Value @(
        '@echo off',
        'if "%1"=="prefix" echo %DOTFILES_TEST_NPM_PREFIX%',
        'if "%1"=="root" echo %DOTFILES_TEST_NPM_ROOT%',
        'if "%1"=="install" echo %*>>"%DOTFILES_TEST_NPM_LOG%"',
        'exit /b 0'
    )
    Set-Content -LiteralPath (Join-Path $npmPackage 'package.json') -Value '{"name":"@openai/codex"}'
    Copy-Item -LiteralPath (Join-Path $wingetLinks 'codex.cmd') `
        -Destination (Join-Path $npmPrefix 'codex.cmd')
    $env:DOTFILES_TEST_DATA = $dataPath
    $env:DOTFILES_TEST_UPGRADE_LOG = $upgradeLog
    $env:DOTFILES_TEST_INSTALL_LOG = $installLog
    $env:DOTFILES_TEST_NPM_LOG = $npmLog
    $env:DOTFILES_TEST_INSTALLED = 'true'
    $env:DOTFILES_TEST_MACHINE = 'false'
    $env:DOTFILES_TEST_AVAILABLE = 'true'
    $env:DOTFILES_TEST_NPM_PREFIX = $npmPrefix
    $env:DOTFILES_TEST_NPM_ROOT = $npmRoot
    $env:LOCALAPPDATA = $fakeLocalAppData
    $env:Path = "$updateTemp$([IO.Path]::PathSeparator)$wingetLinks$([IO.Path]::PathSeparator)$oldPath"
    if ((Get-Command chezmoi).Source -ne (Join-Path $updateTemp 'chezmoi.cmd') -or
        (Get-Command winget).Source -ne (Join-Path $updateTemp 'winget.cmd') -or
        (Get-Command codex).Source -ne (Join-Path $wingetLinks 'codex.cmd')) {
        throw 'Windows update test commands did not resolve to their isolated stubs.'
    }
    $updaterPath = Join-Path $root 'scripts\Update-WindowsTools.ps1'
    $previewOutput = & pwsh -NoLogo -NoProfile -File $updaterPath
    if ($LASTEXITCODE -ne 0 -or
        -not (($previewOutput -join "`n").Contains('Preview only')) -or
        (Test-Path -LiteralPath $upgradeLog)) {
        throw 'Windows tool update must preview selected installed packages without invoking Winget upgrade.'
    }

    $installerPath = Join-Path $root 'scripts\Install-WindowsTools.ps1'
    $bootstrapHarness = Join-Path $updateTemp 'bootstrap-test.ps1'
    Set-Content -LiteralPath $bootstrapHarness -Encoding UTF8 -Value @(
        'function global:winget {',
        '    $global:LASTEXITCODE = 0',
        '    if ($args -contains ''install'') {',
        '        Set-Content -LiteralPath $env:DOTFILES_TEST_INSTALL_LOG -Value ''called''',
        '        return',
        '    }',
        '    if ($args -contains ''user'') {',
        '        Write-Output ''Name Id Version Source''',
        '        Write-Output ''Obsidian Obsidian.Other 1.0 winget''',
        '    } else {',
        '        Write-Output ''No installed package found matching input criteria.''',
        '    }',
        '}',
        "& '$($installerPath.Replace("'", "''"))' -Tools obsidian -SkipProfile"
    )
    $bootstrapOutput = & pwsh -NoLogo -NoProfile -File $bootstrapHarness 2>&1
    if (-not (($bootstrapOutput -join "`n").Contains('unmatched')) -or
        -not (($bootstrapOutput -join "`n").Contains('Obsidian failed')) -or
        (Test-Path -LiteralPath $installLog)) {
        throw "Bootstrap must report an unmatched Winget inventory per tool without claiming success or reinstalling. Output: $($bootstrapOutput -join ' | ')"
    }

    $env:DOTFILES_TEST_INSTALLED = 'false'
    $env:DOTFILES_TEST_DATA = $dataPath
    $missingOutput = & pwsh -NoLogo -NoProfile -File $updaterPath -Apply
    if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $upgradeLog) -or
        -not (($missingOutput -join "`n").Contains('skipped'))) {
        throw 'Windows tool update must skip missing packages instead of installing them.'
    }

    $env:DOTFILES_TEST_INSTALLED = 'true'
    $env:DOTFILES_TEST_MACHINE = 'true'
    $ambiguousOutput = & pwsh -NoLogo -NoProfile -File $updaterPath -Apply
    if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $upgradeLog) -or
        -not (($ambiguousOutput -join "`n").Contains('both scopes'))) {
        throw 'Windows tool update must skip packages installed in both scopes.'
    }

    $env:DOTFILES_TEST_MACHINE = 'false'
    $env:DOTFILES_TEST_AVAILABLE = 'false'
    $currentOutput = & pwsh -NoLogo -NoProfile -File $updaterPath -Apply
    if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $upgradeLog) -or
        -not (($currentOutput -join "`n").Contains('no applicable update'))) {
        throw 'Windows tool update must treat an installed current package as a no-op.'
    }

    $env:DOTFILES_TEST_AVAILABLE = 'true'
    $applyOutput = & pwsh -NoLogo -NoProfile -File $updaterPath -Apply
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $upgradeLog) -or
        -not (Get-Content -LiteralPath $upgradeLog -Raw).Contains(
            'upgrade --id OpenAI.Codex --exact --scope user --source winget')) {
        throw 'Windows tool update must upgrade an installed selected package only after -Apply.'
    }

    Remove-Item -LiteralPath $upgradeLog
    $env:Path = "$npmPrefix$([IO.Path]::PathSeparator)$updateTemp$([IO.Path]::PathSeparator)$wingetLinks$([IO.Path]::PathSeparator)$oldPath"
    if ((Get-Command npm).Source -ne (Join-Path $updateTemp 'npm.cmd') -or
        (Get-Command codex).Source -ne (Join-Path $npmPrefix 'codex.cmd')) {
        throw 'Windows npm test commands did not resolve to their isolated stubs.'
    }
    $npmPreview = & pwsh -NoLogo -NoProfile -File $updaterPath
    if ($LASTEXITCODE -ne 0 -or -not (($npmPreview -join "`n").Contains('npm')) -or
        (Test-Path -LiteralPath $upgradeLog) -or (Test-Path -LiteralPath $npmLog)) {
        throw 'Windows tool update must preview the active global npm Codex installation.'
    }
    $npmApply = & pwsh -NoLogo -NoProfile -File $updaterPath -Apply
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $npmLog) -or
        -not (Get-Content -LiteralPath $npmLog -Raw).Contains(
            'install --global @openai/codex') -or (Test-Path -LiteralPath $upgradeLog)) {
        throw 'Windows tool update must update active npm Codex without upgrading the inactive Winget package.'
    }
} finally {
    $env:Path = $oldPath
    if ($null -eq $oldLocalAppData) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
    else { $env:LOCALAPPDATA = $oldLocalAppData }
    if ($null -eq $oldDataPath) { Remove-Item Env:DOTFILES_TEST_DATA -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_DATA = $oldDataPath }
    if ($null -eq $oldUpgradeLog) { Remove-Item Env:DOTFILES_TEST_UPGRADE_LOG -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_UPGRADE_LOG = $oldUpgradeLog }
    if ($null -eq $oldInstalled) { Remove-Item Env:DOTFILES_TEST_INSTALLED -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_INSTALLED = $oldInstalled }
    if ($null -eq $oldMachine) { Remove-Item Env:DOTFILES_TEST_MACHINE -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_MACHINE = $oldMachine }
    if ($null -eq $oldAvailable) { Remove-Item Env:DOTFILES_TEST_AVAILABLE -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_AVAILABLE = $oldAvailable }
    if ($null -eq $oldNpmPrefix) { Remove-Item Env:DOTFILES_TEST_NPM_PREFIX -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_NPM_PREFIX = $oldNpmPrefix }
    if ($null -eq $oldNpmRoot) { Remove-Item Env:DOTFILES_TEST_NPM_ROOT -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_NPM_ROOT = $oldNpmRoot }
    if ($null -eq $oldNpmLog) { Remove-Item Env:DOTFILES_TEST_NPM_LOG -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_NPM_LOG = $oldNpmLog }
    if ($null -eq $oldInstallLog) { Remove-Item Env:DOTFILES_TEST_INSTALL_LOG -ErrorAction SilentlyContinue }
    else { $env:DOTFILES_TEST_INSTALL_LOG = $oldInstallLog }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $updateTempFullPath = [IO.Path]::GetFullPath($updateTemp)
    $tempRootFullPath = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    $tempParent = [IO.Path]::GetDirectoryName($updateTempFullPath)
    $tempLeaf = [IO.Path]::GetFileName($updateTempFullPath)
    if (-not $tempParent.Equals($tempRootFullPath, [StringComparison]::OrdinalIgnoreCase) -or
        $tempLeaf -notmatch '^dotfiles-update-test-[0-9a-f]{32}$') {
        throw 'Test temporary directory is not the expected GUID directory directly under the system temporary directory.'
    }
    Remove-Item -LiteralPath $updateTempFullPath -Recurse -Force
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
    'linux_tools_install_selected blesh atuin oh-my-posh zoxide just herdr bitwarden-cli tailscale',
    '[atuin]=18.19.0',
    '[oh-my-posh]=30.6.5',
    '[zoxide]=0.10.0',
    '[just]=1.58.0',
    '[herdr]=0.9.1',
    '[bitwarden-cli]=2026.7.0',
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
