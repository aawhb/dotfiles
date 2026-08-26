[CmdletBinding()]
param(
    [string]$Tools = '',
    [string]$InitialResultsPath = '',
    [switch]$SkipProfile
)

$ErrorActionPreference = 'Stop'

function New-InstallResult {
    param(
        [string]$Tool,
        [string]$Status,
        [string]$Detail
    )

    [pscustomobject]@{
        Tool = $Tool
        Status = $Status
        Detail = $Detail
    }
}

function Refresh-ProcessEnvironment {
    $pathEntries = New-Object System.Collections.Generic.List[string]
    foreach ($scope in @('Machine', 'User')) {
        $value = [Environment]::GetEnvironmentVariable('Path', $scope)
        foreach ($entry in @($value -split [IO.Path]::PathSeparator)) {
            if (-not [string]::IsNullOrWhiteSpace($entry) -and
                -not ($pathEntries | Where-Object {
                    $_.Equals($entry, [StringComparison]::OrdinalIgnoreCase)
                })) {
                $pathEntries.Add($entry)
            }
        }
    }
    foreach ($entry in @($env:Path -split [IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrWhiteSpace($entry) -and
            -not ($pathEntries | Where-Object {
                $_.Equals($entry, [StringComparison]::OrdinalIgnoreCase)
            })) {
            $pathEntries.Add($entry)
        }
    }
    $env:Path = $pathEntries -join [IO.Path]::PathSeparator

    foreach ($name in @('NVM_HOME', 'NVM_SYMLINK')) {
        $value = [Environment]::GetEnvironmentVariable($name, 'User')
        if (-not $value) {
            $value = [Environment]::GetEnvironmentVariable($name, 'Machine')
        }
        if ($value) {
            Set-Item -LiteralPath "Env:$name" -Value $value
        }
    }
}

function Add-UserPathEntry {
    param([string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($current -split [IO.Path]::PathSeparator) | Where-Object { $_ }
    if ($entries | Where-Object {
        $_.TrimEnd('\').Equals(
            $Directory.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
    }) {
        return
    }
    $newValue = (@($entries) + $Directory) -join [IO.Path]::PathSeparator
    [Environment]::SetEnvironmentVariable('Path', $newValue, 'User')
    Refresh-ProcessEnvironment
}

function Get-PathCandidates {
    param(
        [string]$Command,
        [string]$PackagePrefix
    )

    $fileNames = @("$Command.exe", "$Command.cmd", "$Command.ps1")
    $directories = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
    )

    switch ($Command) {
        'pwsh' {
            $directories += Join-Path $env:ProgramFiles 'PowerShell\7'
        }
        'code' {
            $directories += Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin'
            $directories += Join-Path $env:ProgramFiles 'Microsoft VS Code\bin'
        }
        'az' {
            $directories += Join-Path $env:ProgramFiles 'Microsoft SDKs\Azure\CLI2\wbin'
        }
        'nvm' {
            if ($env:NVM_HOME) {
                $directories += $env:NVM_HOME
            }
            $directories += Join-Path $env:LOCALAPPDATA 'nvm'
        }
        { $_ -in @('node', 'npm', 'codex') } {
            if ($env:NVM_SYMLINK) {
                $directories += $env:NVM_SYMLINK
            }
            $directories += Join-Path $env:ProgramFiles 'nodejs'
            if ($_ -in @('npm', 'codex')) {
                $directories += Join-Path $env:APPDATA 'npm'
            }
        }
    }

    foreach ($directory in $directories | Select-Object -Unique) {
        foreach ($fileName in $fileNames) {
            $candidate = Join-Path $directory $fileName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $candidate
            }
        }
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if ($PackagePrefix -and (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        foreach ($directory in Get-ChildItem -LiteralPath $packageRoot -Directory -Filter "$PackagePrefix*") {
            foreach ($fileName in $fileNames) {
                Get-ChildItem -LiteralPath $directory.FullName -Recurse -File -Filter $fileName |
                    Select-Object -ExpandProperty FullName
            }
        }
    }
}

function Repair-CommandPath {
    param(
        [string]$Command,
        [string]$PackagePrefix
    )

    Refresh-ProcessEnvironment
    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        return
    }
    $candidate = Get-PathCandidates -Command $Command -PackagePrefix $PackagePrefix |
        Select-Object -First 1
    if ($candidate) {
        Add-UserPathEntry -Directory (Split-Path -Parent $candidate)
    }
}

function Invoke-CommandCheck {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $global:LASTEXITCODE = 0
        & $Command @Arguments *> $null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    } catch {
        return $false
    }

    $shell = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $shell) {
        $shell = Get-Command powershell -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $shell) {
        return $false
    }
    $argumentText = @($Arguments | ForEach-Object {
        "'" + $_.Replace("'", "''") + "'"
    }) -join ' '
    $check = "& '$Command' $argumentText *> `$null; if (`$LASTEXITCODE -ne 0) { exit 1 }"
    try {
        $global:LASTEXITCODE = 0
        & $shell.Source -NoLogo -NoProfile -Command $check *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-PowerShell7 {
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $edition = & pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSEdition'
        $major = & pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major'
        return $LASTEXITCODE -eq 0 -and $edition -eq 'Core' -and [int]$major -ge 7
    } catch {
        return $false
    }
}

function Test-WingetPackage {
    param([string]$Id)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return $false
    }
    $global:LASTEXITCODE = 0
    & winget list --id $Id --exact --source winget --accept-source-agreements *> $null
    return $LASTEXITCODE -eq 0
}

function Install-WingetPackage {
    param([string]$Id)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Winget is not available.'
    }
    & winget install --id $Id --exact --source winget `
        --accept-package-agreements --accept-source-agreements `
        --disable-interactivity | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Winget exited with code $LASTEXITCODE."
    }
}

