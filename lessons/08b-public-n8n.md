# Lesson 08b — Put n8n on the internet, safely (next to an existing website)

**Why:** Tailscale is skipped for now. n8n must be reachable from any browser and phone, and outside apps
(Telegram, forms, other services) must be able to call its webhooks. The server also hosts another public
Apache website (the SAR→PKR calculator) that **must keep running untouched**.

## The idea in one picture

```
Internet ──► Apache :443 ──┬── sar site (unchanged, its own name + certificate)
                           └── n8n-<ip>.sslip.io ──► 127.0.0.1:5678 (n8n, never public itself)
```

Apache already owns ports 80/443, so it becomes the single public door for n8n too, on a **separate name**.
`sslip.io` is a free service: `n8n-1-2-3-4.sslip.io` always points to IP `1.2.3.4`, so we don't have to buy a
domain. (Have your own domain? Point a name at the server and pass `N8N_DOMAIN=n8n.yourdomain.com`.)

## Four locks

| Lock | What it stops |
|---|---|
| 1. HTTPS (free Let's Encrypt certificate, auto-renewed) | nobody can read passwords on the way |
| 2. Apache password prompt before n8n even loads | bots never see n8n's login page or bugs in it |
| 3. n8n's own login **+ 2FA** (you switch it on) | a leaked Apache password is not enough |
| 4. fail2ban | 5 wrong passwords in 10 minutes = that IP blocked for 1 hour |

Only `/webhook/...` paths skip lock 2, because Telegram can't type a password. Every webhook has a long
random ID, and a workflow only answers while it is active.

## Run it (on the VM, as `ubuntu`)

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/public-n8n.sh
bash public-n8n.sh
```

It asks for a username and a password (min 12 characters, typed hidden). Save them in a password manager.

**Expected tests at the end**
- `https://<name>/` → **HTTP 401** (password required) ✓
- `https://<name>/webhook/...` → **HTTP 404** from n8n (webhooks reachable) ✓

Then open the link, enter the Apache password, log in to n8n and go to **Settings → Personal → Enable 2FA**.

## What changed on the server

- New Apache site `/etc/apache2/sites-available/n8n-public.conf` (the SAR site's files are not edited)
- Password file `/etc/apache2/n8n.htpasswd` (bcrypt-hashed)
- fail2ban jail `/etc/fail2ban/jail.d/n8n-apache.conf`
- `~/lab/jarvis/compose.public.yaml` + two lines in `~/lab/jarvis/.env`
  (`N8N_PUBLIC_HOST`, `COMPOSE_FILE`) so n8n knows its public address

Your workflows and saved credentials are kept; n8n is only restarted.

## Undo

```bash
bash public-n8n.sh --off
```
n8n goes back to server-only. The SAR site keeps running.

## Useful checks

```bash
sudo fail2ban-client status apache-auth      # who is banned
sudo tail -f /var/log/apache2/n8n-access.log # who is knocking
sudo certbot renew --dry-run                 # certificate renewal works
```
