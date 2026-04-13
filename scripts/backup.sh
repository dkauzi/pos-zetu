#!/bin/bash
# Daily backup of all sites
cd /home/frappe/frappe-bench
for site in sites/*/; do
  site=$(basename $site)
  if [ -f "sites/$site/site_config.json" ]; then
    echo "Backing up $site..."
    bench --site $site backup --with-files 2>/dev/null
  fi
done
echo "Backup complete. Files in sites/*/private/backups/"