$definitions = @{
    'powershell' = @{
        Label = 'PowerShell 7'; Id = 'Microsoft.PowerShell'; Command = 'pwsh'
        Arguments = @('-NoLogo', '-NoProfile', '-Command', '$PSVersionTable.PSEdition')
        Prefix = 'Microsoft.PowerShell_'
    }
    'oh-my-posh' = @{
        Label = 'Oh My Posh'; Id = 'JanDeDobbeleer.OhMyPosh'; Command = 'oh-my-posh'
        Arguments = @('version'); Prefix = 'JanDeDobbeleer.OhMyPosh_'
    }
    'atuin' = @{
        Label = 'Atuin'; Id = 'Atuinsh.Atuin'; Command = 'atuin'
        Arguments = @('--version'); Prefix = 'Atuinsh.Atuin_'
    }
    'zoxide' = @{
        Label = 'zoxide'; Id = 'ajeetdsouza.zoxide'; Command = 'zoxide'
        Arguments = @('--version'); Prefix = 'ajeetdsouza.zoxide_'
    }
    'just' = @{
        Label = 'just'; Id = 'Casey.Just'; Command = 'just'
        Arguments = @('--version'); Prefix = 'Casey.Just_'
    }
    'fzf' = @{
        Label = 'fzf'; Id = 'junegunn.fzf'; Command = 'fzf'
        Arguments = @('--version'); Prefix = 'junegunn.fzf_'
    }
    'vscode' = @{
        Label = 'Visual Studio Code'; Id = 'Microsoft.VisualStudioCode'; Command = 'code'
        Arguments = @('--version'); Prefix = 'Microsoft.VisualStudioCode_'
    }
    'codex' = @{
        Label = 'Codex CLI'; Id = 'OpenAI.Codex'; Command = 'codex'
        Arguments = @('--version'); Prefix = 'OpenAI.Codex_'
    }
    'obsidian' = @{
        Label = 'Obsidian'; Id = 'Obsidian.Obsidian'; Command = ''
        Arguments = @(); Prefix = 'Obsidian.Obsidian_'
    }
    'uv' = @{
        Label = 'uv'; Id = 'astral-sh.uv'; Command = 'uv'
        Arguments = @('--version'); Prefix = 'astral-sh.uv_'
    }
    'azure-cli' = @{
        Label = 'Azure CLI'; Id = 'Microsoft.AzureCLI'; Command = 'az'
        Arguments = @('version', '--output', 'json'); Prefix = 'Microsoft.AzureCLI_'
    }
    'nvm-node-lts' = @{
        Label = 'NVM and Node.js LTS'; Id = 'CoreyButler.NVMforWindows'; Command = 'nvm'
        Arguments = @('version'); Prefix = 'CoreyButler.NVMforWindows_'
    }
}

