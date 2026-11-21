# Skills Index

The register of every skill available to the PC Assistant. **Read this file at session start; open a skill's `SKILL.md` only when it's relevant to the current task.**

**This index must always be kept current** — update it in the same task that adds, changes, or retires a skill (see `CLAUDE.md` §7 and §9).

- Layout: `skills/<category>/<skill-name>/SKILL.md` (+ scripts). Template: `skills/_template/SKILL.md`.
- Categories: `setup`, `maintenance`, `diagnostics`, `config`, `cleanup`, `automation`, `personal` (create others as needed).
- Commands: scripts are exposed as `pca-<name>` (Unix: `~/.local/bin` symlink; Windows: `%USERPROFILE%\.pca\bin` shim).
- Tier: 0 = free, 1 = do-then-report, 2 = ask-first (highest tier of any step).

## Shared skills

| Skill | Purpose | Use when | Command | Platforms | Admin | Tier | Path | Updated |
|---|---|---|---|---|---|---|---|---|
| first-time-setup | Scan the system, ask the user's preferences, generate the profile, logs, baseline, commands, rollback tools | User says "First time setup", profile missing, or "re-scan my system" | none | all | some steps | 2 | `setup/first-time-setup/` | 2026-11-20 |
| change-backup | Back up / restore files (and Windows registry keys) tied to a change ID | Before editing any config file; undoing a change | `pca-backup` | all | if file needs it | 1 | `maintenance/change-backup/` | 2026-11-20 |
| system-baseline | Read-only snapshot of packages, services, jobs, settings; diff snapshots | Setup; "what changed since…"; before/after big changes | `pca-baseline` | all | no | 0 | `maintenance/system-baseline/` | 2026-11-20 |
| context-menu-actions | File-manager right-click actions: Copy Path/Name/quoted/parent/SHA-256, Open in VS Code, Open Terminal Here | "add X to the right-click menu", copy paths from Files | none | GNOME (built); KDE/Windows/macOS (recipes) | to install package | 2 | `config/context-menu-actions/` | 2026-11-05 |
| system-health | Read-only check-up: pending reboot, updates, failed services, memory hogs, disk/reclaimable space, firewall & exposed ports, battery, startup items | "health check", "any suggestions?", "why is it slow" (first look), periodic check-ups | `pca-health` | all (Windows untested) | no | 0 | `maintenance/system-health/` | 2026-11-05 |
| raspberry-pi-headless | Image a Raspberry Pi with no monitor/keyboard: Imager ≥2.0, SSH key, flash pre-configured OS, find it, first-boot setup over SSH | "set up / reimage my Pi", "headless Pi", "find my Pi", "install Raspberry Pi Imager" | `pca-pi-find` | host: all (Windows/macOS untested) | to install Imager; on the Pi | 2 | `setup/raspberry-pi-headless/` | 2026-11-05 |

### Details
- **first-time-setup** — Runs a read-only scan (`scan.sh` on Linux/macOS/BSD, `scan.ps1` on Windows), asks a short questionnaire adapted to the detected OS, then writes `profile/SYSTEM.md` + `profile/PREFERENCES.md`, creates the CHANGELOG/journal from templates, records a baseline, installs `pca-*` commands, and (with approval) sets up the chosen rollback tools. Has a **re-scan** mode that only refreshes SYSTEM.md.
- **change-backup** — `pca-backup <ID> <file>…` copies files into `logging/backups/<ID>/` preserving full paths and metadata, with a SHA256SUMS file. `--private` for files with secrets (git-ignored). `--restore <ID> [file]` puts them back. `--list` shows what a change backed up. Windows: `--reg <key>` exports a registry key.
- **system-baseline**: `pca-baseline [label]` writes package lists (every package manager it finds), enabled services and timers, cron/launchd/scheduled tasks, and desktop settings exports (dconf, macOS defaults) into `logging/baseline/<stamp>/`. Obvious secrets are redacted. `--diff a b` compares two captures. Nothing on the system is changed.
- **context-menu-actions**: a nautilus-python extension (`gnome-files/pca_context_menu.py`, symlinked by `install.sh`) adds *Copy Path* and a *Copy Other ▸* submenu (Name, shell-quoted Path, Parent Folder Path, SHA-256), plus *Open in VS Code* and *Open Terminal Here*. Needs `python3-nautilus` and wl-clipboard/xclip, and Files must restart (`nautilus -q`). Includes recipes for KDE service menus, Windows `HKCU\…\shell` verbs, and macOS Quick Actions.
- **system-health**: `pca-health [--offline]` prints `[ok]`/`[info]`/`[WARN]` lines per area, then a warning summary. Each check runs only if its tool exists, so it adapts to any OS. Its SKILL.md lists lessons for interpreting findings: phased updates, autoremove traps, snap revisions in use, Timeshift hard links hiding freed space, locked caches.
- **raspberry-pi-headless**: walks through choices (model, wired/Wi-Fi, Lite/Desktop, key passphrase, Pi admin mode), installing and verifying Imager, the SSH key and ssh config, exact Imager values (the user types every password), then `pca-pi-find <host>` (mDNS incl. `-2…-9` conflict names + subnet sweep for Pi MAC prefixes) and a first-boot menu over SSH: updates, unattended-upgrades, ufw with a 5-min `systemd-run` failsafe, Wi-Fi off when wired, EEPROM update. Gotchas section: dual-interface avahi renames, Imager 2.x sudo password, old Imager skipping customisation.
- **Installing commands**: after adding or removing any `pca-*` script, re-run `skills/setup/first-time-setup/install-commands.sh` (or `.ps1` on Windows). It's idempotent.

<!-- PERSONAL-SKILLS:START -->
## Personal skills
Skills specific to this user/machine (`skills/personal/`). Not shared.

| Skill | Purpose | Use when | Command | Platforms | Admin | Tier | Path | Updated |
|---|---|---|---|---|---|---|---|---|

_None yet._
<!-- PERSONAL-SKILLS:END -->

## Candidates (watchlist)
Repeated tasks that might become skills. 2nd occurrence → add here; 3rd (or clearly valuable) → propose.

| Task | Seen on | Status (watching / proposed / declined / built) | Notes |
|---|---|---|---|

## Retired
| Skill | Retired on | Reason |
|---|---|---|
