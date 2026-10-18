#!/bin/bash
# POS-Zetu safe upgrade script.
#
# Applies the latest v15 patch releases to every site on the bench.
# It refuses to run a major-version upgrade (for example v15 -> v16).
#
# Safety steps:
#   1. Pre-flight: every site must answer, core apps must be on their v15 branch,
#      and no app may have uncommitted local edits.
#   2. Records each app's current commit so the code can be rolled back.
#   3. Backs up every site, with files.
#   4. Runs a full `bench update` (pull, requirements, migrate, build, restart).
#   5. Health-checks every site. On any failure, checks the old code back out,
#      reinstalls its requirements, rebuilds, restores every site, and restarts.
#
# Secrets are read from /home/frappe/.poszetu.env (see poszetu.env.example).
# Take a DigitalOcean droplet snapshot before running this for extra safety.

set -u

BENCH=/home/frappe/frappe-bench
REPO=/home/frappe/pos-zetu-repo
ENV_FILE=${POSZETU_ENV:-/home/frappe/.poszetu.env}
LOG=/var/log/poszetu_upgrade.log
MAIN_SITE=pos.homezetu.com
EXPECTED_BRANCH=${EXPECTED_BRANCH:-version-15}
CORE_APPS="frappe erpnext"

if [ ! -r "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE. Copy poszetu.env.example there and fill it in." >&2
  exit 1
fi
set -a; . "$ENV_FILE"; set +a

send_email() {
  SUBJ="$1" BODY="$2" python3 - <<'PY' 2>&1 || echo "Email send failed"
import os, smtplib
from email.mime.text import MIMEText
msg = MIMEText(os.environ["BODY"], "html")
msg["Subject"] = os.environ["SUBJ"]
msg["From"] = os.environ["FROM_EMAIL"]
msg["To"] = os.environ["ADMIN_EMAIL"]
s = smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ["SMTP_PORT"]), timeout=30)
s.ehlo(); s.starttls()
s.login(os.environ["SMTP_USER"], os.environ["SMTP_PASS"])
s.sendmail(msg["From"], [msg["To"]], msg.as_string())
s.quit()
print("Email sent")
PY
}

