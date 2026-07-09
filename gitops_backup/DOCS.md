# GitOps Config Backup

PR-gated GitHub backup for your Home Assistant config.

## Quick start

1. Create a GitHub repo (private recommended).
2. Create a fine-grained PAT with **Contents: read/write** and
   **Pull requests: read/write** on that repo.
3. Fill in the add-on options (`github_repo`, `github_token`), leave
   `dry_run: true`, start the add-on, and check
   `gitops_backup.log` in your config folder.
4. Happy? Set `dry_run: false`. The first real run bootstraps git in your
   config folder (with a Home-Assistant-aware `.gitignore`) and pushes the
   initial import. Every run after that only opens pull requests.
5. Copy `template/workflows/validate-ha-config.yaml` from the add-on
   repository into `.github/workflows/` of your config repo so every backup
   PR is validated against pinned Home Assistant versions before merge.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `github_repo` | — | `owner/repo` to back up into (required) |
| `github_token` | — | Fine-grained PAT (required) |
| `base_branch` | `main` | Branch PRs target |
| `branch_prefix` | `auto-backup` | Prefix for backup branches |
| `interval_hours` | `24` | Hours between runs (1–168) |
| `run_at_start` | `false` | Also run when the add-on starts |
| `dry_run` | `false` | Log what would change; push nothing |
| `commit_name` / `commit_email` | see defaults | Commit author identity |
| `signoff` | `true` | Add `Signed-off-by` (DCO) to commits |

## What is committed

Everything in your config folder **except** the seeded `.gitignore` exclusions:
`secrets.yaml`, `.storage/`, `.cloud/`, databases, logs, `known_devices.yaml`,
`ip_bans.yaml`, and the add-on's own status/log files.

## Status in Home Assistant

```yaml
command_line:
  - sensor:
      name: GitOps Backup Status
      command: "cat /config/.gitops_backup_status 2>/dev/null || echo 'unknown'"
      scan_interval: 3600
```

Values: `success:pr_created:<url>` · `success:no_changes:` ·
`success:dry_run:<n files>` · `warning:…` · `error:…`
