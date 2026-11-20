# TestHelpers.ps1 - shared helpers for the Windows tests (dot-sourced by the *.Tests.ps1 files and Invoke-Tests.ps1).
# Every file in tests/windows is ASCII-only. Non-ASCII test names are built from [char] codes, so these files read
# the same in Windows PowerShell 5.1 and PowerShell 7.

function Get-ShellExe {
    # Full path of the shell that runs the script under test.
    param([Parameter(Mandatory)][ValidateSet('powershell', 'pwsh')][string]$Shell)
    if ($Shell -eq 'powershell') { return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }
    (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
}

function New-FakeRoot {
    # A throwaway project root: a CLAUDE.md marker plus byte-identical copies of the scripts under test at their
    # repo-relative paths. The scripts find their project root from their own location, so anything they write
    # (logging\...) lands here instead of in the repo.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$Scripts
    )
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Set-Content -LiteralPath (Join-Path $Path 'CLAUDE.md') -Value 'fake project root for tests' -Encoding ascii
    foreach ($s in $Scripts) {
        $dst = Join-Path $Path $s
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $s) -Destination $dst -Force
    }
    $Path
}

function Invoke-ScriptIn {
    # Run a script file in a fresh child process of the given shell; return its exit code and merged output.
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string]$Script,
        [string[]]$ArgumentList = @()
    )
    $out = & $Exe -NoProfile -ExecutionPolicy Bypass -File $Script @ArgumentList 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out -join [Environment]::NewLine) }
}

function Get-TestNames {
    # Names that exercise path handling: spaces, brackets, a cp1252 character (e-acute) and characters outside
    # cp1252 (Cyrillic and CJK). Paths are relative to the test data folder.
    $eAcute = [string][char]0x00E9
    $cyrillic = -join [char[]](0x0434, 0x0430, 0x043D, 0x043D, 0x044B, 0x0435)
    $cjk = -join [char[]](0x65E5, 0x672C)
    $folderSpaces = "folder with spaces $eAcute"
    $topFiles = @('plain.txt', 'with spaces\file with spaces.txt', "caf$eAcute.txt", "$cyrillic-$cjk.txt", 'brackets [1].txt')
    [pscustomobject]@{
        TopFiles = $topFiles
        Folders  = @($folderSpaces, 'dir [x]')
        AllFiles = $topFiles + @("$folderSpaces\a.txt", "$folderSpaces\inner $cyrillic.txt", 'dir [x]\a.txt', "dir [x]\inner $cyrillic.txt")
    }
}

function New-TestTree {
    # Create every file from Get-TestNames under $Path, each with distinct content.
    param([Parameter(Mandatory)][string]$Path)
    foreach ($rel in (Get-TestNames).AllFiles) {
        $p = Join-Path $Path $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
        [IO.File]::WriteAllText($p, "original $rel", (New-Object Text.UTF8Encoding($false)))
    }
}

function Get-TreeHashes {
    # SHA-256 of each relative path under $Path, or 'MISSING'.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$RelFiles)
    $h = @{}
    foreach ($r in $RelFiles) {
        $p = Join-Path $Path $r
        $h[$r] = if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { 'MISSING' }
    }
    $h
}

function Set-TreeChanged {
    # Change every test file, then delete one inside the bracketed folder so a restore has to re-create it.
    param([Parameter(Mandatory)][string]$Path)
    foreach ($r in (Get-TestNames).AllFiles) {
        $p = Join-Path $Path $r
        if (Test-Path -LiteralPath $p) { Add-Content -LiteralPath $p -Value 'changed' }
    }
    Remove-Item -LiteralPath (Join-Path $Path 'dir [x]\a.txt') -ErrorAction SilentlyContinue
}
