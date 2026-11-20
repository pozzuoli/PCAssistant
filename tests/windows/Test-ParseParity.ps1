# Test-ParseParity.ps1 - parse every .ps1 under skills\ in Windows PowerShell 5.1 and in PowerShell 7, then compare.
# Fails when a script has parse errors in either shell, when the two shells decode it to different text (BOM-less
# non-ASCII bytes: 5.1 reads them in the ANSI code page, 7 as UTF-8), or when they find different functions in it
# (such a script can parse cleanly in 5.1 yet lose code). Run with pwsh.
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -Path (Join-Path $Root 'skills') -Recurse -File -Filter '*.ps1' | Sort-Object FullName)
$work = Join-Path ([IO.Path]::GetTempPath()) ('pca-parse-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $list = Join-Path $work 'files.txt'
    [IO.File]::WriteAllLines($list, [string[]]$files.FullName, (New-Object Text.UTF8Encoding($true)))

    # The probe runs inside each shell; ParseFile decodes a file the same way that shell's script loader does.
    # Output is plain tab-separated lines (file, kind, value), which both shells write the same way.
    $probe = Join-Path $work 'probe.ps1'
    Set-Content -LiteralPath $probe -Encoding ascii -Value @'
param([string]$ListFile, [string]$OutFile)
$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in (Get-Content -LiteralPath $ListFile -Encoding UTF8)) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    $lines.Add("$f`tFILE`t")
    $lines.Add("$f`tTEXTLEN`t$($ast.Extent.Text.Length)")
    foreach ($e in $errors) { $lines.Add("$f`tERROR`tline $($e.Extent.StartLineNumber): $($e.Message -replace '\s+', ' ')") }
    foreach ($n in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $lines.Add("$f`tFUNCTION`t$($n.Name)") }
}
[IO.File]::WriteAllLines($OutFile, $lines.ToArray(), (New-Object Text.UTF8Encoding($false)))
'@

    $shells = [ordered]@{
        'Windows PowerShell 5.1' = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        'PowerShell 7'           = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    }
    $byShell = @{}
    foreach ($name in $shells.Keys) {
        $out = Join-Path $work (($name -replace '\W', '') + '.tsv')
        & $shells[$name] -NoProfile -ExecutionPolicy Bypass -File $probe -ListFile $list -OutFile $out
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw "parse probe failed under $name" }
        $map = @{}
        foreach ($l in [IO.File]::ReadAllLines($out, (New-Object Text.UTF8Encoding($false)))) {
            $file, $kind, $value = $l -split "`t", 3
            if (-not $map.ContainsKey($file)) { $map[$file] = @{ Errors = @(); Functions = @(); TextLength = -1 } }
            if ($kind -eq 'TEXTLEN') { $map[$file].TextLength = [int]$value }
            if ($kind -eq 'ERROR') { $map[$file].Errors += $value }
            if ($kind -eq 'FUNCTION') { $map[$file].Functions += $value }
        }
        $byShell[$name] = $map
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

$acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP
"System ANSI code page: $acp (Windows PowerShell 5.1 decodes BOM-less scripts with it)"
$inActions = [bool]$env:GITHUB_ACTIONS
if ($acp -eq '65001') {
    $w = 'ANSI code page is 65001 (UTF-8): Windows PowerShell 5.1 decodes BOM-less scripts as UTF-8 here, so decoding differences cannot show'
    if ($inActions) { "::warning title=ANSI code page::$w" } else { Write-Warning $w }
}
$problems = 0
foreach ($f in $files.FullName) {
    $rel = [IO.Path]::GetRelativePath($Root, $f).Replace('\', '/')
    # summary messages first (decoding, functions), then the individual parse errors
    $msgs = @()
    $len51 = $byShell['Windows PowerShell 5.1'][$f].TextLength
    $len7 = $byShell['PowerShell 7'][$f].TextLength
    if ($len51 -ne $len7) { $msgs += "decoded differently: $len51 characters in Windows PowerShell 5.1, $len7 in PowerShell 7 (BOM-less non-ASCII bytes; save as ASCII or UTF-8 with BOM)" }
    $f51 = @($byShell['Windows PowerShell 5.1'][$f].Functions)
    $f7 = @($byShell['PowerShell 7'][$f].Functions)
    $only7 = @($f7 | Where-Object { $f51 -notcontains $_ })
    $only51 = @($f51 | Where-Object { $f7 -notcontains $_ })
    if ($only7) { $msgs += "functions missing in Windows PowerShell 5.1: $($only7 -join ', ')" }
    if ($only51) { $msgs += "functions missing in PowerShell 7: $($only51 -join ', ')" }
    foreach ($name in $shells.Keys) {
        $row = $byShell[$name][$f]
        if (-not $row) { $msgs += "not parsed in $name"; continue }
        foreach ($e in $row.Errors) { $msgs += "parse error in ${name}: $e" }
    }
    if ($msgs) {
        $problems++
        foreach ($m in ($msgs | Select-Object -First 8)) {
            if ($m.Length -gt 200) { $m = $m.Substring(0, 200) + '...' }
            if ($inActions) { "::error file=$rel,title=Parse parity::$m" } else { "FAIL  ${rel}: $m" }
        }
    } else {
        "ok    $rel ($($f7.Count) functions)"
    }
}
"$($files.Count) script(s) parsed in both shells, $problems with problems."
if ($problems -gt 0) { exit 1 }
