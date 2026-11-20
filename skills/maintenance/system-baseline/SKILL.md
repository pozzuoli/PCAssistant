---
name: system-baseline
summary: Capture a read-only snapshot of system state (packages, services, scheduled jobs, settings) and diff snapshots over time.
triggers:
  - first-time setup (initial baseline)
  - "what changed on my system since …?"
  - before/after a big change (upgrade, cleanup, new software stack)
platforms: [linux, macos, bsd, windows]
scope: shared
tier: 0
needs_admin: false (some Windows items are more complete when elevated)
command: pca-baseline
scripts:
  posix: pca-baseline.sh
  windows: pca-baseline.ps1
version: 1.1
updated: 2026-11-20
---

# system-baseline

## Purpose
A cheap record of how the system looked at a point in time. Useful for reinstalling what was there, spotting drift, and checking what a change (or an OS update) really did.

## Usage
```
pca-baseline [label]          # capture → logging/baseline/YYYY-MM-DD_HHMM[_label]/
pca-baseline --list
pca-baseline --diff <a> <b>   # compare two captures by directory name
```

## What's captured (whatever applies to the OS)
- **System:** uname/os-release/sw_vers, disks, `df`, fstab, kernel cmdline and modules.
- **Packages:** apt manual and all dpkg, dnf user-installed, rpm, pacman explicit, zypper, apk world, xbps, brew leaves and casks, snap, flatpak, apt sources. On Windows: the uninstall registry, `winget export`, choco, scoop, AppX, Windows features.
- **Services and jobs:** systemd enabled units (system and user), failed units, timers, OpenRC, launchd, crontab. On Windows: services, scheduled tasks, startup items.
- **Settings:** `dconf dump /` (GNOME etc.) and macOS `defaults` for the global domain, Dock, and Finder. On Windows: firewall profiles, power plan, PATH.
- In config-type captures (dconf, cron, fstab, repo sources, defaults), `password=`/`token=`-style values and credentials embedded in URLs are redacted automatically. **No** network addresses, Wi-Fi details, or user lists are captured.

## Steps (for Claude)
1. Run `pca-baseline [label]`. It's Tier 0, so no approval is needed.
2. Record it in the journal (a CHANGELOG entry isn't needed, since nothing on the system changed).
3. To compare captures, run `pca-baseline --diff` and summarize the meaningful differences.

## Verification
Check that the new directory exists and holds the expected files for this OS.

## Rollback
Nothing to roll back: the skill is read-only. Captures can be deleted freely.

## Platform status
- POSIX: tested on Linux (Ubuntu/GNOME). The macOS/BSD branches are written but untested.
- Windows: tested on Windows 11 with Windows PowerShell 5.1 and PowerShell 7 (2026-11-20). CI: `tests/windows/pca-baseline.Tests.ps1`. Without elevation the optional-features list is skipped and fewer scheduled tasks are visible.

## Changelog
- 1.0 (2026-11-04): created.
- 1.1 (2026-11-20): Windows: `pkg-winget.json` is captured again. `winget export` used to target the file that the capture helper held open, so it failed with a sharing violation and the file was silently dropped. `--diff` reads captures as UTF-8, so a capture taken in one shell can be compared in the other without false differences. The script is ASCII-only so Windows PowerShell 5.1 reads it correctly.
