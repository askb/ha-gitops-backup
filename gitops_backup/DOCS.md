# GitOps Config Backup

PR-gated GitHub backup for your Home Assistant config.

## What you need

- A **GitHub account** (free is fine)
- A **repository** for your config — private recommended
- A **fine-grained personal access token (PAT)** scoped to that one repo

## Step-by-step setup

### 1. Create the repository

github.com → **+** → **New repository** → name it (e.g. `my-ha-config`) →
**Private** → Create. Don't add a README — the add-on bootstraps the content.

### 2. Create the token

1. github.com → your avatar → **Settings** → **Developer settings** →
   **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
2. **Token name**: `ha-gitops-backup` · **Expiration**: 1 year (set a calendar
   reminder — the add-on status will show `error` when it expires)
3. **Repository access**: *Only select repositories* → pick the repo from step 1
4. **Permissions → Repository permissions**:
   - **Contents**: Read and write
   - **Pull requests**: Read and write
   - everything else: No access
5. Generate, copy the `github_pat_…` value — you won't see it again

> The token can only touch that single repo. Even if it leaked, your other
> repos and account are untouchable — that's why fine-grained beats classic PATs.

### 3. Configure the add-on

Settings → Add-ons → GitOps Config Backup → **Configuration**:

```yaml
github_repo: yourname/my-ha-config
github_token: github_pat_XXXXXXXX
dry_run: true        # first run: log only, push nothing
```

Start the add-on, then check `gitops_backup.log` in your config folder to see
what *would* be committed. Happy? Set `dry_run: false` and restart. The first
real run pushes the initial import; every run after that only opens PRs.

The token is stored in the add-on options by the Supervisor — it never goes
into git, and the seeded `.gitignore` keeps `secrets.yaml` and other sensitive
files out of the repo entirely.

### 4. Add the CI gate (recommended)

Copy `template/workflows/validate-ha-config.yaml` from this repository into
`.github/workflows/` of **your config repo**, and add a stub line for every
`!secret` key you use (CI never sees real secrets). Then protect `main`:
repo → Settings → Branches → require the *HA Config Validation* and
*HA Smoke Boot* checks.

## What is backed up where (best practice)

This add-on is **change tracking for your config**, not disaster recovery.
Run both layers:

| Data | This add-on (GitHub) | HA Backup + Google Drive |
|------|----------------------|--------------------------|
| Config YAML (automations, dashboards, …) | ✅ versioned, reviewable diffs | ✅ inside the archive |
| `secrets.yaml` | ❌ **never** (gitignored) | ✅ inside the **encrypted** archive |
| `.storage/` (auth, entity registry) | ❌ never | ✅ |
| Databases, history, logs | ❌ never | ✅ (recorder DB, if selected) |
| Add-ons + their data | ❌ | ✅ |
| Media, camera recordings | ❌ | usually excluded — external drive |

**Recommended stack:**

```text
GitHub (this add-on)      → config changes: who/what/when, PR review, CI gate
HA auto backup (daily)    → full system state, encrypted, on the box
 └─ Google Drive Backup   → off-site copies of those archives
Password manager          → the three keys to the kingdom (below)
```

### Where secrets belong

- `secrets.yaml` lives **only on the box** — referenced via `!secret` in your
  config, excluded from git by the seeded `.gitignore`, and recovered from the
  encrypted HA backup, never from GitHub.
- Store in your **password manager** (never in the repo, never in a README):
  1. the HA **backup encryption password** — without it your off-site backups
     are unrestorable,
  2. the **GitHub PAT** for this add-on,
  3. your HA admin credentials.
- CI validates PRs with **stub** secrets (step 4) — real values never leave
  the box.

**Disaster recovery order:** reinstall HAOS → restore the encrypted HA backup
(brings back `secrets.yaml`, `.storage`, add-ons) → your config repo is then
already live on the box and git history simply resumes.

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
