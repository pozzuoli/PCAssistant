# pca-backup.Tests.ps1 - Pester 5 round-trip tests for skills\maintenance\change-backup\pca-backup.ps1.
# -Shell picks the shell that runs the script under test (Windows PowerShell 5.1 or PowerShell 7); Pester itself
# runs in PowerShell 7. Files live on Pester's TestDrive. The registry tests create HKCU\Software\PCA-CI-<random>
# and delete it afterwards. The documented usage is in skills\maintenance\change-backup\SKILL.md.
param(
    [ValidateSet('powershell', 'pwsh')][string]$Shell = 'pwsh',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $AllFiles = (Get-TestNames).AllFiles
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Exe = Get-ShellExe $Shell
    $Rel = 'skills\maintenance\change-backup\pca-backup.ps1'
}

Describe "pca-backup: files and folders ($Shell)" {
    BeforeAll {
        $root = New-FakeRoot -Path (Join-Path $TestDrive 'root') -RepoRoot $RepoRoot -Scripts $Rel
        $Pb = Join-Path $root $Rel
        $Id = 'C-0001'
        $Data = Join-Path $TestDrive 'data'
        New-TestTree -Path $Data
        $Names = Get-TestNames
        $Targets = @(($Names.TopFiles + $Names.Folders) | ForEach-Object { Join-Path $Data $_ })
        $Original = Get-TreeHashes -Path $Data -RelFiles $Names.AllFiles
        $Backup = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList (@($Id) + $Targets)
        $Meta = Join-Path $root "logging\backups\$Id\METADATA"
    }

    It 'backup exits 0' {
        $Backup.ExitCode | Should -Be 0 -Because $Backup.Output
    }

    It 'records every backed-up item in METADATA, as valid UTF-8' {
        $Meta | Should -Exist -Because 'without METADATA, --list and --restore cannot see the backup'
        $text = [IO.File]::ReadAllText($Meta, (New-Object Text.UTF8Encoding($false, $true)))
        foreach ($t in $Targets) { $text.Contains($t) | Should -BeTrue -Because "METADATA should list $t" }
    }

    It '--list C-0001 (ID only, as documented) exits 0 and lists every item' {
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--list', $Id)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        # Count the listed items instead of matching every path: how a child prints non-ASCII text depends on the
        # console code page. The METADATA test above reads the file as UTF-8 and proves the exact paths.
        $items = @(($r.Output -split "`r?`n") | Where-Object { $_ -match '^(file|dir|reg)\t' })
        $items.Count | Should -Be $Targets.Count -Because $r.Output
        foreach ($t in ($Targets | Where-Object { $_ -notmatch '[^\x00-\x7F]' })) {
            $r.Output.Contains($t) | Should -BeTrue -Because "--list should show $t"
        }
    }

    It '--verify C-0001 (ID only, as documented) reports checksums OK' {
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--verify', $Id)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $r.Output | Should -Match 'checksums OK'
    }

    Context 'restore C-0001 with no paths (restores everything)' {
        BeforeAll {
            Set-TreeChanged -Path $Data
            $Restore = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', $Id)
            $After = Get-TreeHashes -Path $Data -RelFiles (Get-TestNames).AllFiles
        }
        It 'exits 0' {
            $Restore.ExitCode | Should -Be 0 -Because $Restore.Output
        }
        It 'restores <_>' -ForEach $AllFiles {
            $After[$_] | Should -Be $Original[$_] -Because "the restore should put $_ back"
        }
    }

    Context 'restore C-0001 with explicit paths' {
        BeforeAll {
            Set-TreeChanged -Path $Data
            $Restore = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList (@('--restore', $Id) + $Targets)
            $After = Get-TreeHashes -Path $Data -RelFiles (Get-TestNames).AllFiles
        }
        It 'exits 0' {
            $Restore.ExitCode | Should -Be 0 -Because $Restore.Output
        }
        It 'restores <_>' -ForEach $AllFiles {
            $After[$_] | Should -Be $Original[$_] -Because "the restore should put $_ back"
        }
    }
}

