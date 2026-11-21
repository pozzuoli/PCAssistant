<#
pca-backup (Windows) - back up / restore files and registry keys tied to a PC Assistant change ID.
Works with Windows PowerShell 5.1+ and PowerShell 7+. Part of the change-backup skill.

  pca-backup <ID> [--private] <path>...          back up files/folders before change <ID>
  pca-backup <ID> [--private] --reg <key>...     export registry keys (e.g. HKLM\SOFTWARE\Foo)
  pca-backup --restore <ID> [--private] [path|key...]   restore all (or listed) items
  pca-backup --list <ID> [--private]             show what <ID> backed up
  pca-backup --verify <ID> [--private]           check backup checksums

Files go to logging\backups\<ID>\<Drive>\<path>; registry keys to logging\backups\<ID>\registry\*.reg.
METADATA records kind, original path, and ACL (SDDL); SHA256SUMS holds hashes. Both are UTF-8.
--private uses logging\backups-private\ (never committed) for anything containing secrets.
#>
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page.
$ErrorActionPreference = 'Stop'

function Die($msg) { Write-Error "pca-backup: $msg" -ErrorAction Continue; exit 1 }
function Say($msg) { Write-Host "pca-backup: $msg" }

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path (Join-Path $Root 'CLAUDE.md'))) { Die "cannot find project root (looked in $Root)" }

# --- args (--private and --reg may appear anywhere) ---
$private = $false; $reg = $false; $rest = @()
foreach ($a in $args) {
    switch ($a) { '--private' { $private = $true } '--reg' { $reg = $true } default { $rest += $a } }
}
$mode = 'backup'
if ($rest.Count -eq 0 -or $rest[0] -in @('-h', '--help')) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 12; exit 0
}
# @(...) keeps $rest an array: with a single element left, $rest[0] must be the ID, not its first character
if ($rest[0] -in @('--restore', '--list', '--verify')) { $mode = $rest[0].TrimStart('-'); $rest = @($rest | Select-Object -Skip 1) }
if ($rest.Count -eq 0) { Die 'missing change ID (e.g. C-0042)' }
$id = $rest[0]; $items = @($rest | Select-Object -Skip 1)
if ($id -notmatch '^C-\d+$') { Die "change ID should look like C-0042 (got '$id')" }

$base = Join-Path $Root ($(if ($private) { 'logging\backups-private' } else { 'logging\backups' }))
$dest = Join-Path $base $id
$metaFile = Join-Path $dest 'METADATA'
$sumFile = Join-Path $dest 'SHA256SUMS'

