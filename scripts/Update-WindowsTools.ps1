[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WindowsToolDefinitions.ps1')
$definitions = Get-WindowsToolDefinitions

function Get-SelectedWindowsTools {
    $chezmoi = Get-Command chezmoi -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $chezmoi) {
        throw 'chezmoi is required to read the selected Windows tools.'
    }

    $dataJson = & $chezmoi.Source data --format=json
    if ($LASTEXITCODE -ne 0) {
        throw "chezmoi data exited with code $LASTEXITCODE."
    }
    $data = ($dataJson -join "`n") | ConvertFrom-Json
    if (-not $data.PSObject.Properties['windowsTools']) {
        throw 'chezmoi data does not contain windowsTools.'
    }

    $selected = @($data.windowsTools | ForEach-Object { [string]$_ } |
        Where-Object { $_ })
    foreach ($key in $selected) {
        if (-not $definitions.ContainsKey($key)) {
            throw "Selected Windows tool '$key' has no update definition."
        }
    }
    return $selected
}

function Test-PathWithinDirectory {
    param(
        [string]$Path,
        [string]$Directory
    )

    if (-not $Path -or -not $Directory) {
        return $false
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'
    return $fullPath.StartsWith($fullDirectory, [StringComparison]::OrdinalIgnoreCase)
}

function Get-NpmCodexOwner {
    try {
        $npm = Get-Command npm -ErrorAction SilentlyContinue | Select-Object -First 1
        $codex = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $npm -or -not $codex -or
            $npm.CommandType -notin @('Application', 'ExternalScript') -or
            $codex.CommandType -notin @('Application', 'ExternalScript')) {
            return $null
        }

        $globalPrefix = (& $npm.Source prefix --global 2>$null | Select-Object -Last 1)
        if ($LASTEXITCODE -ne 0 -or -not $globalPrefix) {
            return $null
        }
        $globalRoot = (& $npm.Source root --global 2>$null | Select-Object -Last 1)
        if ($LASTEXITCODE -ne 0 -or -not $globalRoot) {
            return $null
        }
        $packagePath = Join-Path $globalRoot '@openai\codex\package.json'
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
            return $null
        }
        $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
        if ($package.name -ne '@openai/codex' -or
            -not (Test-PathWithinDirectory -Path $codex.Source -Directory $globalPrefix)) {
            return $null
        }
        return [pscustomobject]@{ Npm = $npm.Source; Prefix = $globalPrefix }
    } catch {
        return $null
    }
}

function Test-WingetCommandPath {
    param(
        [string]$Command,
        [string]$PackagePrefix
    )

    $resolved = Get-Command $Command -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $resolved -or $resolved.CommandType -notin @('Application', 'ExternalScript')) {
        return $false
    }
    $directories = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path $env:ProgramFiles 'WinGet\Packages')
    )
    foreach ($directory in @($directories)) {
        if ($directory -like '*Packages') {
            $packageDirectories = @(Get-ChildItem -LiteralPath $directory `
                -Directory -Filter "$PackagePrefix*" -ErrorAction SilentlyContinue)
            foreach ($packageDirectory in $packageDirectories) {
                if (Test-PathWithinDirectory -Path $resolved.Source `
                    -Directory $packageDirectory.FullName) {
                    return $true
                }
            }
        } elseif (Test-PathWithinDirectory -Path $resolved.Source -Directory $directory) {
            return $true
        }
    }
    return $false
}

function Get-WingetUpdateCandidate {
    param(
        [string]$Id,
        [string]$Scope
    )

    $output = @(& winget list --upgrade-available --id $Id --exact `
        --scope $Scope --source winget --accept-source-agreements `
        --disable-interactivity 2>&1)
    $outputText = $output -join "`n"
    if ($LASTEXITCODE -ne 0) {
        if ($outputText -match '(?i)no installed package found|no (applicable )?upgrade|no update available') {
            return $null
        }
        throw "Winget list --upgrade-available exited with code $LASTEXITCODE."
    }
    $row = Get-WingetExactRow -Id $Id -Lines $output
    if ($row) {
        $idPosition = $row.IndexOf($Id, [StringComparison]::OrdinalIgnoreCase)
        $versions = @($row.Substring($idPosition + $Id.Length).Trim() -split '\s+')
        if ($versions.Count -ge 2) {
            return "$($versions[0]) -> $($versions[1])"
        }
        throw 'Winget returned an update row without installed and available versions.'
    }
    return $null
}

function Invoke-WingetUpgrade {
    param(
        [string]$Id,
        [string]$Scope
    )

    $output = @(& winget upgrade --id $Id --exact --scope $Scope --source winget `
        --accept-package-agreements --accept-source-agreements `
        --disable-interactivity 2>&1)
    $outputText = $output -join "`n"
    if ($LASTEXITCODE -ne 0) {
        if ($outputText -match '(?i)no (applicable )?upgrade|no update available') {
            return $false
        }
        throw "Winget upgrade exited with code $LASTEXITCODE."
    }
    $output | Out-Host
    return $true
}