function Test-Tool {
    param([string]$Key)

    if ($Key -eq 'powershell') {
        return Test-PowerShell7
    }
    if ($Key -eq 'obsidian') {
        return Test-WingetPackage -Id $definitions[$Key].Id
    }
    if ($Key -eq 'nvm-node-lts') {
        return (Invoke-CommandCheck -Command 'nvm' -Arguments @('version')) -and
            (Invoke-CommandCheck -Command 'node' -Arguments @('--version')) -and
            (Invoke-CommandCheck -Command 'npm' -Arguments @('--version'))
    }
    $definition = $definitions[$Key]
    return Invoke-CommandCheck -Command $definition.Command -Arguments $definition.Arguments
}

function Install-GenericTool {
    param([string]$Key)

    $definition = $definitions[$Key]
    if (Test-Tool -Key $Key) {
        return New-InstallResult -Tool $definition.Label -Status 'available' `
            -Detail 'Verification succeeded; no installation needed.'
    }
    try {
        Install-WingetPackage -Id $definition.Id
        Refresh-ProcessEnvironment
        if ($definition.Command) {
            Repair-CommandPath -Command $definition.Command -PackagePrefix $definition.Prefix
        }
        if (-not (Test-Tool -Key $Key)) {
            throw 'Installation completed but verification failed in a fresh PowerShell process.'
        }
        return New-InstallResult -Tool $definition.Label -Status 'installed' `
            -Detail 'Installed with Winget and verified.'
    } catch {
        return New-InstallResult -Tool $definition.Label -Status 'failed' -Detail $_.Exception.Message
    }
}

function Install-NvmNodeLts {
    $definition = $definitions['nvm-node-lts']
    if (Test-Tool -Key 'nvm-node-lts') {
        return New-InstallResult -Tool $definition.Label -Status 'available' `
            -Detail 'NVM, Node.js, and npm verification succeeded.'
    }
    try {
        if (-not (Invoke-CommandCheck -Command 'nvm' -Arguments @('version'))) {
            Install-WingetPackage -Id $definition.Id
            Refresh-ProcessEnvironment
            Repair-CommandPath -Command 'nvm' -PackagePrefix $definition.Prefix
        }
        if (-not (Invoke-CommandCheck -Command 'nvm' -Arguments @('version'))) {
            throw 'NVM is unavailable after Winget installation.'
        }
        & nvm install lts | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "nvm install lts exited with code $LASTEXITCODE."
        }
        & nvm use lts | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "nvm use lts exited with code $LASTEXITCODE."
        }
        Refresh-ProcessEnvironment
        Repair-CommandPath -Command 'node' -PackagePrefix ''
        Repair-CommandPath -Command 'npm' -PackagePrefix ''
        if (-not (Test-Tool -Key 'nvm-node-lts')) {
            throw 'NVM installed, but Node.js or npm verification failed.'
        }
        return New-InstallResult -Tool $definition.Label -Status 'installed' `
            -Detail 'Installed NVM with Winget and activated Node.js LTS.'
    } catch {
        return New-InstallResult -Tool $definition.Label -Status 'failed' -Detail $_.Exception.Message
    }
}

