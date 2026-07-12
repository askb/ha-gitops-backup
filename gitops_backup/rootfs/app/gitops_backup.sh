#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Anil Belur
##############################################################################
# GitOps Config Backup — PR-gated GitHub backup for Home Assistant config
#
# Workflow (never pushes to the base branch after bootstrap):
#   1. Stash any local changes
#   2. pull --rebase from origin/<base> to sync upstream changes (merged PRs)
#   3. Re-apply stashed changes
#   4. If the live config drifted, commit to a dated backup branch + open a PR
#
# Status file (.gitops_backup_status, gitignored) format:
#   <status>:<detail>:<extra>
##############################################################################

set -euo pipefail

OPTIONS="${OPTIONS:-/data/options.json}"
CONFIG_DIR="${CONFIG_DIR:-/homeassistant}"
LOG_FILE="${CONFIG_DIR}/gitops_backup.log"
MAX_LOG_LINES=200
STATUS_FILE="${CONFIG_DIR}/.gitops_backup_status"

opt() { jq -r "$1" "$OPTIONS"; }

GITHUB_REPO="$(opt .github_repo)"
GITHUB_TOKEN="$(opt .github_token)"
BASE_BRANCH="$(opt .base_branch)"
BRANCH_PREFIX="$(opt .branch_prefix)"
DRY_RUN="$(opt .dry_run)"
COMMIT_NAME="$(opt .commit_name)"
COMMIT_EMAIL="$(opt .commit_email)"
SIGNOFF="$(opt .signoff)"

REMOTE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
API="https://api.github.com/repos/${GITHUB_REPO}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"; }

write_status() {
    echo "$1:$2:${3:-}" > "$STATUS_FILE"
    log "Status: $1:$2:${3:-}"
}