function Test-ToolCommand {
    param([hashtable]$Definition)

    if (-not $Definition.Command) {
        return $true
    }
    if (-not (Get-Command $Definition.Command -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $arguments = @($Definition.Arguments)
        $global:LASTEXITCODE = 0
        & $Definition.Command @arguments *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Get-ToolUpdatePlan {
    param([string]$Key)

    $definition = $definitions[$Key]
    if ($Key -eq 'codex') {
        $npmOwner = Get-NpmCodexOwner
        if ($npmOwner) {
            return [pscustomobject]@{
                Tool = $definition.Label; Status = 'ready'; Source = 'npm'
                Detail = 'Global @openai/codex is active; update it through npm.'
            }
        }
        if (-not (Test-WingetCommandPath -Command $definition.Command `
            -PackagePrefix $definition.Prefix)) {
            return [pscustomobject]@{
                Tool = $definition.Label; Status = 'skipped'; Source = ''
                Detail = 'The active Codex CLI is not owned by its Winget or global npm installation.'
            }
        }
    }

    $wingetStatus = Get-WingetPackageStatus -Id $definition.Id
    if ($wingetStatus -eq 'missing' -or $wingetStatus -eq 'unavailable') {
        return [pscustomobject]@{
            Tool = $definition.Label; Status = 'skipped'; Source = ''
            Detail = if ($wingetStatus -eq 'missing') {
                'No exact Winget package is installed; leaving other installation sources unchanged.'
            } else {
                'Winget is unavailable, so the installed source cannot be verified.'
            }
        }
    }
    if ($wingetStatus -eq 'ambiguous') {
        return [pscustomobject]@{
            Tool = $definition.Label; Status = 'skipped'; Source = ''
            Detail = 'The exact Winget package is installed in both scopes; update was not applied.'
        }
    }
    if ($wingetStatus -notin @('installed-user', 'installed-machine')) {
        return [pscustomobject]@{
            Tool = $definition.Label; Status = 'failed'; Source = ''
            Detail = 'Winget did not return an exact installed package row; update source is ambiguous.'
        }
    }
    $scope = $wingetStatus -replace '^installed-', ''
    if ($Key -eq 'codex' -and -not (Test-WingetCommandPath `
        -Command $definition.Command -PackagePrefix $definition.Prefix)) {
        return [pscustomobject]@{
            Tool = $definition.Label; Status = 'skipped'; Source = ''
            Detail = 'Codex is installed through Winget, but the active command path is owned elsewhere.'
        }
    }

    $candidate = Get-WingetUpdateCandidate -Id $definition.Id -Scope $scope
    if (-not $candidate) {
        return [pscustomobject]@{
            Tool = $definition.Label; Status = 'current'; Source = 'winget'
            Detail = 'The installed Winget package has no applicable update.'
        }
    }

    return [pscustomobject]@{
        Tool = $definition.Label; Status = 'ready'; Source = 'winget'
        Scope = $scope
        Detail = if ($Key -eq 'nvm-node-lts') {
            "Would update NVM package in the $scope scope ($candidate); Node.js LTS version changes are deferred."
        } else {
            "Would update Winget package in the $scope scope ($candidate)."
        }
    }
}

function Invoke-ToolUpdate {
    param([string]$Key)

    try {
        $plan = Get-ToolUpdatePlan -Key $Key
        if ($plan.Status -ne 'ready') {
            return $plan
        }
        $definition = $definitions[$Key]
        if ($plan.Source -eq 'npm') {
            $npmOwner = Get-NpmCodexOwner
            if (-not $npmOwner) {
                throw 'The active global npm Codex installation changed before update.'
            }
            & $npmOwner.Npm install --global '@openai/codex' | Out-Host
            if ($LASTEXITCODE -ne 0 -or -not (Get-NpmCodexOwner) -or
                -not (Test-ToolCommand -Definition $definition)) {
                throw 'npm update failed or Codex no longer resolves to the global npm package.'
            }
            return [pscustomobject]@{
                Tool = $definition.Label; Status = 'updated'; Source = 'npm'
                Detail = 'Updated the active global npm package.'
            }
        }

        $applied = Invoke-WingetUpgrade -Id $definition.Id -Scope $plan.Scope
        if ((Get-WingetPackageStatus -Id $definition.Id) -ne "installed-$($plan.Scope)") {
            throw 'The exact Winget package could not be verified after update.'
        }
        if (-not (Test-ToolCommand -Definition $definition)) {
            throw "The $($definition.Command) command did not pass its post-update check."
        }
        return [pscustomobject]@{
            Tool = $definition.Label
            Status = if ($applied) { 'updated' } else { 'current' }
            Source = 'winget'
            Detail = if ($Key -eq 'nvm-node-lts') {
                'Verified NVM after the Winget update. Node.js LTS version changes remain deferred.'
            } else {
                'Verified the Winget package and command after update.'
            }
        }
    } catch {
        return [pscustomobject]@{
            Tool = $definition.Label; Status = 'failed'; Source = $plan.Source
            Detail = $_.Exception.Message
        }
    }
}

$selectedTools = @(Get-SelectedWindowsTools)
if ($selectedTools.Count -eq 0) {
    Write-Output 'No Windows tools are selected in chezmoi data.'
    exit 0
}

$results = foreach ($key in $selectedTools) {
    try {
        $plan = Get-ToolUpdatePlan -Key $key
        if ($Apply -and $plan.Status -eq 'ready') {
            Invoke-ToolUpdate -Key $key
        } elseif ($plan.Status -eq 'ready') {
            $plan.Status = 'preview'
            $plan.Detail = if ($plan.Source -eq 'winget') {
                $plan.Detail
            } else {
                'Would run: npm install --global @openai/codex'
            }
            $plan
        } else {
            $plan
        }
    } catch {
        [pscustomobject]@{
            Tool = $definitions[$key].Label; Status = 'failed'; Source = ''
            Detail = $_.Exception.Message
        }
    }
}

$results | Format-Table -AutoSize Tool, Status, Source, Detail
if (-not $Apply -and @($results | Where-Object Status -eq 'preview').Count -gt 0) {
    Write-Output 'Preview only. Rerun with -Apply to update the listed tools.'
}
if (@($results | Where-Object Status -eq 'failed').Count -gt 0) {
    exit 1
}
