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

Describe "pca-backup: registry backups written by the previous version in Windows PowerShell 5.1 ($Shell)" {
    BeforeAll {
        # The previous version, run in 5.1, wrote METADATA and SHA256SUMS in the ANSI code page and named registry
        # backups without a hash suffix. Build such a backup set by hand: one key with a non-ASCII name, one without.
        $root = New-FakeRoot -Path (Join-Path $TestDrive 'legacyroot') -RepoRoot $RepoRoot -Scripts $Rel
        $Pb = Join-Path $root $Rel
        $Base = 'Software\PCA-CI-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        $KeyA = "HKCU\$Base\caf" + [char]0x00E9; $PsA = "HKCU:\$Base\caf" + [char]0x00E9
        $KeyB = "HKCU\$Base\plain"; $PsB = "HKCU:\$Base\plain"
        foreach ($p in $PsA, $PsB) {
            New-Item -Path $p -Force | Out-Null
            New-ItemProperty -Path $p -Name V -Value 'original' -PropertyType String -Force | Out-Null
        }
        $Dest = Join-Path $root 'logging\backups\C-0001'
        $RegDir = Join-Path $Dest 'registry'
        New-Item -ItemType Directory -Force -Path $RegDir | Out-Null
        $ansi = [Text.Encoding]::GetEncoding([int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP)
        $meta = @(); $sums = @()
        foreach ($k in $KeyA, $KeyB) {
            $name = ($k -replace '[\\/:*?"<>|]', '_') + '.reg'
            & reg.exe export $k (Join-Path $RegDir $name) /y | Out-Null
            $meta += "reg`t-`t$k"
            $sums += "$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $RegDir $name)).Hash.ToLower())  \registry\$name"
        }
        [IO.File]::WriteAllText((Join-Path $Dest 'METADATA'), (($meta -join "`r`n") + "`r`n"), $ansi)
        [IO.File]::WriteAllText((Join-Path $Dest 'SHA256SUMS'), (($sums -join "`r`n") + "`r`n"), $ansi)
        $LegacyA = Join-Path $RegDir (($KeyA -replace '[\\/:*?"<>|]', '_') + '.reg')
    }
    AfterAll {
        Remove-Item -Path "HKCU:\$Base" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'verify reports checksums OK' {
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--verify', 'C-0001')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $r.Output | Should -Match 'checksums OK'
    }

    It 'restore with no paths brings both keys back' {
        foreach ($p in $PsA, $PsB) { Set-ItemProperty -Path $p -Name V -Value 'changed' }
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0001')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        (Get-ItemProperty -Path $PsA).V | Should -Be 'original'
        (Get-ItemProperty -Path $PsB).V | Should -Be 'original'
    }

    It 'a missing backup file does not block restoring another named key, and verify reports it' {
        Set-ItemProperty -Path $PsB -Name V -Value 'changed'
        Remove-Item -LiteralPath $LegacyA
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0001', $KeyB)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        (Get-ItemProperty -Path $PsB).V | Should -Be 'original'
        $v = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--verify', 'C-0001')
        $v.ExitCode | Should -Be 1 -Because $v.Output
        $v.Output | Should -Match 'MISSING'
    }
}

Describe "pca-backup: restore refuses damaged or ambiguous backups ($Shell)" {
    BeforeAll {
        $root = New-FakeRoot -Path (Join-Path $TestDrive 'safetyroot') -RepoRoot $RepoRoot -Scripts $Rel
        $Pb = Join-Path $root $Rel
        $Backups = Join-Path $root 'logging\backups'
        $Data = Join-Path $TestDrive 'safetydata'
        New-Item -ItemType Directory -Force -Path (Join-Path $Data 'app') | Out-Null
        $Base = 'Software\PCA-CI-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        function New-TestKey([string]$PsPath, [string]$Value) {
            New-Item -Path $PsPath -Force | Out-Null
            New-ItemProperty -Path $PsPath -Name V -Value $Value -PropertyType String -Force | Out-Null
        }
    }
    AfterAll {
        Remove-Item -Path "HKCU:\$Base" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'does not restore a changed folder backup (folder given with a trailing backslash)' {
        $app = Join-Path $Data 'app'
        Set-Content -LiteralPath (Join-Path $app 'x.txt') -Value 'original'
        $b = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('C-0001', "$app\")
        $b.ExitCode | Should -Be 0 -Because $b.Output
        Get-ChildItem -LiteralPath (Join-Path $Backups 'C-0001') -Recurse -File -Filter 'x.txt' | ForEach-Object { Set-Content -LiteralPath $_.FullName -Value 'tampered' }
        Set-Content -LiteralPath (Join-Path $app 'x.txt') -Value 'changed'
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0001', "$app\")
        $r.ExitCode | Should -Be 1 -Because $r.Output
        Get-Content -LiteralPath (Join-Path $app 'x.txt') | Should -Be 'changed' -Because 'a backup that fails its checksum must not be restored'
    }

    It 'restores nothing when one requested registry backup file is missing' {
        $f = Join-Path $Data 'a.txt'
        Set-Content -LiteralPath $f -Value 'original'
        New-TestKey "HKCU:\$Base\k" 'original'
        $b1 = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('C-0002', $f)
        $b2 = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('C-0002', '--reg', "HKCU\$Base\k")
        $b1.ExitCode | Should -Be 0 -Because $b1.Output
        $b2.ExitCode | Should -Be 0 -Because $b2.Output
        Set-Content -LiteralPath $f -Value 'changed'
        Get-ChildItem -LiteralPath (Join-Path $Backups 'C-0002\registry') -File | Remove-Item
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0002', $f, "HKCU\$Base\k")
        $r.ExitCode | Should -Be 1 -Because $r.Output
        Get-Content -LiteralPath $f | Should -Be 'changed' -Because 'nothing may be restored when part of the request cannot be'
    }

    It "does not import another key's old-style backup when the key's own file is missing" {
        # The previous version named the backup of ...\coll\a_b exactly as it would have named ...\coll\a\b.
        $k1 = "HKCU\$Base\coll\a_b"; $k2 = "HKCU\$Base\coll\a\b"
        New-TestKey "HKCU:\$Base\coll\a_b" 'a_b value'
        New-TestKey "HKCU:\$Base\coll\a\b" 'original'
        $reg = Join-Path $Backups 'C-0003\registry'
        New-Item -ItemType Directory -Force -Path $reg | Out-Null
        $legacy = ($k1 -replace '[\\/:*?"<>|]', '_') + '.reg'
        & reg.exe export $k1 (Join-Path $reg $legacy) /y | Out-Null
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $reg $legacy)).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $Backups 'C-0003\METADATA') -Value "reg`t-`t$k1" -Encoding ascii
        Set-Content -LiteralPath (Join-Path $Backups 'C-0003\SHA256SUMS') -Value "$hash  \registry\$legacy" -Encoding ascii
        $b = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('C-0003', '--reg', $k2)
        $b.ExitCode | Should -Be 0 -Because $b.Output
        Set-ItemProperty -Path "HKCU:\$Base\coll\a\b" -Name V -Value 'changed'
        Get-ChildItem -LiteralPath $reg -File | Where-Object Name -match '-[0-9a-f]{8}\.reg$' | Remove-Item
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0003', $k2)
        $r.ExitCode | Should -Be 1 -Because $r.Output
        (Get-ItemProperty -Path "HKCU:\$Base\coll\a\b").V | Should -Be 'changed'
    }

    It 'checks the key named inside a registry backup file before importing it' {
        # METADATA lists ...\x\b, but the only file is the old-style backup of ...\x_b (same old name), with a checksum.
        $k1 = "HKCU\$Base\x_b"; $k2 = "HKCU\$Base\x\b"
        New-TestKey "HKCU:\$Base\x_b" 'x_b value'
        New-TestKey "HKCU:\$Base\x\b" 'changed'
        $reg = Join-Path $Backups 'C-0004\registry'
        New-Item -ItemType Directory -Force -Path $reg | Out-Null
        $legacy = ($k1 -replace '[\\/:*?"<>|]', '_') + '.reg'
        & reg.exe export $k1 (Join-Path $reg $legacy) /y | Out-Null
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $reg $legacy)).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $Backups 'C-0004\METADATA') -Value @("reg`t-`t$k1", "reg`t-`t$k2") -Encoding ascii
        Set-Content -LiteralPath (Join-Path $Backups 'C-0004\SHA256SUMS') -Value "$hash  \registry\$legacy" -Encoding ascii
        $r = Invoke-ScriptIn -Exe $Exe -Script $Pb -ArgumentList @('--restore', 'C-0004', $k2)
        $r.ExitCode | Should -Be 1 -Because $r.Output
        $r.Output | Should -Match 'different key'
        (Get-ItemProperty -Path "HKCU:\$Base\x\b").V | Should -Be 'changed'
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
