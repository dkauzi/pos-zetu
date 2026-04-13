#!/bin/bash
# POS-Zetu Safe Upgrade Script
BENCH=/home/frappe/frappe-bench
SITE=pos.homezetu.com
REPO=/home/frappe/pos-zetu-repo
EMAIL_TO="dkarigi@gmail.com"
EMAIL_FROM="homezetu@homezetu.com"
SMTP_HOST="mail-eu.smtp2go.com"
SMTP_PORT=2525
SMTP_USER="homezetu.com"
SMTP_PASS="NLaw4FzZALN9G0cl"
LOG=/var/log/poszetu_upgrade.log

send_email() {
  local SUBJ="$1" BODY="$2"
  python3 -c "
import smtplib, sys
from email.mime.text import MIMEText
msg = MIMEText(sys.argv[2], 'html')
msg['Subject'] = sys.argv[1]
msg['From'] = 'homezetu@homezetu.com'
msg['To'] = 'dkarigi@gmail.com'
s = smtplib.SMTP('mail-eu.smtp2go.com', 2525, timeout=30)
s.ehlo(); s.starttls()
s.login('homezetu.com', 'NLaw4FzZALN9G0cl')
s.sendmail(msg['From'], [msg['To']], msg.as_string())
s.quit()
print('Email sent')
" "$SUBJ" "$BODY" 2>&1 || echo 'Email send failed'
}

check_health() {
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$SITE/api/method/frappe.ping" --max-time 30)
  [ "$CODE" = "200" ]
}

exec >> "$LOG" 2>&1
echo ""
echo "=== POS-Zetu Upgrade $(date) ==="

START_TIME=$(date)
VERSIONS_BEFORE=$(cd $BENCH && bench version 2>/dev/null)

if ! check_health; then
  send_email "WARNING POS-Zetu Upgrade ABORTED - site was already down" "<h2>Upgrade Aborted</h2><p>Site was not responding before upgrade. No changes made.</p><pre>$VERSIONS_BEFORE</pre>"
  exit 1
fi

echo "[1/4] Backing up..."
cd $BENCH
bench --site $SITE backup --with-files
BACKUP_FILE=$(ls -t sites/$SITE/private/backups/*.sql.gz 2>/dev/null | head -1)
echo "Backup: $BACKUP_FILE"

echo "[2/4] Saving customizations..."
bench --site $SITE mariadb --execute "SELECT value FROM tabSingles WHERE doctype='Website Settings' AND field='head_html';" > $REPO/customizations/fixtures/head_html_backup.txt 2>/dev/null
git -C $REPO add -A && git -C $REPO commit -m "Pre-upgrade $(date +%Y-%m-%d)" 2>/dev/null || true

send_email "STARTED POS-Zetu Upgrade $(date +%Y-%m-%d)" "<h2>Upgrade Started</h2><p><b>Time:</b> $START_TIME</p><p><b>Versions:</b></p><pre>$VERSIONS_BEFORE</pre><p>You will get another email when done.</p>"

echo "[3/4] Running bench update..."
UPGRADE_OUT=$(bench update --pull --patch --build 2>&1)
UPGRADE_EXIT=$?
echo "$UPGRADE_OUT"

echo "[4/4] Health check..."
sleep 10
VERSIONS_AFTER=$(bench version 2>/dev/null)

if [ $UPGRADE_EXIT -eq 0 ] && check_health; then
  send_email "SUCCESS POS-Zetu Upgrade Completed $(date +%Y-%m-%d)" "<h2>Upgrade Successful</h2><p><b>Started:</b> $START_TIME</p><p><b>Finished:</b> $(date)</p><p><b>Before:</b></p><pre>$VERSIONS_BEFORE</pre><p><b>After:</b></p><pre>$VERSIONS_AFTER</pre><p><a href='https://$SITE'>Check site</a></p>"
  git -C $REPO add -A && git -C $REPO commit -m "Post-upgrade $(date +%Y-%m-%d)" 2>/dev/null || true
else
  echo "FAILED - reverting..."
  [ -n "$BACKUP_FILE" ] && bench --site $SITE restore "$BACKUP_FILE" && bench --site $SITE migrate
  REVERT=${BACKUP_FILE:-"NO BACKUP FOUND - manual fix needed"}
  TAIL=$(echo "$UPGRADE_OUT" | tail -50)
  send_email "FAILED POS-Zetu Upgrade FAILED - Auto-reverted" "<h2>Upgrade Failed</h2><p><b>Started:</b> $START_TIME</p><p><b>Failed:</b> $(date)</p><p><b>Reverted to:</b> $REVERT</p><pre>$TAIL</pre>"
fi
echo "=== Done $(date) ==="
