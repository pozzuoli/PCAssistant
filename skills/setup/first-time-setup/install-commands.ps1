<#
install-commands.ps1 - expose every skills\**\pca-*.ps1 script as a `pca-*` command (Windows).
Creates .cmd shims in %USERPROFILE%\.pca\bin and adds that folder to the *user* PATH (no admin needed).
Idempotent: re-run after adding a skill. Removes shims whose target script no longer exists.
  powershell -NoProfile -ExecutionPolicy Bypass -File install-commands.ps1 [-Bin <dir>]
#>
param([string]$Bin = (Join-Path $env:USERPROFILE '.pca\bin'))
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
New-Item -ItemType Directory -Force -Path $Bin | Out-Null

# Prefer PowerShell 7 if installed, else Windows PowerShell 5.1
$ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

$scripts = Get-ChildItem -Path (Join-Path $Root 'skills') -Recurse -File -Filter 'pca-*.ps1'
foreach ($s in $scripts) {
    $name = [IO.Path]::GetFileNameWithoutExtension($s.Name)
    $shim = Join-Path $Bin "$name.cmd"
    $body = "@echo off`r`n:: PC Assistant shim -> $($s.FullName)`r`n$ps -NoProfile -ExecutionPolicy Bypass -File `"$($s.FullName)`" %*`r`n"
    if ((Test-Path $shim) -and ((Get-Content $shim -Raw) -eq $body)) { "ok       $name"; continue }
    if ((Test-Path $shim) -and -not ((Get-Content $shim -Raw) -match 'PC Assistant shim')) { Write-Warning "SKIPPED $name`: $shim exists and is not ours"; continue }
    Set-Content -Path $shim -Value $body -NoNewline -Encoding ASCII
    "linked   $name -> $($s.FullName)"
}

# prune shims whose target is gone
Get-ChildItem -Path $Bin -Filter 'pca-*.cmd' | ForEach-Object {
    $c = Get-Content $_.FullName -Raw
    if ($c -match 'PC Assistant shim -> (.+?)\r?\n' -and -not (Test-Path $Matches[1])) { Remove-Item $_.FullName; "removed  $($_.BaseName) (target gone)" }
}

# add to user PATH if missing
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($userPath -split ';') -contains $Bin)) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$Bin").TrimStart(';'), 'User')
    "added $Bin to the user PATH (open a new terminal to pick it up)"
}