Describe "pca-backup: registry keys ($Shell)" {
    BeforeAll {
        $root = New-FakeRoot -Path (Join-Path $TestDrive 'regroot') -RepoRoot $RepoRoot -Scripts $Rel
        $Pb = Join-Path $root $Rel
        $Base = 'Software\PCA-CI-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        $Key = "HKCU\$Base\key"
        $KeyPs = "HKCU:\$Base\key"
        New-Item -Path $KeyPs -Force | Out-Null
        New-ItemProperty -Path $KeyPs -Name A -Value '1' -PropertyType String -Force | Out-Null
        $Backup = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('C-0001', '--reg', $Key)
    }
    AfterAll {
        Remove-Item -Path "HKCU:\$Base" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'backup exits 0' {
        $Backup.ExitCode | Should -Be 0 -Because $Backup.Output
    }

    It 'restore puts a changed value back' {
        Set-ItemProperty -Path $KeyPs -Name A -Value '2'
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0001', $Key)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        (Get-ItemProperty -Path $KeyPs).A | Should -Be '1'
    }

    It 'restore re-creates a deleted key' {
        Remove-Item -Path $KeyPs -Recurse -Force
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0001', $Key)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        Test-Path -Path $KeyPs | Should -BeTrue
        (Get-ItemProperty -Path $KeyPs).A | Should -Be '1' -Because 'the re-created key should get its backed-up value'
    }

    It 'backs up and restores two keys whose names differ only by a backslash and an underscore' {
        $k1 = "HKCU\$Base\coll\a_b"; $p1 = "HKCU:\$Base\coll\a_b"
        $k2 = "HKCU\$Base\coll\a\b"; $p2 = "HKCU:\$Base\coll\a\b"
        New-Item -Path $p1 -Force | Out-Null; New-ItemProperty -Path $p1 -Name V -Value 'one' -PropertyType String -Force | Out-Null
        New-Item -Path $p2 -Force | Out-Null; New-ItemProperty -Path $p2 -Name V -Value 'two' -PropertyType String -Force | Out-Null
        $b = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('C-0002', '--reg', $k1, $k2)
        $b.ExitCode | Should -Be 0 -Because $b.Output
        Set-ItemProperty -Path $p1 -Name V -Value 'changed'
        Set-ItemProperty -Path $p2 -Name V -Value 'changed'
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0002', $k1, $k2)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        (Get-ItemProperty -Path $p1).V | Should -Be 'one'
        (Get-ItemProperty -Path $p2).V | Should -Be 'two' -Because "$k2 must get its own backup, not share $k1's"
    }
}

if ($Shell -eq 'powershell') {
    Describe 'pca-backup: back up in PowerShell 7, restore in Windows PowerShell 5.1' {
        BeforeAll {
            $root = New-FakeRoot -Path (Join-Path $TestDrive 'crossroot') -RepoRoot $RepoRoot -Scripts $Rel
            $Pb = Join-Path $root $Rel
            $Data = Join-Path $TestDrive 'crossdata'
            New-TestTree -Path $Data
            $Top = (Get-TestNames).TopFiles
            $Targets = @($Top | ForEach-Object { Join-Path $Data $_ })
            $Original = Get-TreeHashes -Path $Data -RelFiles $Top
            $Backup = Invoke-ScriptIn -Exe (Get-ShellExe 'pwsh') -Script $Pb -ArgumentList (@('C-0001') + $Targets)
            foreach ($t in $Targets) { Add-Content -LiteralPath $t -Value 'changed' }
            $Restore = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList (@('--restore', 'C-0001') + $Targets)
            $After = Get-TreeHashes -Path $Data -RelFiles $Top
        }

        It 'backup in PowerShell 7 exits 0' {
            $Backup.ExitCode | Should -Be 0 -Because $Backup.Output
        }
        It 'restore in Windows PowerShell 5.1 exits 0' {
            $Restore.ExitCode | Should -Be 0 -Because $Restore.Output
        }
        It 'restores every file' {
            foreach ($t in $Top) { $After[$t] | Should -Be $Original[$t] -Because "the restore should put $t back" }
        }
    }
}
