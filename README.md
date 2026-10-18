# POS-Zetu

Cloud POS system for Kenyan businesses built on ERPNext.

**Live:** https://pos.homezetu.com  
**Contact:** +254 792 338 173 | dkarigi@gmail.com

## Server
- DigitalOcean Droplet: 164.92.69.54 (KwetuPOS)
- Ubuntu 24.10, ERPNext v15
- Bench path: /home/frappe/frappe-bench
- Sites: pos.homezetu.com, staging-site

## Secrets
Passwords are never stored in this repo. On the server, create the secrets file once:
```bash
cp poszetu.env.example /home/frappe/.poszetu.env
chown frappe:frappe /home/frappe/.poszetu.env && chmod 600 /home/frappe/.poszetu.env
nano /home/frappe/.poszetu.env   # fill in SMTP_PASS and DB_ROOT_PASSWORD
```
`upgrade.sh` and `subscription_lifecycle.py` read it and refuse to run without it.

## Upgrade (v15 patch releases only)
```bash
./scripts/upgrade.sh
```
Checks every site is up, refuses to run if frappe/erpnext are not on `version-15`
or have local edits, backs up every site, runs `bench update`, and on failure
rolls back both code and data. Take a droplet snapshot first.

## Onboard a New Client
```bash
./scripts/new_client.sh clientname
```
Creates `clientname.homezetu.com` with full ERPNext + POS.

## Backup All Sites
```bash
./scripts/backup.sh
```

## Pricing
| Plan | Price | Users |
|------|-------|-------|
| Starter | KES 2,000/mo | 1 terminal |
| Business | KES 5,000/mo | 5 terminals |
| Enterprise | KES 10,000/mo | Unlimited |

## Trial Model
- 14-day free trial on signup
- Day 10/13: automated reminder emails
- Day 14: read-only mode
- Day 21: suspended
