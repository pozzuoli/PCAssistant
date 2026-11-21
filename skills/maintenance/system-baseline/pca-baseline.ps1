<#
pca-baseline (Windows) - capture a READ-ONLY snapshot of system state into logging\baseline\<stamp>\,
or diff two snapshots. Part of the system-baseline skill.
  pca-baseline [label]            capture (dir: YYYY-MM-DD_HHmm[_label])
  pca-baseline --list             list baselines
  pca-baseline --diff <a> <b>     compare two baselines (dir names)
Some items (all services' details, scheduled tasks of other users) are more complete from an elevated shell.
#>
$ErrorActionPreference = 'SilentlyContinue'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Base = Join-Path $Root 'logging\baseline'

switch ($args[0]) {
    '--list' { Get-ChildItem $Base -Directory | ForEach-Object Name; exit 0 }
    '--diff' {
        if ($args.Count -ne 3) { Write-Error 'usage: pca-baseline --diff <a> <b>'; exit 1 }
        $a = Join-Path $Base $args[1]; $b = Join-Path $Base $args[2]
        $names = @(Get-ChildItem $a -File | ForEach-Object Name) + @(Get-ChildItem $b -File | ForEach-Object Name) | Sort-Object -Unique
        foreach ($n in $names) {
            $fa = Join-Path $a $n; $fb = Join-Path $b $n
            if (-not (Test-Path $fa)) { "+++ only in $($args[2]): $n"; continue }
            if (-not (Test-Path $fb)) { "--- only in $($args[1]): $n"; continue }
            # captures are UTF-8 (BOM from 5.1, none from 7); read them as UTF-8 so either shell can diff either
            $d = Compare-Object (Get-Content -LiteralPath $fa -Encoding UTF8) (Get-Content -LiteralPath $fb -Encoding UTF8)
            if ($d) { "=== $n"; $d | ForEach-Object { "$(if ($_.SideIndicator -eq '=>') { '+' } else { '-' }) $($_.InputObject)" } }
        }
        exit 0
    }
    { $_ -in '-h', '--help' } { Get-Content $PSCommandPath | Select-Object -Skip 1 -First 7; exit 0 }
}

$stamp = (Get-Date -Format 'yyyy-MM-dd_HHmm') + $(if ($args[0]) { "_$($args[0])" } else { '' })
$Out = Join-Path $Base $stamp
New-Item -ItemType Directory -Force -Path $Out | Out-Null
function Cap($file, [scriptblock]$sb) {
    $p = Join-Path $Out $file
    try { & $sb | Out-File -FilePath $p -Encoding utf8 -Width 400 } catch {}
    if ((Test-Path $p) -and (Get-Item $p).Length -eq 0) { Remove-Item $p }
}

Cap 'system.txt' { Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime }
Cap 'disks.txt' { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Format-Table DeviceID, FileSystem, @{n = 'SizeGB'; e = { [Math]::Round($_.Size / 1GB, 1) } }, @{n = 'FreeGB'; e = { [Math]::Round($_.FreeSpace / 1GB, 1) } } -AutoSize }
Cap 'pkg-installed-programs.txt' {
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        ForEach-Object { Get-ItemProperty $_ } | Where-Object DisplayName | Sort-Object DisplayName |
        ForEach-Object { "$($_.DisplayName)`t$($_.DisplayVersion)`t$($_.Publisher)" }
}
if (Get-Command winget) {
    # winget writes the export file itself. Exporting through Cap would aim it at the file Out-File already holds
    # open (sharing violation, no file), so export to a temp file and move it into place.
    $wj = Join-Path ([IO.Path]::GetTempPath()) ('pca-winget-' + [guid]::NewGuid().ToString('N') + '.json')
    winget export -o $wj --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $wj) -and (Get-Item -LiteralPath $wj).Length -gt 0) {
        Move-Item -LiteralPath $wj -Destination (Join-Path $Out 'pkg-winget.json') -Force
    } else { Remove-Item -LiteralPath $wj -ErrorAction SilentlyContinue }
}
if (Get-Command choco) { Cap 'pkg-choco.txt' { choco list --limit-output } }
if (Get-Command scoop) { Cap 'pkg-scoop.txt' { scoop list } }
Cap 'pkg-appx.txt' { Get-AppxPackage | Sort-Object Name | ForEach-Object { "$($_.Name)`t$($_.Version)" } }
if (Get-Command Get-WindowsFeature) { Cap 'features-server.txt' { Get-WindowsFeature | Where-Object Installed | ForEach-Object Name } }
else { Cap 'features-optional.txt' { Get-WindowsOptionalFeature -Online | Where-Object State -eq 'Enabled' | ForEach-Object FeatureName | Sort-Object } }
Cap 'services.txt' { Get-Service | Sort-Object Name | ForEach-Object { "$($_.Name)`t$($_.StartType)`t$($_.Status)" } }
Cap 'scheduled-tasks.txt' { Get-ScheduledTask | Where-Object State -ne 'Disabled' | ForEach-Object { "$($_.TaskPath)$($_.TaskName)`t$($_.State)" } }
Cap 'startup-items.txt' { Get-CimInstance Win32_StartupCommand | ForEach-Object { "$($_.Name)`t$($_.Location)`t$($_.Command)" } }
Cap 'firewall-profiles.txt' { Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction -AutoSize }
Cap 'power-plan.txt' { powercfg /getactivescheme }
Cap 'env-user-path.txt' { [Environment]::GetEnvironmentVariable('Path', 'User') -split ';' }
Cap 'env-machine-path.txt' { [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' }

# redact obvious secrets in config-type captures (package/service lists are left alone)
Get-ChildItem $Out -File | Where-Object { $_.Name -notmatch '^(pkg-|services|features-)' } | ForEach-Object {
    (Get-Content -LiteralPath $_.FullName -Encoding UTF8) -replace '(?i)([a-z0-9_.-]*(password|passwd|secret|token|api[_-]?key|psk|credentials)[a-z0-9_.-]*\s*[=:]\s*).*', '$1[REDACTED]' -replace '://[^/@\s:]+:[^/@\s]+@', '://[REDACTED]@' | Set-Content $_.FullName -Encoding utf8
}
"pca-baseline: captured $((Get-ChildItem $Out -File).Count) files -> $($Out.Substring($Root.Length + 1))"