list_sites() {
  for d in "$BENCH"/sites/*/; do
    [ -f "$d/site_config.json" ] && basename "$d"
  done
}

# Hit gunicorn directly with the site's Host header, so every site is checked
# without depending on DNS or TLS certificates.
site_ok() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $1" \
    "http://127.0.0.1:8000/api/method/frappe.ping" --max-time 30)
  [ "$code" = "200" ]
}

check_all_sites() {
  local failed=""
  for site in $SITES; do
    site_ok "$site" || failed="$failed $site"
  done
  [ -z "$failed" ] || { echo "Unhealthy sites:$failed"; return 1; }
}

abort() {
  echo "ABORTED: $1"
  send_email "WARNING POS-Zetu upgrade aborted" \
    "<h2>Upgrade aborted. No changes made.</h2><p>$1</p><pre>$VERSIONS_BEFORE</pre>"
  exit 1
}

exec >> "$LOG" 2>&1
echo ""
echo "=== POS-Zetu Upgrade $(date) ==="
cd "$BENCH" || exit 1

START_TIME=$(date)
SITES=$(list_sites)
APPS=$(ls apps)
VERSIONS_BEFORE=$(bench version 2>/dev/null)
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/home/frappe/upgrade-backups/$STAMP

echo "[1/5] Pre-flight checks..."
check_all_sites || abort "One or more sites were already down before the upgrade."
for app in $CORE_APPS; do
  branch=$(git -C "apps/$app" rev-parse --abbrev-ref HEAD)
  [ "$branch" = "$EXPECTED_BRANCH" ] || \
    abort "apps/$app is on branch '$branch', expected '$EXPECTED_BRANCH'. Major upgrades must be done by hand."
done
for app in $APPS; do
  [ -z "$(git -C "apps/$app" status --porcelain --untracked-files=no)" ] || \
    abort "apps/$app has uncommitted local edits. Move them into a custom app before upgrading."
done

echo "[2/5] Recording app commits and backing up all sites..."
mkdir -p "$BACKUP_DIR"
for app in $APPS; do
  echo "$app $(git -C "apps/$app" rev-parse HEAD)" >> "$BACKUP_DIR/app_commits.txt"
done
for site in $SITES; do
  bench --site "$site" backup --with-files --backup-path "$BACKUP_DIR/$site" \
    || abort "Backup failed for $site."
done
echo "Backups in $BACKUP_DIR"

if [ -d "$REPO/.git" ]; then
  bench --site "$MAIN_SITE" mariadb --execute \
    "SELECT value FROM tabSingles WHERE doctype='Website Settings' AND field='head_html';" \
    > "$REPO/customizations/fixtures/head_html_backup.txt" 2>/dev/null
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "Pre-upgrade $(date +%Y-%m-%d)" || true
fi

send_email "STARTED POS-Zetu upgrade $(date +%Y-%m-%d)" \
  "<h2>Upgrade started</h2><p><b>Time:</b> $START_TIME</p><p><b>Sites:</b> $SITES</p><pre>$VERSIONS_BEFORE</pre>"

echo "[3/5] Running bench update..."
# No step flags: a plain update also installs new Python/Node requirements.
# --no-backup because every site was already backed up above.
UPGRADE_OUT=$(bench update --no-backup 2>&1)
UPGRADE_EXIT=$?
echo "$UPGRADE_OUT"
# Make sure workers run the new code even if auto-restart on update is off.
[ $UPGRADE_EXIT -eq 0 ] && { bench restart || UPGRADE_EXIT=1; }

echo "[4/5] Health check..."
sleep 15
VERSIONS_AFTER=$(bench version 2>/dev/null)

if [ $UPGRADE_EXIT -eq 0 ] && check_all_sites; then
  send_email "SUCCESS POS-Zetu upgrade completed $(date +%Y-%m-%d)" \
    "<h2>Upgrade successful</h2><p><b>Started:</b> $START_TIME</p><p><b>Finished:</b> $(date)</p><p><b>Before:</b></p><pre>$VERSIONS_BEFORE</pre><p><b>After:</b></p><pre>$VERSIONS_AFTER</pre>"
  [ -d "$REPO/.git" ] && { git -C "$REPO" add -A && git -C "$REPO" commit -qm "Post-upgrade $(date +%Y-%m-%d)" || true; }
  echo "=== Done $(date) ==="
  exit 0
fi

echo "[5/5] FAILED. Rolling back code and data..."
while read -r app sha; do
  git -C "apps/$app" checkout -q "$sha" || echo "Could not check out $app at $sha"
done < "$BACKUP_DIR/app_commits.txt"
bench setup requirements
bench build

ROOT_ARGS=()
[ -n "${DB_ROOT_PASSWORD:-}" ] && ROOT_ARGS=(--db-root-password "$DB_ROOT_PASSWORD")
RESTORE_FAILED=""
for site in $SITES; do
  dir="$BACKUP_DIR/$site"
  sql=$(ls "$dir"/*-database.sql.gz 2>/dev/null | head -1)
  pub=$(ls "$dir"/*-files.tar 2>/dev/null | grep -v private | head -1)
  priv=$(ls "$dir"/*-private-files.tar 2>/dev/null | head -1)
  if [ -z "$sql" ]; then RESTORE_FAILED="$RESTORE_FAILED $site"; continue; fi
  args=("${ROOT_ARGS[@]}" --force)
  [ -n "$pub" ] && args+=(--with-public-files "$pub")
  [ -n "$priv" ] && args+=(--with-private-files "$priv")
  bench --site "$site" restore "$sql" "${args[@]}" || RESTORE_FAILED="$RESTORE_FAILED $site"
done
bench restart
sleep 15

if [ -z "$RESTORE_FAILED" ] && check_all_sites; then
  RESULT="Rolled back to the previous code and data. All sites are healthy."
else
  RESULT="ROLLBACK INCOMPLETE. Restore failed for:${RESTORE_FAILED:- none}. Check sites by hand. Backups: $BACKUP_DIR"
fi
echo "$RESULT"
# Note: apps are left in detached-HEAD state at the old commits.
# Run `git -C apps/<app> checkout $EXPECTED_BRANCH` once the cause is fixed.
TAIL=$(echo "$UPGRADE_OUT" | tail -50)
send_email "FAILED POS-Zetu upgrade failed" \
  "<h2>Upgrade failed</h2><p><b>Started:</b> $START_TIME</p><p><b>Failed:</b> $(date)</p><p>$RESULT</p><pre>$TAIL</pre>"
echo "=== Done $(date) ==="
exit 1