function Get-BackupPath([string]$full) {
    # C:\Windows\x -> <dest>\C\Windows\x ; \\server\share\x -> <dest>\UNC\server\share\x
    if ($full -match '^([A-Za-z]):\\(.*)$') { return Join-Path $dest (Join-Path $Matches[1] $Matches[2]) }
    if ($full -match '^\\\\(.*)$') { return Join-Path $dest (Join-Path 'UNC' $Matches[1]) }
    Die "unsupported path: $full"
}
function Get-RegBackupPath([string]$key) {
    # The key's hash keeps names unique: HKCU\Software\a_b and HKCU\Software\a\b map to the same readable part.
    $safe = ($key -replace '[\\/:*?"<>|]', '_')
    $bytes = [Text.Encoding]::UTF8.GetBytes($key.ToLowerInvariant())
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').Substring(0, 8).ToLower()
    return Join-Path $dest (Join-Path 'registry' "$safe-$hash.reg")
}
function Get-LegacyRegBackupPath([string]$key) {
    # name used by backups made before the hash suffix was added; restore falls back to it
    $safe = ($key -replace '[\\/:*?"<>|]', '_')
    return Join-Path $dest (Join-Path 'registry' "$safe.reg")
}
function Resolve-RegBackupFile([string]$key) {
    # The hashed name wins when its file exists or SHA256SUMS lists it, so a lost file is reported as MISSING. The
    # legacy name is only for backups made before the hash suffix; on disk alone it may belong to another key
    # (a_b vs a\b), which is why restore also checks the key named inside the file (Test-RegFileKey).
    $file = Get-RegBackupPath $key
    if (Test-Path -LiteralPath $file) { return $file }
    if (Test-Path -LiteralPath $sumFile) {
        $rel = $file.Substring($dest.Length)
        foreach ($line in Read-MetaLine $sumFile) { if (($line -split '  ', 2)[1] -eq $rel) { return $file } }
    }
    return Get-LegacyRegBackupPath $key
}
function Test-RegFileKey([string]$file, [string]$key) {
    # A .reg export names its key on the first [..] line, e.g. [HKEY_CURRENT_USER\Software\Foo]. Restore imports a
    # file only when that is the key being restored.
    $full = $key.TrimEnd('\') -replace '^HKCU(?=\\|$)', 'HKEY_CURRENT_USER' -replace '^HKLM(?=\\|$)', 'HKEY_LOCAL_MACHINE' `
        -replace '^HKCR(?=\\|$)', 'HKEY_CLASSES_ROOT' -replace '^HKU(?=\\|$)', 'HKEY_USERS' -replace '^HKCC(?=\\|$)', 'HKEY_CURRENT_CONFIG'
    $first = Get-Content -LiteralPath $file -TotalCount 10 | Where-Object { $_ -match '^\[' } | Select-Object -First 1
    return ($first -eq "[$full]")
}
function Get-EntryBackupPath([string]$kind, [string]$path) {
    if ($kind -eq 'reg') { return Resolve-RegBackupFile $path }
    return Get-BackupPath $path
}
function Read-MetaLine([string]$file) {
    # METADATA and SHA256SUMS are UTF-8. A line that is not valid UTF-8 was written by an older version running in
    # Windows PowerShell 5.1, which used the ANSI code page, so that line is read as ANSI. Decoding per line matters
    # because a newer run may have appended UTF-8 lines to an older ANSI file.
    $strict = New-Object Text.UTF8Encoding($false, $true)
    $ansi = [Text.Encoding]::GetEncoding([int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP)
    $bytes = [IO.File]::ReadAllBytes($file)
    $pos = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $pos = 3 }
    while ($pos -lt $bytes.Length) {
        $nl = [Array]::IndexOf($bytes, [byte]10, $pos)
        if ($nl -lt 0) { $nl = $bytes.Length }
        $len = $nl - $pos
        if ($len -gt 0 -and $bytes[$pos + $len - 1] -eq 13) { $len-- }
        if ($len -gt 0) { try { $strict.GetString($bytes, $pos, $len) } catch { $ansi.GetString($bytes, $pos, $len) } }
        $pos = $nl + 1
    }
}
function Test-Recorded([string]$kind, [string]$path) {
    # true when METADATA already holds an entry of this kind for exactly this path or key
    if (-not (Test-Path -LiteralPath $metaFile)) { return $false }
    foreach ($line in Read-MetaLine $metaFile) {
        $k, $null, $p = $line -split "`t", 3
        if ($k -eq $kind -and $p -eq $path) { return $true }
    }
    return $false
}
function Add-Sum([string]$file) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLower()
    Add-Content -LiteralPath $sumFile -Encoding UTF8 -Value "$h  $($file.Substring($dest.Length))"
}

function Backup-Item([string]$p) {
    if ($reg) {
        $out = Get-RegBackupPath $p
        if ((Test-Recorded 'reg' $p) -or (Test-Path -LiteralPath $out)) { Say "already backed up in $id (keeping original): $p"; return }
        New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
        & reg.exe export $p $out /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "reg export failed for $p (does the key exist? HKLM may need an elevated shell)" }
        Add-Content -LiteralPath $metaFile -Encoding UTF8 -Value "reg`t-`t$p"
        Add-Sum $out; Say "exported $p -> $($out.Substring($Root.Length + 1))"; return
    }
    $full = (Resolve-Path -LiteralPath $p).Path
    $out = Get-BackupPath $full
    if (Test-Path -LiteralPath $out) { Say "already backed up in $id (keeping original): $full"; return }
    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
    try {
        $isDir = (Get-Item -LiteralPath $full -Force).PSIsContainer
        Copy-Item -LiteralPath $full -Destination $out -Recurse:$isDir -Force
        $sddl = try { (Get-Acl -LiteralPath $full).Sddl } catch { '-' }
    } catch [System.UnauthorizedAccessException] { Die "access denied for $full - run from an elevated (Administrator) shell" }
    $kind = $(if ($isDir) { 'dir' } else { 'file' })
    Add-Content -LiteralPath $metaFile -Encoding UTF8 -Value "$kind`t$sddl`t$full"
    if ($isDir) { Get-ChildItem -LiteralPath $out -Recurse -File | ForEach-Object { Add-Sum $_.FullName } } else { Add-Sum $out }
    Say "backed up $full -> $($out.Substring($Root.Length + 1))"
}

