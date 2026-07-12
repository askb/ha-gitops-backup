# Changelog

## 0.2.0

- Docs: make the two-pillar backup model explicit — config repo (this add-on)
  + encrypted HA full backup (e.g. Google Drive Backup) = 100% restorable;
  neither alone is enough. Sharpened the "what is backed up where" table
  (names exactly what `.storage/` holds and what lives outside `/config`).
- Security: seed `.gitignore` now also excludes `*.token` / `.google.token`
  so OAuth tokens (e.g. Google Calendar) never land in the repo.
- First bootstrap now logs a disaster-recovery warning: this add-on versions
  declarative config only; run HA full backups for a complete restore.

## 0.1.1

- Fix: keep the addon's own runtime files (`.gitops_backup_status`,
  `gitops_backup.log`) out of backups when migrating a repo that already has a
  `.gitignore` — they were previously swept into backup PRs and risked a
  status-file PR feedback loop. Now excluded via `.git/info/exclude` on every
  run, and untracked if a prior run committed them.

## 0.1.0

- Initial release: PR-gated backup (stash → rebase → drift → branch → PR),
  dry-run mode, DCO sign-off, seeded HA `.gitignore`, status file for a
  `command_line` sensor, template CI workflow for the config repo.
