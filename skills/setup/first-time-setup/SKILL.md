---
name: first-time-setup
summary: Onboard a new machine/user. Read-only scan, preference questionnaire, then generate the profile, logs, baseline, commands, and (with approval) rollback tools. Also re-scan mode.
triggers:
  - "First time setup" / "set me up" / "get started"
  - profile/SYSTEM.md or profile/PREFERENCES.md missing
  - "re-scan my system" / "refresh my system profile" (re-scan mode)
platforms: [linux, macos, bsd, windows, windows-server, other]
scope: shared
tier: 2
needs_admin: only for installing/configuring rollback tools
command: none
scripts:
  posix: scan.sh, install-commands.sh
  windows: scan.ps1, install-commands.ps1
version: 1.2
updated: 2026-11-20
---

# first-time-setup

Gets this tool working on a machine it has never seen. **Assume nothing about the system.** Detect it, then adapt. The finished state is the same on every machine: `profile/SYSTEM.md` and `profile/PREFERENCES.md` filled in, `logging/` initialized, `pca-*` commands installed, a baseline recorded, the rollback tools the user chose set up, and everything logged.

Use the AskUserQuestion tool for the questionnaire if it's available (it is in Claude Code). Otherwise ask in plain text, numbered, with a recommended option for each question.

## Mode: re-scan
If the profile already exists and the user wants a refresh: run step 2, compare the results with `profile/SYSTEM.md`, update only what changed, write a journal entry listing the differences, and stop. **Do not** re-ask the questionnaire unless the user wants to.

