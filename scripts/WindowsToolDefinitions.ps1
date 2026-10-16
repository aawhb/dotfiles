function Get-WindowsToolDefinitions {
    @{
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
        'notepad-plus-plus' = @{
            Label = 'Notepad++'; Id = 'Notepad++.Notepad++'; Command = ''
            Arguments = @(); Prefix = 'Notepad++.Notepad++_'
        }
        'lm-studio' = @{
            Label = 'LM Studio'; Id = 'ElementLabs.LMStudio'; Command = ''
            Arguments = @(); Prefix = 'ElementLabs.LMStudio_'
        }
        'k-lite-codec-pack-mega' = @{
            Label = 'K-Lite Codec Pack Mega'; Id = 'CodecGuide.K-LiteCodecPack.Mega'; Command = ''
            Arguments = @(); Prefix = 'CodecGuide.K-LiteCodecPack.Mega_'
        }
        'windhawk' = @{
            Label = 'Windhawk'; Id = 'RamenSoftware.Windhawk'; Command = ''
            Arguments = @(); Prefix = 'RamenSoftware.Windhawk_'
        }
        'powertoys' = @{
            Label = 'PowerToys'; Id = 'Microsoft.PowerToys'; Command = ''
            Arguments = @(); Prefix = 'Microsoft.PowerToys_'
        }
        'zoom' = @{
            Label = 'Zoom Workplace'; Id = 'Zoom.Zoom.EXE'; Command = ''
            Arguments = @(); Prefix = 'Zoom.Zoom.EXE_'
        }
        'teams' = @{
            Label = 'Microsoft Teams'; Id = 'Microsoft.Teams'; Command = ''
            Arguments = @(); Prefix = 'Microsoft.Teams_'
        }
        'nanazip' = @{
            Label = 'NanaZip'; Id = 'M2Team.NanaZip'; Command = ''
            Arguments = @(); Prefix = 'M2Team.NanaZip_'
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
        'herdr' = @{
            Label = 'Herdr'; Id = 'Herdr.Herdr.Preview'; Command = 'herdr'
            Arguments = @('--version'); Prefix = 'Herdr.Herdr.Preview_'
        }
        'github-cli' = @{
            Label = 'GitHub CLI'; Id = 'GitHub.cli'; Command = 'gh'
            Arguments = @('--version'); Prefix = 'GitHub.cli_'
        }
        'bitwarden-cli' = @{
            Label = 'Bitwarden CLI'; Id = 'Bitwarden.CLI'; Command = 'bw'
            Arguments = @('--version'); Prefix = 'Bitwarden.CLI_'
        }
        'tailscale' = @{
            Label = 'Tailscale'; Id = 'Tailscale.Tailscale'; Command = 'tailscale'
            Arguments = @('version'); Prefix = 'Tailscale.Tailscale_'
        }
    }
}

function Get-WindowsToolInstallOrder {
    param([string[]]$SelectedTools)

    $ordered = @('powershell', 'nvm-node-lts') + @($SelectedTools)
    @($ordered | Select-Object -Unique)
}

function Get-WingetExactRow {
    param(
        [string]$Id,
        [string[]]$Lines
    )

    $pattern = '(?<!\S)' + [regex]::Escape($Id) + '(?!\S)'
    foreach ($line in $Lines) {
        if ($line.ToString() -match $pattern) {
            return $line.ToString()
        }
    }
    return $null
}

function Get-WingetPackageStatus {
    param([string]$Id)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return 'unavailable'
    }
    $installedScopes = @()
    foreach ($scope in @('user', 'machine')) {
        $output = @(& winget list --id $Id --exact --scope $scope --source winget `
            --accept-source-agreements --disable-interactivity 2>&1)
        $outputText = $output -join "`n"
        if ($outputText -match '(?i)no installed package found') {
            continue
        }
        if ($LASTEXITCODE -ne 0) {
            return 'error'
        }
        if (Get-WingetExactRow -Id $Id -Lines $output) {
            $installedScopes += $scope
        } else {
            return 'unmatched'
        }
    }
    if ($installedScopes.Count -gt 1) {
        return 'ambiguous'
    }
    if ($installedScopes.Count -eq 1) {
        return "installed-$($installedScopes[0])"
    }
    return 'missing'
}

function Test-WingetPackage {
    param([string]$Id)

    $status = Get-WingetPackageStatus -Id $Id
    if ($status -in @('unavailable', 'error', 'unmatched')) {
        throw "Could not verify Winget package '$Id' (inventory status: $status)."
    }
    return $status -in @('installed-user', 'installed-machine', 'ambiguous')
}
