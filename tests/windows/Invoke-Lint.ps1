# Invoke-Lint.ps1 - PSScriptAnalyzer over every .ps1 under skills\ (run with PowerShell 7).
# Fails on Error-severity findings and on the rules in $Blocking; every other finding is reported, not fatal.
# Settings: PSScriptAnalyzerSettings.psd1 next to this file. In GitHub Actions, findings become annotations.
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    # CI passes the exact version it installed; locally any PSScriptAnalyzer 1.21+ is fine.
    [string]$AnalyzerVersion = ''
)
$ErrorActionPreference = 'Stop'
if ($AnalyzerVersion) { Import-Module PSScriptAnalyzer -RequiredVersion $AnalyzerVersion } else { Import-Module PSScriptAnalyzer -MinimumVersion 1.21.0 }

# PSUseBOMForUnicodeEncodedFile: Windows PowerShell 5.1 reads a BOM-less script in the system ANSI code page, so a
# non-ASCII character in a BOM-less .ps1 can change how the whole script parses (README.md in this folder).
$Blocking = @('PSUseBOMForUnicodeEncodedFile')

$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
$results = @(Invoke-ScriptAnalyzer -Path (Join-Path $Root 'skills') -Recurse -Settings $settings)
$inActions = [bool]$env:GITHUB_ACTIONS
function ConvertTo-AnnotationText([string]$s) { $s.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A') }

$fatal = 0
foreach ($r in ($results | Sort-Object ScriptPath, Line)) {
    $rel = [IO.Path]::GetRelativePath($Root, $r.ScriptPath).Replace('\', '/')
    $isFatal = ($r.Severity -eq 'Error') -or ($Blocking -contains $r.RuleName)
    if ($isFatal) { $fatal++ }
    $level = if ($isFatal) { 'error' } else { 'warning' }
    $line = if ($r.Line) { $r.Line } else { 1 }
    if ($inActions) { "::$level file=$rel,line=$line,title=$($r.RuleName)::$(ConvertTo-AnnotationText $r.Message)" }
    else { '{0,-7} {1}:{2} {3}: {4}' -f $level.ToUpper(), $rel, $line, $r.RuleName, $r.Message }
}
"PSScriptAnalyzer $((Get-Module PSScriptAnalyzer).Version): $($results.Count) finding(s), $fatal blocking."
if ($fatal -gt 0) { exit 1 }