function Test-Sums([string[]]$Only = @()) {
    # Checks every backup file, or only those under the backup paths in -Only. A missing, unreadable or changed file
    # counts as a problem and the check carries on, so every broken entry is reported. With -Only, a path that no
    # SHA256SUMS line covers is a problem too (nothing proves its backup is intact), unless it is a folder backup
    # that exists and holds no files.
    if (-not (Test-Path -LiteralPath $sumFile)) { Say "no checksums for $id"; return }
    $roots = @($Only | ForEach-Object { $_.TrimEnd('\') })   # a folder recorded as C:\x\ has files C:\x\f, not C:\x\\f
    $covered = @{}
    $bad = $false
    foreach ($line in Read-MetaLine $sumFile) {
        $h, $f = $line -split '  ', 2
        $full = $dest + $f
        if ($roots.Count -gt 0) {
            $hit = @($roots | Where-Object { $full -eq $_ -or $full.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) })
            if ($hit.Count -eq 0) { continue }
            foreach ($r in $hit) { $covered[$r] = $true }
        }
        if (-not (Test-Path -LiteralPath $full)) { Write-Warning "MISSING: $f"; $bad = $true; continue }
        $actual = try { (Get-FileHash -Algorithm SHA256 -LiteralPath $full -ErrorAction Stop).Hash.ToLower() } catch { $null }
        if (-not $actual) { Write-Warning "UNREADABLE: $f"; $bad = $true }
        elseif ($actual -ne $h) { Write-Warning "MISMATCH: $f"; $bad = $true }
    }
    foreach ($r in $roots) {
        if ($covered.ContainsKey($r)) { continue }
        if ((Test-Path -LiteralPath $r -PathType Container) -and -not (Get-ChildItem -LiteralPath $r -Recurse -File -Force | Select-Object -First 1)) { continue }
        Write-Warning "NO CHECKSUM: $($r.Substring($dest.Length)) (backup file missing or never summed)"; $bad = $true
    }
    if ($bad) { Die "checksum problems in $id (to restore other items, name them: --restore $id <path|key>...)" } else { Say "checksums OK for $id" }
}

function Restore-Entry([string]$kind, [string]$sddl, [string]$path) {
    if ($kind -eq 'reg') {
        $file = Resolve-RegBackupFile $path
        Say "importing registry key $path"
        & reg.exe import $file | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "reg import failed for $path (HKLM needs an elevated shell)" }
        return
    }
    $src = Get-BackupPath $path
    Say "restoring $path"
    try {
        if ($kind -eq 'dir') {
            if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
            # -LiteralPath: a folder name with [ or ] must not be read as a wildcard
            Get-ChildItem -LiteralPath $src -Force | Copy-Item -Destination $path -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -LiteralPath $src -Destination $path -Force
        }
        if ($sddl -and $sddl -ne '-') {
            try { $acl = Get-Acl -LiteralPath $path; $acl.SetSecurityDescriptorSddlForm($sddl); Set-Acl -LiteralPath $path -AclObject $acl }
            catch { Write-Warning "could not restore ACL on $path (needs elevation?)" }
        }
    } catch [System.UnauthorizedAccessException] { Die "access denied for $path - run from an elevated (Administrator) shell" }
}

switch ($mode) {
    'backup' {
        if ($items.Count -eq 0) { Die 'nothing to back up' }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($i in $items) { Backup-Item $i }
    }
    'list' {
        if (-not (Test-Path -LiteralPath $metaFile)) { Die "no backups recorded for $id" }
        "KIND`tACL`tPATH"; Read-MetaLine $metaFile
    }
    'verify' { Test-Sums }
    'restore' {
        if (-not (Test-Path -LiteralPath $metaFile)) { Die "no backups recorded for $id" }
        # a trailing \ must not matter when matching requested items against METADATA
        $want = @($items | ForEach-Object { $(if (Test-Path -LiteralPath $_) { (Resolve-Path -LiteralPath $_).Path } else { $_ }).TrimEnd('\') })
        $entries = @(foreach ($line in Read-MetaLine $metaFile) {
            $kind, $sddl, $path = $line -split "`t", 3
            if ($want.Count -gt 0 -and $path.TrimEnd('\') -notin $want) { continue }
            [pscustomobject]@{ Kind = $kind; Sddl = $sddl; Path = $path }
        })
        if ($entries.Count -eq 0) { Die "none of the requested items are in $id" }
        # Check everything that is about to be restored before restoring anything: the checksums of each selected
        # entry, and for registry entries that the backup file holds that same key.
        Test-Sums -Only @($entries | ForEach-Object { Get-EntryBackupPath $_.Kind $_.Path })
        foreach ($e in @($entries | Where-Object Kind -eq 'reg')) {
            $file = Resolve-RegBackupFile $e.Path
            if (-not (Test-Path -LiteralPath $file)) { Die "no backup file for $($e.Path) in $id; nothing was restored" }
            if (-not (Test-RegFileKey $file $e.Path)) { Die "the backup file for $($e.Path) holds a different key; nothing was restored" }
        }
        foreach ($e in $entries) { Restore-Entry $e.Kind $e.Sddl $e.Path }
    }
}
