#!/bin/bash
# Reset demo POS opening entry daily so demo users never get stuck
cd /home/frappe/frappe-bench
bench --site pos.homezetu.com mariadb --execute "
  UPDATE \`tabPOS Opening Entry\`
  SET status='Open', period_start_date=NOW(), posting_date=CURDATE(), modified=NOW()
  WHERE name='DEMO-POS-OPEN-001';
  DELETE FROM \`tabPOS Invoice\` WHERE pos_opening_entry='DEMO-POS-OPEN-001' AND docstatus=0;
" 2>/dev/null
echo "Demo reset done: $(date)"