rotate_log() {
    [ -f "$LOG_FILE" ] && tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" \
        && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

api_call() { # method path [json-body]
    local method="$1" path="$2" body="${3:-}"
    curl -sf -X "$method" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        ${body:+-d "$body"} \
        "${API}${path}"
}

seed_gitignore() {
    if [ ! -f .gitignore ]; then
        log "Seeding recommended Home Assistant .gitignore"
        cat > .gitignore <<'EOF'
# Secrets and credentials — never commit
secrets.yaml
*.pem
*.key
.git-credentials
.cloud/
.storage/

# Runtime state, databases, logs
*.db
*.db-shm
*.db-wal
*.log
*.log.*
ip_bans.yaml
known_devices.yaml
home-assistant_v2.*
OZW_Log.txt
.uuid
.ha_run.lock

# This addon's runtime metadata (committing it creates a PR feedback loop)
.gitops_backup_status
gitops_backup.log

# Misc
__pycache__/
deps/
tts/
backups/
EOF
    fi
}

ensure_own_excludes() {
    # The addon's own runtime files must never be committed — not even when the
    # repo already had a .gitignore (seed_gitignore only writes one when none
    # exists, so migrating an existing repo would otherwise sweep these into a
    # backup PR and risk a status-file PR feedback loop). .git/info/exclude is
    # git's local, non-committed ignore — the right home for addon-managed
    # metadata. Idempotent: replace our managed block each run.
    [ -d .git ] || return 0
    mkdir -p .git/info
    local exclude=".git/info/exclude"
    if [ -f "$exclude" ]; then
sed -i \
    '/# >>> gitops-backup managed >>>/,/# <<< gitops-backup managed <<</d' \
    "$exclude"
    fi
    cat >> "$exclude" <<'EOF'
# >>> gitops-backup managed >>>
.gitops_backup_status
gitops_backup.log
# <<< gitops-backup managed <<<
EOF
    # If a prior buggy run already committed these, stop tracking them (the
    # removal flows out through the next backup PR).
    local f
    for f in .gitops_backup_status gitops_backup.log; do
if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git rm -q --cached "$f"
fi
    done
}

bootstrap_if_needed() {
    # Returns 0 if bootstrap ran (caller should stop), 1 if repo already exists
    if [ -d .git ]; then return 1; fi
    log "No git repo in ${CONFIG_DIR} — bootstrapping"
    if [ "$DRY_RUN" = "true" ]; then
        seed_gitignore
        log "DRY RUN: would git init, commit initial import, push to ${BASE_BRANCH}"
        write_status success dry_run bootstrap
        return 0
    fi
    git init -q -b "$BASE_BRANCH"
    seed_gitignore
    git add -A
    git commit -q ${SIGNOFF:+-s} -m "chore: initial Home Assistant config import"
    git remote add origin "$REMOTE_URL"
    # Push base branch only on bootstrap; every later change goes through a PR
    git push -q -u origin "$BASE_BRANCH"
    write_status success bootstrap "initial import pushed to ${BASE_BRANCH}"
    log "Bootstrap complete"
}

create_pull_request() {
    local branch="$1" title="$2" body="$3"
    local payload
    payload=$(jq -n --arg t "$title" --arg b "$body" \
        --arg h "$branch" --arg base "$BASE_BRANCH" \
        '{title:$t, body:$b, head:$h, base:$base}')
    api_call POST /pulls "$payload" | jq -r '.html_url // empty'
}

cleanup_branch() {
    local current
    current=$(git branch --show-current 2>/dev/null || echo "")
    if [ "$current" != "$BASE_BRANCH" ] && [ -n "$current" ]; then
        git checkout -q "$BASE_BRANCH" 2>/dev/null || true
    fi
}

main() {
    # Input validation at the trust boundary
    if [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_TOKEN" ]; then
        write_status error config "github_repo and github_token are required"
        exit 1
    fi
    cd "$CONFIG_DIR"

    git config --global --add safe.directory "$CONFIG_DIR"
    git config --global user.name "$COMMIT_NAME"
    git config --global user.email "$COMMIT_EMAIL"

    if bootstrap_if_needed; then
        rotate_log
        return 0
    fi
    git remote set-url origin "$REMOTE_URL"
    seed_gitignore
    ensure_own_excludes
    trap cleanup_branch EXIT

    # 1–2. Stash local drift, sync upstream (merged PRs flow back here)
    local stashed=false
    if [ -n "$(git status --porcelain)" ]; then
        git stash -q --include-untracked
        stashed=true
    fi
    if ! git pull -q --rebase origin "$BASE_BRANCH"; then
        git rebase --abort 2>/dev/null || true
        [ "$stashed" = true ] && git stash pop -q 2>/dev/null
        write_status error pull_rebase_failed "resolve manually in ${CONFIG_DIR}"
        exit 1
    fi
    # 3. Re-apply drift
    if [ "$stashed" = true ] && ! git stash pop -q; then
        git checkout -q --theirs . 2>/dev/null || true
        git stash drop -q 2>/dev/null || true
        write_status warning stash_conflict "kept live config where conflicting"
    fi

    # 4. Anything to back up?
    if [ -z "$(git status --porcelain)" ]; then
        write_status success no_changes ""
        log "No changes to back up"
        rotate_log
        return 0
    fi

    local changed_count branch_name
    changed_count=$(git status --porcelain | wc -l | tr -d ' ')
    branch_name="${BRANCH_PREFIX}/$(date '+%Y-%m-%d-%H%M%S')"

    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: ${changed_count} changed file(s) would go to ${branch_name}:"
        git status --porcelain | tee -a "$LOG_FILE"
        write_status success dry_run "${changed_count} files"
        rotate_log
        return 0
    fi

    git checkout -q -b "$branch_name"
    git add -A
    git commit -q ${SIGNOFF:+-s} \
        -m "chore: auto backup $(date '+%Y-%m-%d %H:%M') (${changed_count} files)"
    git push -q -u origin "$branch_name"

    local pr_url
    if pr_url=$(create_pull_request "$branch_name" \
        "chore: auto backup $(date '+%Y-%m-%d %H:%M')" \
        "Automated Home Assistant config backup — ${changed_count} changed file(s). Opened by the GitOps Config Backup addon; review and merge.") \
        && [ -n "$pr_url" ]; then
        write_status success pr_created "$pr_url"
        log "✅ Backup complete — PR opened: ${pr_url}"
    else
        write_status warning branch_pushed "$branch_name"
        log "WARNING: branch pushed but PR creation failed"
    fi
    rotate_log
}

main "$@"
