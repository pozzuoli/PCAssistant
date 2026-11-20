# Invoke-Tests.ps1 - run every tests\windows\*.Tests.ps1 with Pester 5 (in PowerShell 7), with -Shell as the shell
# that runs the scripts under test. In GitHub Actions it also writes a failure table to the job summary.
param(
    [Parameter(Mandatory)][ValidateSet('powershell', 'pwsh')][string]$Shell,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    # CI passes the exact version it installed; locally any Pester 5.5+ is fine.
    [string]$PesterVersion = ''
)
$ErrorActionPreference = 'Stop'
if ($PesterVersion) { Import-Module Pester -RequiredVersion $PesterVersion } else { Import-Module Pester -MinimumVersion 5.5.0 }
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$inActions = [bool]$env:GITHUB_ACTIONS

function Get-FirstLine($ErrorRecord) {
    $m = (@($ErrorRecord) | Select-Object -First 1).Exception.Message
    if ($m) { (($m -split "`r?`n")[0]).Replace('|', '\|') } else { '' }
}

# Child shells write stdout in the console output code page they inherit. Without an interactive console (as in CI)
# that is the OEM code page (437), which turns non-ASCII text into '?'. Use UTF-8 for this run, restore it after.
$prevOutEnc = $null
try { $prevOutEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) }
catch { Write-Warning "could not set the console output encoding: $($_.Exception.Message)" }

$code = 1
try {
    $exe = Get-ShellExe $Shell
    $ver = & $exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    $acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP
    "Shell under test: $Shell $ver | Pester $((Get-Module Pester).Version) in PowerShell $($PSVersionTable.PSVersion) | ANSI code page $acp | console output code page $([Console]::OutputEncoding.CodePage)"
    if ($Shell -eq 'powershell' -and $acp -eq '65001') {
        $w = 'ANSI code page is 65001 (UTF-8): Windows PowerShell 5.1 decodes BOM-less scripts as UTF-8 here, so its BOM-related failures cannot show'
        if ($inActions) { "::warning title=ANSI code page::$w" } else { Write-Warning $w }
    }

    $data = @{ Shell = $Shell; RepoRoot = $RepoRoot }
    $containers = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' | Sort-Object Name |
        ForEach-Object { New-PesterContainer -Path $_.FullName -Data $data })
    $cfg = New-PesterConfiguration
    $cfg.Run.Container = $containers
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Detailed'
    $res = Invoke-Pester -Configuration $cfg

    if ($env:GITHUB_STEP_SUMMARY) {
        $lines = @("### Pester, shell under test: $Shell $ver (ANSI code page $acp)", '',
            ("Passed $($res.PassedCount), failed $($res.FailedCount), skipped $($res.SkippedCount), " +
             "failed blocks $($res.FailedBlocksCount), failed containers $($res.FailedContainersCount)."), '')
        $rows = @()
        foreach ($t in $res.Failed) { $rows += "| $($t.ExpandedPath.Replace('|', '\|')) | $(Get-FirstLine $t.ErrorRecord) |" }
        foreach ($b in $res.FailedBlocks) { $rows += "| block: $($b.ExpandedPath.Replace('|', '\|')) | $(Get-FirstLine $b.ErrorRecord) |" }
        foreach ($c in $res.FailedContainers) { $rows += "| container: $(Split-Path -Leaf "$($c.Item)") | $(Get-FirstLine $c.ErrorRecord) |" }
        if ($rows) { $lines += @('| Test | First line of the failure |', '|---|---|') + $rows }
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $lines -Encoding utf8
    }
    $code = if ($res.Result -eq 'Passed') { 0 } else { 1 }
} finally {
    if ($prevOutEnc) { try { [Console]::OutputEncoding = $prevOutEnc } catch { Write-Warning 'could not restore the console output encoding' } }
}
exit $code