If the profile already exists and the user says "First time setup", ask first: re-scan only, or full re-setup? A full re-setup backs up the existing profile files first (`pca-backup` isn't installed yet on a fresh copy, so copy them to `logging/backups/<ID>/profile/`).

## Step 1: Orient and check prerequisites (Tier 0)
1. Tell the user what's about to happen: a read-only scan, roughly 8 short questions, then setup. Nothing changes on their system without approval.
2. Detect the platform from your environment info and a quick probe (`uname -s`; on Windows `$PSVersionTable` / `$env:OS`).
3. Check for:
   - **git**: needed for updates and history. If it's missing, recommend installing it later, using the native package manager.
   - **a shell for the scripts**: POSIX `sh` on Unix. Windows PowerShell 5.1+ (always present on Windows 10/11/Server 2016+).
   - **gh** (GitHub CLI): only needed if they want a private backup repo.
4. Confirm the project folder is writable and note its absolute path.

## Step 2: Read-only scan (Tier 0)
- Unix-like: `sh skills/setup/first-time-setup/scan.sh`
- Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File skills\setup\first-time-setup\scan.ps1`
- **Other or unusual OS:** if neither script fits or a section comes back thin, probe by hand with what the system offers (`uname`, `/etc/*release`, `sysctl`, `ps`, `mount`, `df`, `which <pm>`…). Note the gaps rather than guessing.

Keep the raw output; step 5 saves it as `scan.md` in the setup baseline folder. Then give the user a 4–6 line summary: OS, hardware, package manager(s), filesystem, available elevation, snapshot capability.

## Step 3: Questionnaire
Ask in 2 rounds of at most 4 questions. Adapt the options to what the scan found, mark a recommended option, and put it first.

**Round 1**
1. **Autonomy.**
   - *Tiered* (recommended): read-only work is free. User-level changes that are easy to undo: do them, then report. Admin, destructive, or hard-to-undo changes: ask first.
   - *Ask for every change*.
   - *Broad autonomy* (ask only for destructive actions).
2. **Elevation method.** Never ask for passwords.
   - Linux/BSD/macOS:
     - *Timed sudo cache* (the user runs `sudo -v` when asked). **Only offer this when the sudo is classic sudo** (`sudo -V` prints "Sudo version"), and it may need the global-timestamp drop-in (see step 6). **sudo-rs** (`sudo -V` prints "sudo-rs"; the default on Ubuntu 25.10+) caches per terminal and has no global option, so this choice doesn't work there.
     - *User runs admin commands* (Claude prepares them).
     - *Scoped passwordless sudo* for a vetted command list.
     - *Full passwordless sudo* (warn: weak security).
     - Use `doas` instead if that's the tool present.
   - Windows:
     - *Launch VS Code / the terminal "as Administrator"* for admin sessions.
     - *User runs admin commands* in their own elevated PowerShell.
     - *sudo for Windows* (Windows 11 24H2+, if enabled).
3. **Package policy.**
   - *Native package manager first, then decide case by case* (recommended).
   - *Native first, then <the most relevant secondary source found: flatpak / snap / brew cask / winget→scoop>*.
   - *Always case by case*.
   - Rule in every case: no new third-party repos without approval.
4. **Communication style.**
   - *Concise, with the why* (recommended).
   - *Teach me* (more explanation).
   - *Minimal*.

**Round 2**

5. **Rollback stack** (multi-select). Offer what fits this OS. File backups via `pca-backup` are always on.
   - Linux:
     - *etckeeper* (git history for `/etc`; supports apt, dnf, pacman, zypper).
     - *System snapshots*: Timeshift (rsync mode on ext4/xfs, btrfs mode on Ubuntu-style btrfs layouts) or Snapper (btrfs, e.g. on openSUSE/Fedora).
   - macOS: *Time Machine local snapshots* before risky changes (`tmutil localsnapshot`; needs Time Machine set up). Recommend that they configure Time Machine if it isn't.
   - Windows client: *System Restore* (turn it on for the system drive with a max usage %, and make a restore point before risky changes). Registry exports always happen through `pca-backup --reg`.
   - Windows Server (no System Restore): *Windows Server Backup* (`wbadmin`, the feature may need installing), *VSS shadow copies*, and *hypervisor snapshots* if it's a VM (the user takes those).
   - Other OS: whatever exists (ZFS/btrfs snapshots, `/etc` in git by hand). Otherwise, file backups only.
6. **Snapshot schedule** (only if a snapshot tool was picked).
   - *On-demand plus a light schedule* (recommended): e.g. 2 daily and 1 weekly.
   - *On-demand only*.
   - *Heavier* (daily, weekly, monthly).
   - Windows note: by default it allows at most one restore point per 24 hours. Mention this.
7. **Retention.**
   - *Keep forever* (recommended).
   - *Prune backups older than 90 days*.
8. **Back up this folder** (their logs and profile) **to a private repo?**
   - *Private GitHub repo, auto-push after each task*.
   - *Private repo, ask before each push*.
   - *Private repo, push at session end*.
   - *Local only* (no remote).
   - Note that in the shared tool, their personal files are git-ignored by default and never go to the upstream repo.

Ask a follow-up only if an answer needs a detail (e.g. which commands go on a scoped sudo list).

## Step 4: Write the profile and logs (Tier 1, inside the project)
1. Make `profile/SYSTEM.md` from `templates/SYSTEM.template.md`, filled in from the scan. Delete any template lines that don't apply. Never leave `{{…}}` placeholders behind.
2. Make `profile/PREFERENCES.md` from `templates/PREFERENCES.template.md`, filled in from the answers. Standing duties come from question 8 (e.g. "after each task, commit and push this folder to the private repo").
3. Create `logging/CHANGELOG.md` from `logging/templates/CHANGELOG.template.md`, and `logging/journal/<YYYY-MM>.md` from `journal.template.md`. Create `logging/backups/`, plus `logging/backups-private/` with mode 700 (Windows: restrict to the user).
4. **C-0001:** "First-time setup: profile and logging initialized". Undo: delete `profile/SYSTEM.md`, `profile/PREFERENCES.md`, and the logging files.

## Step 5: Install commands and take a baseline (Tier 1)
1. Install the commands:
   - Unix: `sh skills/setup/first-time-setup/install-commands.sh [bin-dir]`. The default is `~/.local/bin`. If it isn't on PATH, pick a directory from PATH that the user owns, or ask to add it to their shell profile (back up the profile first).
   - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File skills\setup\first-time-setup\install-commands.ps1` (adds `%USERPROFILE%\.pca\bin` to the user's PATH).
2. Check that `pca-backup --help` and `pca-baseline --help` both run. In the current session you may need the full path.
3. Run `pca-baseline setup` (Tier 0), then save the step 2 scan output as `scan.md` in the folder it creates (`logging/baseline/<stamp>_setup/`).
4. **C-0002:** "Installed pca-* commands" (list them). Undo: remove the symlinks or shims, and the PATH entry if one was added.

## Step 6: Elevation and rollback tools (Tier 2: approval per step)
Each step: explain it, get approval, reserve an ID, back up anything you'll edit, apply, verify, log.

- **Identify the sudo implementation first:** run `sudo -V | head -1`. It shows either classic sudo ("Sudo version …") or **sudo-rs** ("sudo-rs …"). Also check whether `doas` is in use.
- **Timed sudo cache (classic sudo only):** ask the user to run `sudo -v`, then test `sudo -n true`. It usually fails, because the default per-terminal timestamp doesn't reach Claude's shell. If so, offer a drop-in the **user** installs: `/etc/sudoers.d/pca-timestamp` containing `Defaults:<user> timestamp_type=global`. Trade-off: for about 15 minutes after `sudo -v`, any process the user runs can use sudo.
- **sudo-rs:** there's no global timestamp, so offer scoped passwordless sudo, the user running admin commands, or switching to classic sudo (Ubuntu: `sudo update-alternatives --config sudo`, if `sudo.ws` is installed).
- **Scoped passwordless sudo:** write `profile/sudoers-pca` with `Cmnd_Alias` lists of **absolute paths**, then validate it with `/usr/sbin/visudo -cf` (or `visudo-rs -cf`). On distros where coreutils binaries are symlinks (e.g. Ubuntu 26.04's uutils: `/usr/bin/cp → gnucp`), list **both the symlink and its target** (`readlink -f`). Tell the user plainly that package managers, `systemctl`, and `cp`/`chown`-type commands are root-equivalent, so the list limits the scope of normal use but isn't a security boundary. The **user** installs it in their own terminal:
  `sudo visudo -cf <file> && sudo install -m 0440 -o root -g root <file> /etc/sudoers.d/pca && sudo visudo -c`
  Then verify with `sudo -n true` and a couple of listed commands, and confirm an unlisted one (e.g. `sudo -n whoami`) is still refused.
- In every case: validate any sudoers file before it's installed, log the change, and record the method in SYSTEM.md → Elevation.
- **etckeeper:** install it with the native package manager. It makes its own first commit. Verify with `sudo etckeeper vcs log -1`.
- **Timeshift / Snapper:** install, configure (rsync or btrfs mode, the schedule from question 6), take the first snapshot, verify it in the list. Timeshift's rsync mode excludes home folders by default. Say so.
- **Time Machine:** check `tmutil destinationinfo`. If no destination is configured, explain how to set one up (the user does it in System Settings). Test `tmutil localsnapshot`.
- **Windows System Restore:** in an elevated shell, `Enable-ComputerRestore -Drive "C:\"`, set a max usage (`vssadmin resize shadowstorage …`, or leave the default), then `Checkpoint-Computer -Description "PCA setup" -RestorePointType MODIFY_SETTINGS`. Verify with `Get-ComputerRestorePoint`.
- **Windows Server Backup:** check whether the feature is installed (`Get-WindowsFeature Windows-Server-Backup`). Install it only with approval. Agree on a target volume before any backup.
- Update SYSTEM.md → *Rollback & snapshot tools* with the status of each tool and its log ID.

## Step 7: Back up the folder (if chosen in question 8)
- If the folder is a clone of the shared tool (`git remote -v` shows the upstream):
  - Rename that remote `upstream`.
  - Delete the block between `# >>> PCA-PERSONAL-DATA` and `# <<< PCA-PERSONAL-DATA` in `.gitignore`, so personal files get tracked. **Keep `logging/backups-private/` ignored.**
  - Create the private repo (`gh repo create <name> --private --source . --remote origin`), commit, and push.
  - Future tool updates come from `git pull upstream main`.
- If the folder isn't a git repo: `git init`, add a `.gitignore` containing `logging/backups-private/`, commit, create the private repo, push.
- **Local only:** if the folder is a clone, leave it as it is (personal files stay ignored, so `git pull` updates stay clean). If it isn't a clone, offer to `git init` for local history.
- Log the change. Undo: `git remote remove origin`, and delete the remote repo if the user wants.

## Step 8: Finish
1. Journal entry: the setup summary and the user's choices.
2. Tell the user:
   - What was set up, with the log IDs.
   - How to elevate when asked.
   - Three things to try (e.g. "check my disk health", "clean up old packages", "what's slowing down boot?").
   - That they can ask to change any preference at any time.
3. Remind them that the rules (`CLAUDE.md`) load automatically in every session started in this folder.

## Verification
- `profile/SYSTEM.md` and `profile/PREFERENCES.md` exist, with no `{{…}}` left.
- `logging/CHANGELOG.md` has entries for every change made.
- The `pca-*` commands resolve.
- Each chosen rollback tool shows a working first snapshot or commit.
- Shared-tool clones only: `git status` shows no personal files staged for the upstream repo (unless step 7 deliberately made the folder a private backup).

## Rollback
Each step's undo is in its CHANGELOG entry. A full reset: run every entry's undo in reverse order, then delete `profile/*.md` (except `README.md`) and the generated `logging/` contents.

## Platform status
- Linux: designed and partly tested (Ubuntu).
- Windows 11: run end to end once (2026-11-20), without setting up a new rollback tool. `scan.ps1` still reports some values wrongly: BitLocker when it is off, sudo for Windows when it is disabled, WSL distro names, and restore points when not elevated. Check those by hand until fixed.
- macOS/BSD: steps are written from documented behavior and not yet tested end to end.
- Fix and log anything you find on first real use.

## Changelog
- 1.0 (2026-11-04): created.
- 1.1 (2026-11-05): elevation step now detects sudo-rs (no global timestamp) and covers scoped passwordless sudo, including symlinked binaries. Learned on Ubuntu 26.04.
- 1.2 (2026-11-20): `scan.ps1` and `install-commands.ps1` are ASCII-only, so the documented Windows PowerShell 5.1 commands work. Before, `scan.ps1` failed to parse in 5.1 on systems with code page 1252.
