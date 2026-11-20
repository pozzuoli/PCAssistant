<#
scan.ps1 - READ-ONLY system scan for PC Assistant first-time setup (Windows 10/11, Windows Server 2016+).
Prints a markdown report to stdout. Changes nothing. Every probe is optional; failures are skipped.
Works in Windows PowerShell 5.1 and PowerShell 7+.
Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File scan.ps1 > scan.md
#>
$ErrorActionPreference = 'SilentlyContinue'
function KV($k, $v) { if ($null -ne $v -and "$v".Trim() -ne '') { "- **${k}:** $v" } }
function Sec($t) { ''; "## $t" }
function Has($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Ver($c) { try { $l = "$(& $c --version 2>&1 | Select-Object -First 1)"; $l.Substring(0, [Math]::Min(80, $l.Length)) } catch { 'present' } }

"# System scan"
''
KV 'Scanned' (Get-Date -Format 'yyyy-MM-dd HH:mm K')
KV 'Scanner' 'scan.ps1'

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

Sec 'Operating system'
KV 'OS' $os.Caption
KV 'Version' "$($cv.DisplayVersion) (build $($os.BuildNumber).$($cv.UBR))"
KV 'Edition ID' $cv.EditionID
KV 'Installation type' $cv.InstallationType   # Client / Server / Server Core
KV 'Product type' (@{1 = 'Workstation'; 2 = 'Domain controller'; 3 = 'Server' }[[int]$os.ProductType])
KV 'Architecture' $os.OSArchitecture
KV 'Hostname' $env:COMPUTERNAME
KV 'Domain / workgroup' $(if ($cs.PartOfDomain) { "domain: $($cs.Domain)" } else { "workgroup: $($cs.Workgroup)" })
KV 'Last boot' $os.LastBootUpTime
KV 'Virtual machine' $(if ($cs.Model -match 'Virtual|VMware|KVM|QEMU|VirtualBox|HVM') { "yes ($($cs.Model))" } else { 'no' })

Sec 'User & shell'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
KV 'User' $id.Name
KV 'Shell elevated now' $(if ($isAdmin) { 'YES (Administrator)' } else { 'no' })
$admins = try { (Get-LocalGroupMember -SID 'S-1-5-32-544' | Select-Object -ExpandProperty Name) -join ', ' } catch { $null }
KV 'Local Administrators' $admins
KV 'UAC enabled' $(if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA -eq 1) { 'yes' } else { 'no' })
KV 'PowerShell' "$($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
KV 'PowerShell 7 (pwsh)' $(if (Has pwsh) { 'installed' } else { 'not installed' })
KV 'Execution policy' ((Get-ExecutionPolicy -List | Where-Object { $_.ExecutionPolicy -ne 'Undefined' } | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join ', ')
KV 'Profile folder' $env:USERPROFILE
KV '%USERPROFILE%\.pca\bin on PATH' $(if (($env:PATH -split ';') -contains (Join-Path $env:USERPROFILE '.pca\bin')) { 'yes' } else { 'no' })

Sec 'Hardware'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
KV 'CPU' "$($cpu.Name.Trim()) - $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"
KV 'RAM' ('{0:N1} GiB' -f ($cs.TotalPhysicalMemory / 1GB))
KV 'GPU' ((Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join '; ')
KV 'Model' "$($cs.Manufacturer) $($cs.Model)"
KV 'Battery' $(if (Get-CimInstance Win32_Battery) { 'present (laptop)' } else { 'none' })
KV 'Firmware' $(try { if (Confirm-SecureBootUEFI) { 'UEFI, Secure Boot on' } else { 'UEFI, Secure Boot off' } } catch { 'BIOS/legacy or unknown (needs elevation to check)' })
KV 'Page file' ((Get-CimInstance Win32_PageFileUsage | ForEach-Object { "$($_.Name) ($($_.AllocatedBaseSize) MB)" }) -join '; ')

Sec 'Storage'
'```'
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    '{0}  {1,-6} {2,8:N1} GiB total  {3,8:N1} GiB free  {4}' -f $_.DeviceID, $_.FileSystem, ($_.Size / 1GB), ($_.FreeSpace / 1GB), $_.VolumeName
}
'```'
KV 'Physical disks' ((Get-PhysicalDisk | ForEach-Object { "$($_.FriendlyName) $($_.MediaType) $([Math]::Round($_.Size/1GB))GB" }) -join '; ')
$bl = try { (Get-BitLockerVolume -MountPoint $env:SystemDrive).ProtectionStatus } catch { $null }
KV 'BitLocker (system drive)' $(if ($bl) { $bl } else { 'unknown (needs elevation) or not available' })

Sec 'Package managers'
$pm = @('winget', 'choco', 'scoop') | Where-Object { Has $_ }
KV 'Found' $(if ($pm) { $pm -join ' ' } else { 'none' })
KV 'Windows Store / AppX' $(if (Get-Command Get-AppxPackage) { 'available' })
KV 'Windows features cmdlets' $(if (Has Get-WindowsFeature) { 'Get-WindowsFeature (Server)' } elseif (Has Get-WindowsOptionalFeature) { 'Get-WindowsOptionalFeature' })
KV 'WSL' $(if (Has wsl) { (wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' }) -join ', ' })

Sec 'Elevation'
KV 'Method' 'UAC - run an elevated PowerShell/Terminal ("Run as administrator")'
KV 'sudo for Windows' $(if (Has sudo) { 'present' } else { 'not present' })

Sec 'Rollback / snapshot tools'
$srKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
KV 'System Restore' $(if ($cv.InstallationType -match 'Server') { 'not available on Server editions' } elseif ($srKey.RPSessionInterval -eq 1) { 'enabled' } else { 'disabled or unknown' })
KV 'Restore points' $(try { (Get-ComputerRestorePoint | Measure-Object).Count } catch { 'needs elevation to list' })
KV 'Windows Server Backup' $(if (Has wbadmin) { 'wbadmin present' })
KV 'File History' $(if (Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory") { 'configured at some point' })
KV 'VSS (vssadmin)' $(if (Has vssadmin) { 'present' })

Sec 'Security'
$mp = Get-MpComputerStatus
KV 'Defender' $(if ($mp) { "AV enabled: $($mp.AntivirusEnabled), real-time: $($mp.RealTimeProtectionEnabled)" })
KV 'Firewall profiles' ((Get-NetFirewallProfile | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ', ')

Sec 'Tools'
foreach ($t in 'git', 'gh', 'python', 'py', 'node', 'curl.exe', 'tar') { if (Has $t) { KV $t (Ver $t) } }
if (Has git) { KV 'git identity' $(if (git config --global user.name) { 'configured (global)' } else { 'not configured' }) }

''
'_End of scan._'
