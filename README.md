# POS-Zetu

Cloud POS system for Kenyan businesses built on ERPNext.

**Live:** https://pos.homezetu.com  
**Contact:** +254 792 338 173 | dkarigi@gmail.com

## Server
- DigitalOcean Droplet: 164.92.69.54 (KwetuPOS)
- Ubuntu 24.10, ERPNext v15
- Bench path: /home/frappe/frappe-bench
- Sites: pos.homezetu.com, staging-site

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
