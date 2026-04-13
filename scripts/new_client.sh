#!/bin/bash
# Usage: ./new_client.sh "Business Name" email@client.com +254700000000 starter|business|enterprise
# Creates ERPNext company + user + subscription record for a new POS-Zetu trial client

BIZ_NAME="$1"
EMAIL="$2"
PHONE="$3"
PLAN="${4:-business}"
BENCH=/home/frappe/frappe-bench
SITE=pos.homezetu.com
TRIAL_END=$(date -d '+14 days' +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
SUB_NAME="$(echo $BIZ_NAME | tr ' ' '-' | tr '[:upper:]' '[:lower:]')-$(date +%s)"
TEMP_PASS="PosZetu@$(date +%Y)$(shuf -i 100-999 -n 1)"

if [ -z "$BIZ_NAME" ] || [ -z "$EMAIL" ]; then
  echo "Usage: $0 'Business Name' email@client.com +254700000000 [plan]"
  exit 1
fi

echo "=== Creating client: $BIZ_NAME ==="
cd $BENCH

# 1. Create Company
bench --site $SITE execute frappe.get_doc --args "['Company']" 2>/dev/null
bench --site $SITE mariadb --execute "
INSERT IGNORE INTO \`tabCompany\` (name, owner, creation, modified, modified_by, docstatus, company_name, abbr, default_currency, country)
VALUES ('$BIZ_NAME', 'dkarigi@gmail.com', NOW(), NOW(), 'dkarigi@gmail.com', 0, '$BIZ_NAME', '$(echo $BIZ_NAME | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z' | cut -c1-4)', 'KES', 'Kenya');"

# 2. Create User
bench --site $SITE mariadb --execute "
INSERT IGNORE INTO \`tabUser\` (name, owner, creation, modified, modified_by, docstatus, email, first_name, enabled, user_type, new_password)
VALUES ('$EMAIL', 'dkarigi@gmail.com', NOW(), NOW(), 'dkarigi@gmail.com', 0, '$EMAIL', '$BIZ_NAME', 1, 'System User', '$TEMP_PASS');"

# 3. Assign POS User role
bench --site $SITE mariadb --execute "
INSERT IGNORE INTO \`tabHas Role\` (name, owner, creation, modified, modified_by, docstatus, idx, role, parent, parentfield, parenttype)
VALUES (CONCAT('$EMAIL','-POS User'), 'dkarigi@gmail.com', NOW(), NOW(), 'dkarigi@gmail.com', 0, 1, 'POS Manager', '$EMAIL', 'roles', 'User');"

# 4. Create Subscription record
bench --site $SITE mariadb --execute "
INSERT INTO \`tabPOS Subscription\` (name, owner, creation, modified, business_name, email, phone, company, user, plan, status, trial_start, trial_end, reminded_day10, reminded_day13, reminded_day14)
VALUES ('$SUB_NAME', 'dkarigi@gmail.com', NOW(), NOW(), '$BIZ_NAME', '$EMAIL', '$PHONE', '$BIZ_NAME', '$EMAIL', '$PLAN', 'trial', '$TODAY', '$TRIAL_END', 0, 0, 0);"

echo ""
echo "✓ Client created: $BIZ_NAME"
echo "  Email:      $EMAIL"
echo "  Password:   $TEMP_PASS  (send this to client)"
echo "  Plan:       $PLAN"
echo "  Trial ends: $TRIAL_END"
echo "  Login URL:  https://$SITE/login"
echo ""
echo "  Send this to client:"
echo "  ─────────────────────────────────"
echo "  Welcome to POS-Zetu!"
echo "  Login: https://$SITE"
echo "  Email: $EMAIL"
echo "  Password: $TEMP_PASS"
echo "  Trial ends: $TRIAL_END"
echo "  Support: +254 792 338 173"
echo "  ─────────────────────────────────"
