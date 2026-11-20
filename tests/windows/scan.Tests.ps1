# scan.Tests.ps1 - Pester 5 smoke test for skills\setup\first-time-setup\scan.ps1 (read-only, writes nothing).
# -Shell picks the shell that runs it; first-time setup documents running it with Windows PowerShell 5.1.
param(
    [ValidateSet('powershell', 'pwsh')][string]$Shell = 'pwsh',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Exe = Get-ShellExe $Shell
}

Describe "scan.ps1: smoke run ($Shell)" {
    BeforeAll {
        $Run = Invoke-ScriptIn -Exe $Exe -Script (Join-Path $RepoRoot 'skills\setup\first-time-setup\scan.ps1')
        $Head = (($Run.Output -split "`r?`n") | Select-Object -First 12) -join [Environment]::NewLine
    }

    It 'exits 0' {
        $Run.ExitCode | Should -Be 0 -Because $Head
    }

    It 'prints the whole report, from the title to the end marker' {
        $Run.Output | Should -Match '(?m)^# System scan' -Because $Head
        $Run.Output | Should -Match '_End of scan\._' -Because $Head
    }

    It 'prints the operating system and storage sections' {
        $Run.Output | Should -Match '(?m)^## Operating system'
        $Run.Output | Should -Match '(?m)^## Storage'
    }
}
