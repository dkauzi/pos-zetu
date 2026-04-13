#!/bin/bash
# Usage: ./new_client.sh clientname
# Creates a new ERPNext site for a POS-Zetu client
CLIENT=$1
SITE="${CLIENT}.homezetu.com"
BENCH=/home/frappe/frappe-bench

if [ -z "$CLIENT" ]; then
  echo "Usage: $0 <clientname>"
  exit 1
fi

echo "Creating site: $SITE"
cd $BENCH
bench new-site $SITE \
  --mariadb-root-password $(cat /etc/frappe_db_root 2>/dev/null || echo "enter-root-password") \
  --admin-password Admin@PosZetu123 \
  --install-app erpnext

bench --site $SITE install-app hrms 2>/dev/null || true

echo "Site $SITE created. Add to nginx with: bench setup nginx && sudo nginx -s reload"
