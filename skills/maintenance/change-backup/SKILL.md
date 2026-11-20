---
name: change-backup
summary: Back up and restore files, folders, and Windows registry keys, tied to a change ID.
triggers:
  - "before editing any config file" (mandatory: CLAUDE.md §4.1)
  - "undo / roll back change C-XXXX"
  - "what did change C-XXXX back up?"
platforms: [linux, macos, bsd, windows]
scope: shared
tier: 1
needs_admin: only when the file or key requires it
command: pca-backup
scripts:
  posix: pca-backup.sh
  windows: pca-backup.ps1
version: 1.1
updated: 2026-11-20
---

# change-backup

## Purpose
Makes "backup before edit" one consistent command, so every change can be undone exactly. Backups live under the change's ID, which links each one to its CHANGELOG entry.

## Usage
```
pca-backup <ID> <path>...                 # back up before change <ID>
pca-backup <ID> --private <path>...       # file contains secrets → logging/backups-private/ (never committed)
pca-backup <ID> --reg <key>...            # Windows only: reg export (e.g. HKCU\Software\Foo)
pca-backup --list <ID>                    # what <ID> backed up (original mode/owner or ACL)
pca-backup --verify <ID>                  # check SHA-256 checksums
pca-backup --restore <ID> [path...]       # restore everything, or only the listed paths
```
- Storage: `logging/backups/<ID>/<absolute path>`. Unix directories are stored as `<path>.tar` so owners and permissions survive. On Windows the path is `<ID>\C\Windows\...`, and registry keys go in `<ID>\registry\*.reg`.
- `METADATA` records the original mode/owner/group (Unix) or ACL SDDL (Windows). `SHA256SUMS` holds the hashes.
- Backing up the same path twice under one ID keeps the **first** (original) copy.
- Unix: if the current user can't read or write the file, the script uses `sudo -n`. When elevation isn't cached, it fails with a clear message instead of prompting. Copies are re-owned to the user so git can read them.
- Windows: run from an elevated shell when backing up or restoring protected files or HKLM.

## Steps (for Claude)
1. Reserve the next change ID from `logging/CHANGELOG.md`.
2. `pca-backup <ID> <every file you will modify>`. Use `--private` if any of them hold secrets (credentials, Wi-Fi PSKs, tokens, keys).
3. Make the change. Record the backup path in the CHANGELOG entry.
4. **Undoing a change:** reserve a new ID, back up the *current* state first (`pca-backup <NEW-ID> <files>`), then `pca-backup --restore <OLD-ID> [files]`. Log the revert and mark the old entry `reverted by <NEW-ID>`.

## Verification
`pca-backup --verify <ID>` after backing up. After a restore, diff the restored file against its backup, or check that the service or setting behaves as it did before.

## Rollback
Backups are additive. Deleting `logging/backups/<ID>/` removes them (never needed in normal use).

## Platform status
- POSIX (`pca-backup.sh`): tested on Linux (GNU coreutils). Written to also work on macOS/BSD (`stat -f` fallback, `shasum`).
- Windows (`pca-backup.ps1`): tested on Windows 11 with Windows PowerShell 5.1 and PowerShell 7 (2026-11-20), including names with spaces, brackets and non-ASCII characters, folders, HKCU keys, and a backup made in 7 restored in 5.1. CI: `tests/windows/pca-backup.Tests.ps1`. A registry restore merges into the key (values added after the backup stay), and a folder restore keeps files added after the backup.

## Changelog
- 1.0 (2026-11-04): created.
- 1.1 (2026-11-20): Windows fixes.
  - The script is ASCII-only, so it works in Windows PowerShell 5.1. Before, 5.1 lost the verify and restore functions and never recorded file backups.
  - `--list`, `--verify` and `--restore` work with only an ID.
  - METADATA and SHA256SUMS are written as UTF-8 in both shells. Lines that an older version wrote in the ANSI code page (5.1) are still read correctly.
  - Restoring a folder whose name contains `[` or `]` works.
  - Registry backup file names include a short hash of the key, so keys such as `...\a_b` and `...\a\b` no longer share one file. Restores still find backups made with the old names.
  - Before restoring anything, `--restore` checks every selected item: its files match their checksums, it has a checksum at all, and a registry backup file holds that same key. If any check fails, nothing is restored. Problems are reported per file (`MISSING`, `MISMATCH`, `UNREADABLE`, `NO CHECKSUM`) instead of stopping at the first one. Naming items restores just those, so one broken entry no longer blocks the rest of a change ID.
  - A requested path matches its METADATA entry with or without a trailing `\`.
