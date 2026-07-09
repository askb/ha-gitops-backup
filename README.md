# GitOps Config Backup — Home Assistant Add-on

**PR-gated GitHub backup for your Home Assistant config.** Nothing force-pushes,
every change is a reviewable pull request, and CI validates your config against
pinned Home Assistant versions *before* it can merge.

[![Add repository to my Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Faskb%2Fha-gitops-backup)

## Why another config-backup add-on?

Most config-sync tools upload your files straight onto a branch — some even
force-push. That gives you a *copy*, not *control*. This add-on treats your
config like production infrastructure:

| | Direct-push sync tools | GitOps Config Backup |
|---|---|---|
| Changes land on main | Immediately, sometimes force-pushed | **Never** — every drift becomes a PR |
| Review before accept | No | **Yes** — diff, comment, merge (or close) |
| CI validation | No | **Yes** — HA version-matrix check gates the merge |
| Bidirectional | Usually one-way upload | **Yes** — merged PRs flow back on the next run |
| Secrets safety | gitignore defaults | gitignore defaults **+ CI runs with stub secrets only** |

## How it works

1. **Daily (configurable) run** on your Home Assistant box:
   stash local drift → `pull --rebase` from `origin/main` (picks up PRs you
   merged) → re-apply → if the live config changed, commit to a dated
   `auto-backup/…` branch and **open a PR** via the GitHub API.
2. **CI on the PR** (template workflows included): yamllint + full
   `frenck/action-home-assistant` validation against a pinned HA version, with
   a `stable` early-warning leg — upgrade breakage surfaces in CI, not on your Pi.
3. **You merge** (from your phone, if you like). The next add-on run rebases the
   merged state back onto the box.

## Install

1. Add this repository to your Add-on store (badge above), install
   **GitOps Config Backup**.
2. Create a GitHub repo (private recommended) and a fine-grained PAT with
   *Contents: read/write* and *Pull requests: read/write* on it.
3. Configure the add-on:

```yaml
github_repo: you/your-ha-config
github_token: github_pat_…
base_branch: main
branch_prefix: auto-backup
interval_hours: 24
run_at_start: false
dry_run: true        # start with a dry run, check the log, then set false
signoff: true
```

4. Copy `template/workflows/validate-ha-config.yaml` into
   `.github/workflows/` of your config repo, and add a stub line for every
   `!secret` key you use (CI never sees real secrets).
5. (Recommended) Protect `main` in the repo settings: require the
   *HA Config Validation* check.

First run bootstraps the git repo in `/config` (seeding a Home Assistant
`.gitignore` covering `secrets.yaml`, `.storage/`, databases, logs) and pushes
the initial import; every run after that only ever opens PRs.

## Status sensor (optional)

The add-on writes `.gitops_backup_status` (`status:detail:extra`) to your config
dir. Expose it in HA:

```yaml
command_line:
  - sensor:
      name: GitOps Backup Status
      command: "cat /config/.gitops_backup_status 2>/dev/null || echo 'unknown'"
      scan_interval: 3600
```

## Deploying merged changes back to the box

Merged PRs are picked up automatically on the next scheduled run. To apply
immediately:

```bash
ssh root@<HA_IP> 'cd /homeassistant && git fetch origin && git reset --hard origin/main'
ssh root@<HA_IP> 'ha core restart'
```

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
| `commit_name` / `commit_email` | see config | Commit author |
| `signoff` | `true` | Add `Signed-off-by` (DCO) to commits |

## Security notes

- The token lives in the add-on options (Supervisor-encrypted), never in git.
- The seeded `.gitignore` excludes `secrets.yaml`, `.storage/`, `.cloud/`,
  databases, logs, and the add-on's own status/log files (committing status
  files creates a PR-per-day feedback loop — learned the hard way).
- CI validates with **stub** secrets; your real `secrets.yaml` never leaves the box.
- Nothing in this add-on ever force-pushes or writes to your base branch after
  the initial bootstrap import.

## License

Apache-2.0