function Install-Codex {
    $definition = $definitions['codex']
    if (Test-Tool -Key 'codex') {
        return New-InstallResult -Tool $definition.Label -Status 'available' `
            -Detail 'Verification succeeded; no installation needed.'
    }

    $wingetFailure = ''
    try {
        Install-WingetPackage -Id $definition.Id
        Refresh-ProcessEnvironment
        Repair-CommandPath -Command 'codex' -PackagePrefix $definition.Prefix
        if (Test-Tool -Key 'codex') {
            return New-InstallResult -Tool $definition.Label -Status 'installed' `
                -Detail 'Installed with Winget and verified.'
        }
        $wingetFailure = 'Winget completed but Codex verification failed.'
    } catch {
        $wingetFailure = $_.Exception.Message
    }

    if (Invoke-CommandCheck -Command 'npm' -Arguments @('--version')) {
        try {
            & npm install --global '@openai/codex' | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "npm exited with code $LASTEXITCODE."
            }
            Refresh-ProcessEnvironment
            Repair-CommandPath -Command 'codex' -PackagePrefix ''
            if (-not (Test-Tool -Key 'codex')) {
                throw 'npm completed but Codex verification failed.'
            }
            return New-InstallResult -Tool $definition.Label -Status 'installed' `
                -Detail 'Winget failed; installed with the npm fallback and verified.'
        } catch {
            return New-InstallResult -Tool $definition.Label -Status 'failed' `
                -Detail "$wingetFailure npm fallback: $($_.Exception.Message)"
        }
    }
    return New-InstallResult -Tool $definition.Label -Status 'failed' `
        -Detail "$wingetFailure npm fallback was unavailable because npm is not installed."
}

function Install-PowerShellLoader {
    if (-not (Test-PowerShell7)) {
        return New-InstallResult -Tool 'PowerShell 7 profile' -Status 'skipped' `
            -Detail 'PowerShell 7 is unavailable; the Windows PowerShell 5 profile was not changed.'
    }
    try {
        $targetProfile = (& pwsh -NoLogo -NoProfile -Command '$PROFILE.CurrentUserCurrentHost' |
            Select-Object -First 1).Trim()
        if (-not $targetProfile) {
            throw 'PowerShell 7 did not return a profile path.'
        }
        $managedProfile = Join-Path $HOME '.config\dotfiles\powershell\profile.ps1'
        $loader = @'
# BEGIN dotfiles loader
$managedProfile = Join-Path $HOME '.config\dotfiles\powershell\profile.ps1'
if (Test-Path -LiteralPath $managedProfile -PathType Leaf) {
    . $managedProfile
}
# END dotfiles loader
'@
        $current = if (Test-Path -LiteralPath $targetProfile -PathType Leaf) {
            Get-Content -LiteralPath $targetProfile -Raw
        } else {
            ''
        }
        if ($current -ceq $loader) {
            return New-InstallResult -Tool 'PowerShell 7 profile' -Status 'available' `
                -Detail $targetProfile
        }
        if ($current) {
            $backupRoot = Join-Path $HOME '.local\state\dotfiles\backups'
            $backup = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            Copy-Item -LiteralPath $targetProfile -Destination $backup
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetProfile) -Force |
            Out-Null
        Set-Content -LiteralPath $targetProfile -Value $loader -NoNewline -Encoding UTF8
        return New-InstallResult -Tool 'PowerShell 7 profile' -Status 'installed' `
            -Detail $targetProfile
    } catch {
        return New-InstallResult -Tool 'PowerShell 7 profile' -Status 'failed' `
            -Detail $_.Exception.Message
    }
}

Refresh-ProcessEnvironment
$selectedTools = @($Tools -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$results = @()
if ($InitialResultsPath) {
    $results += @(Get-Content -LiteralPath $InitialResultsPath -Raw | ConvertFrom-Json)
}

foreach ($unknown in @($selectedTools | Where-Object { -not $definitions.ContainsKey($_) })) {
    $results += New-InstallResult -Tool $unknown -Status 'failed' `
        -Detail 'Unknown tool selection in the Chezmoi configuration.'
}
$selectedTools = @($selectedTools | Where-Object { $definitions.ContainsKey($_) } |
    Select-Object -Unique)

if ($PSVersionTable.PSEdition -ne 'Core' -and 'powershell' -in $selectedTools) {
    $powerShellResult = Install-GenericTool -Key 'powershell'
    $results += $powerShellResult
    $selectedTools = @($selectedTools | Where-Object { $_ -ne 'powershell' })
    if ($powerShellResult.Status -ne 'failed' -and (Test-PowerShell7)) {
        $statePath = Join-Path ([IO.Path]::GetTempPath()) (
            'dotfiles-bootstrap-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
            & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
                -Tools ($selectedTools -join ',') -InitialResultsPath $statePath `
                -SkipProfile:$SkipProfile
            exit $LASTEXITCODE
        } finally {
            if (Test-Path -LiteralPath $statePath -PathType Leaf) {
                Remove-Item -LiteralPath $statePath -Force
            }
        }
    }
}

$installOrder = @(
    'powershell', 'nvm-node-lts', 'oh-my-posh', 'atuin', 'zoxide', 'just',
    'fzf', 'vscode', 'obsidian', 'uv', 'azure-cli', 'codex'
)
foreach ($key in $installOrder) {
    if ($key -notin $selectedTools) {
        continue
    }
    if ($key -eq 'nvm-node-lts') {
        $results += Install-NvmNodeLts
    } elseif ($key -eq 'codex') {
        $results += Install-Codex
    } else {
        $results += Install-GenericTool -Key $key
    }
}

if (-not $SkipProfile) {
    $results += Install-PowerShellLoader
}

''
'Windows tool setup summary:'
$results | Format-Table -AutoSize Tool, Status, Detail

$failures = @($results | Where-Object { $_.Status -eq 'failed' })
if ($failures.Count) {
    [Console]::Error.WriteLine(
        "$($failures.Count) selected tool or configuration step(s) failed.")
    exit 1
}
exit 0
