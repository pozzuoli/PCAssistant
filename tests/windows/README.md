# Windows tests

Checks for the Windows scripts under `skills/`. The README promises Windows PowerShell 5.1 or newer, and the `pca-*` shims use PowerShell 7 when it is installed, so every check covers both shells. CI runs them on `windows-latest` (`.github/workflows/windows-powershell.yml`).

| Check | What it catches |
|---|---|
| `Invoke-Lint.ps1` | PSScriptAnalyzer over `skills/`. Error-severity findings and `PSUseBOMForUnicodeEncodedFile` fail the run; other warnings are only reported. `Write-Host` is allowed (these are console tools). |
| `Test-ParseParity.ps1` | Parses each script in Windows PowerShell 5.1 and in PowerShell 7. Fails on parse errors in either shell, when the two shells decode the file to different text, or when they find different functions in it. |
| `pca-backup.Tests.ps1` | Back up, change, `--list`, `--verify`, restore with and without paths, for names with spaces, brackets and non-ASCII characters (inside and outside code page 1252), folders, and HKCU registry keys. In the 5.1 run it also backs up in PowerShell 7 and restores in 5.1. |
| `pca-baseline.Tests.ps1` | A capture completes, writes the core files, and writes a valid `pkg-winget.json`. A stand-in `winget.cmd` is used, so this needs no winget and no network. |
| `scan.Tests.ps1` | `scan.ps1` runs to the end and prints the main sections. |

Not covered on purpose:
- Whether a restore should remove values or files added after the backup. Today it merges, and that is a design decision, not a test.
- `--reg` with the PowerShell drive form (`HKCU:\...`). The skill documents `HKCU\...`.
- Values `scan.ps1` and `pca-health.ps1` read from the machine (BitLocker, sudo, restore points and so on). They depend on the machine, not the code.

## Why BOM-less non-ASCII scripts break in 5.1
Windows PowerShell 5.1 reads a `.ps1` without a byte order mark using the system ANSI code page (1252 on en-US Windows), not UTF-8. The UTF-8 bytes of U+2014 (`E2 80 94`) then decode as three cp1252 characters. The last one is U+201D, which PowerShell accepts as a closing double quote, so a string can end early. Depending on how many such characters a file has, it either fails to parse or parses into different code. Keep `.ps1` files ASCII-only, or save them as UTF-8 with BOM. Read and write data files with an explicit `-Encoding`: the default differs between 5.1 (ANSI) and 7 (UTF-8).

## Run locally
From the repo root, in PowerShell 7 (`pwsh`). Install the modules once. `-SkipPublisherCheck` is needed because Windows ships an older, differently signed Pester 3.4.0:

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.23.0 -Scope CurrentUser
```

```powershell
Install-Module Pester -RequiredVersion 5.6.1 -Scope CurrentUser -Force -SkipPublisherCheck
```

Then:

```powershell
./tests/windows/Invoke-Lint.ps1
./tests/windows/Test-ParseParity.ps1
./tests/windows/Invoke-Tests.ps1 -Shell powershell
./tests/windows/Invoke-Tests.ps1 -Shell pwsh
```

The scripts here need PowerShell 7 to run. The shell under test is what `-Shell` picks.

What the tests touch:
- Files are created on Pester's TestDrive, a temp folder it deletes afterwards.
- The scripts under test run from a throwaway copy of the project root there, so nothing is written to this repo's `logging/` folder.
- The registry tests create `HKCU\Software\PCA-CI-<random>` and delete it at the end.
- `scan.ps1` and the pca-baseline capture only read system state. The baseline test's winget calls go to the stand-in.
- `Invoke-Tests.ps1` sets the console output encoding to UTF-8 for the run and restores it afterwards.
- Nothing needs elevation.

Every file in this folder is ASCII-only. Non-ASCII test names are built from `[char]` codes.
