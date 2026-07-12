# Changelog

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
