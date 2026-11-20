# pca-baseline.Tests.ps1 - Pester 5 tests for skills\maintenance\system-baseline\pca-baseline.ps1.
# -Shell picks the shell that runs the script under test. The script runs from a throwaway project root on
# Pester's TestDrive, so its capture lands there and not in the repo's logging\ folder. A stand-in winget.cmd is put
# first on PATH, so the winget part is deterministic, works offline and never touches the real winget.
param(
    [ValidateSet('powershell', 'pwsh')][string]$Shell = 'pwsh',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Exe = Get-ShellExe $Shell
    $Rel = 'skills\maintenance\system-baseline\pca-baseline.ps1'
}

Describe "pca-baseline: capture ($Shell)" {
    BeforeAll {
        # Stand-in for winget: `winget export -o <file> ...` writes a minimal export file, anything else does nothing.
        $bin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        Set-Content -LiteralPath (Join-Path $bin 'winget.cmd') -Encoding ascii -Value @(
            '@echo off'
            'if /i "%~1"=="export" (echo {"Sources":[]}> "%~3")'
            'exit /b %ERRORLEVEL%'
        )
        $OldPath = $env:PATH
        $env:PATH = "$bin;$env:PATH"

        $root = New-FakeRoot -Path (Join-Path $TestDrive 'root') -RepoRoot $RepoRoot -Scripts $Rel
        $Run = Invoke-ScriptIn -Exe $Exe -Script (Join-Path $root $Rel) -ArgumentList @('ci')
        $Dir = Get-ChildItem -LiteralPath (Join-Path $root 'logging\baseline') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    AfterAll {
        $env:PATH = $OldPath
    }

    It 'exits 0 and creates a capture folder' {
        $Run.ExitCode | Should -Be 0 -Because $Run.Output
        $Dir | Should -Not -BeNullOrEmpty
    }

    It 'captures <_>' -ForEach @('system.txt', 'services.txt', 'pkg-installed-programs.txt') {
        Join-Path $Dir.FullName $_ | Should -Exist
    }

    It 'captures the winget package list as pkg-winget.json' {
        $f = Join-Path $Dir.FullName 'pkg-winget.json'
        $f | Should -Exist -Because 'pca-baseline exports the winget package list when winget is present'
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        $j.PSObject.Properties.Name | Should -Contain 'Sources'
    }
}
