[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingInvokeExpression',
    '',
    Justification = 'Reviewed shell tools emit their supported initialization scripts.'
)]
param()

$interactive =
    -not [Console]::IsInputRedirected -and
    -not [Console]::IsOutputRedirected

if (-not $interactive) {
    return
}

$localBin = Join-Path $HOME '.local\bin'
if (Test-Path -LiteralPath $localBin -PathType Container) {
    $pathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
    if ($localBin -notin $pathEntries) {
        $env:PATH = $localBin + [IO.Path]::PathSeparator + $env:PATH
    }
}

Import-Module PSReadLine -ErrorAction Stop
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 32767
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle InlineView
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

$theme = Join-Path $HOME '.config\oh-my-posh\emodipt-extend.omp.json'
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and
    (Test-Path -LiteralPath $theme -PathType Leaf)) {
    oh-my-posh init pwsh --config $theme |
        Out-String |
        Invoke-Expression
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide init powershell |
        Out-String |
        Invoke-Expression
}

if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell --disable-up-arrow --disable-ai |
        Out-String |
        Invoke-Expression
}

