#!/usr/bin/env python3
"""
POS-Zetu Subscription Lifecycle Manager
Runs daily via cron. Handles trial reminders, expiry, cleanup.
"""
import os, sys, smtplib, subprocess
from datetime import date, timedelta
from email.mime.text import MIMEText

# Secrets live in /home/frappe/.poszetu.env (see poszetu.env.example), never in git.
# Cron does not load that file, so read it here. Real environment variables win.
ENV_FILE = os.environ.get('POSZETU_ENV', '/home/frappe/.poszetu.env')

def load_env(path):
    values = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                key, value = line.split('=', 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    values.update({k: v for k, v in os.environ.items() if k in values or k.startswith('SMTP_')})
    return values

_env = load_env(ENV_FILE)
if not _env.get('SMTP_PASS'):
    sys.exit(f'SMTP_PASS not set. Create {ENV_FILE} from poszetu.env.example.')

# Config
SMTP_HOST = _env.get('SMTP_HOST', 'mail-eu.smtp2go.com')
SMTP_PORT = int(_env.get('SMTP_PORT', '2525'))
SMTP_USER = _env.get('SMTP_USER', 'homezetu.com')
SMTP_PASS = _env['SMTP_PASS']
FROM_EMAIL = _env.get('FROM_EMAIL', 'homezetu@homezetu.com')
ADMIN_EMAIL = _env.get('ADMIN_EMAIL', 'dkarigi@gmail.com')
SITE = 'pos.homezetu.com'
BENCH = '/home/frappe/frappe-bench'

def send_email(to, subject, html):
    msg = MIMEText(html, 'html')
    msg['Subject'] = subject
    msg['From'] = f'POS-Zetu <{FROM_EMAIL}>'
    msg['To'] = to
    try:
        s = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30)
        s.ehlo(); s.starttls()
        s.login(SMTP_USER, SMTP_PASS)
        s.sendmail(FROM_EMAIL, [to, ADMIN_EMAIL], msg.as_string())
        s.quit()
        print(f'  Email sent to {to}: {subject}')
    except Exception as e:
        print(f'  Email failed: {e}')

def bench_sql(sql):
    r = subprocess.run(
        ['bench', '--site', SITE, 'mariadb', '--execute', sql],
        cwd=BENCH, capture_output=True, text=True
    )
    return r.stdout.strip()

def bench_sql_rows(sql):
    out = bench_sql(sql)
    rows = []
    for line in out.strip().split('\n')[1:]:  # skip header
        if line.strip():
            rows.append(line.strip().split('\t'))
    return rows

def disable_user(user_email):
    bench_sql(f"UPDATE  SET enabled=0 WHERE email='{user_email}'")

def delete_company_data(company, user_email):
    """Nuclear cleanup - delete all company data"""
    print(f'  Deleting company: {company}')
    tables = [
        'tabSales Invoice', 'tabSales Order', 'tabCustomer',
        'tabItem', 'tabStock Ledger Entry', 'tabPOS Profile',
        'tabEmployee', 'tabPayment Entry'
    ]
    for table in tables:
        bench_sql(f"DELETE FROM  WHERE company='{company}'")
    bench_sql(f"DELETE FROM  WHERE name='{company}'")
    bench_sql(f"DELETE FROM  WHERE email='{user_email}'")
    bench_sql(f"UPDATE  SET status='deleted' WHERE company='{company}'")
    print(f'  Company {company} deleted')

today = date.today()
print(f'=== POS-Zetu Lifecycle — {today} ===')

# Fetch all active/trial subscriptions
rows = bench_sql_rows(
    "SELECT name, business_name, email, phone, company, user, plan, status, "    "trial_end, paid_until, reminded_day10, reminded_day13, reminded_day14 "    "FROM  WHERE status IN ('trial','active','expired')"
)

for row in rows:
    if len(row) < 13:
        continue
    name, biz, email, phone, company, user, plan, status, trial_end_s, paid_until_s, r10, r13, r14 = row

    try:
        trial_end = date.fromisoformat(trial_end_s)
    except:
        continue

    days_left = (trial_end - today).days
    print(f'\n{biz} ({email}) — {days_left} days left, status={status}')

    if status == 'trial':
        # Day 10 reminder (4 days left)
        if days_left == 4 and r10 == '0':
            send_email(email,
                f'Your POS-Zetu trial ends in 4 days — {biz}',
                f'<h2>Hi {biz},</h2><p>Your free trial ends on <b>{trial_end}</b>.</p>'
                f'<p>Upgrade now to keep selling. WhatsApp us: <a href="https://wa.me/254792338173">+254 792 338 173</a></p>'
                f'<p>Plans from <b>KES 2,000/mo</b>. Reply to this email or WhatsApp to activate.</p>'
            )
            bench_sql(f"UPDATE  SET reminded_day10=1 WHERE name='{name}'")

        # Day 13 final warning
        elif days_left == 1 and r13 == '0':
            send_email(email,
                f'TOMORROW: Your POS-Zetu goes read-only — {biz}',
                f'<h2>Last chance, {biz}!</h2><p>Tomorrow your POS becomes <b>read-only</b>.</p>'
                f'<p>You will be able to view reports but not process new sales.</p>'
                f'<p><a href="https://wa.me/254792338173?text=I+want+to+upgrade+POS-Zetu">WhatsApp us now to keep selling →</a></p>'
            )
            bench_sql(f"UPDATE  SET reminded_day13=1 WHERE name='{name}'")

        # Day 14 — disable
        elif days_left <= 0 and r14 == '0':
            if user:
                disable_user(user)
            bench_sql(f"UPDATE  SET status='expired', reminded_day14=1 WHERE name='{name}'")
            send_email(email,
                f'Your POS-Zetu trial has ended — {biz}',
                f'<h2>{biz} — Trial Ended</h2><p>Your account is now read-only.</p>'
                f'<p>Your data is safe for <b>30 more days</b>.</p>'
                f'<p><a href="https://wa.me/254792338173?text=I+want+to+activate+POS-Zetu">Activate now from KES 2,000/mo →</a></p>'
            )
            print(f'  {biz}: disabled (trial expired)')

    elif status == 'expired':
        # Day 30 — delete everything
        expiry_plus_30 = trial_end + timedelta(days=30)
        if today >= expiry_plus_30:
            send_email(email,
                f'POS-Zetu: Your data has been deleted — {biz}',
                f'<h2>Account Closed — {biz}</h2><p>Your trial data has been removed.</p>'
                f'<p>You can start fresh anytime: <a href="https://wa.me/254792338173">+254 792 338 173</a></p>'
            )
            if company and user:
                delete_company_data(company, user)
            print(f'  {biz}: DELETED')

print('\n=== Done ===')
