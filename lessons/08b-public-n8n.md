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

## The locks

| Lock | What it stops |
|---|---|
| 1. HTTPS (free Let's Encrypt certificate, auto-renewed) | nobody can read passwords on the way |
| 2. n8n login, created **from the server** (the public setup page is blocked) | nobody on the internet can claim your empty n8n first |
| 3. **2FA** in n8n (you switch it on) | a leaked password is not enough |
| 4. fail2ban on the n8n login | 5 failed logins in 10 minutes = that IP blocked for 1 hour |
| 5. n8n's own port 5678 stays server-only | the only way in is through Apache + HTTPS |

> **Why no extra Apache password box?** We tried it first. n8n's page loads some files (its app manifest,
> the live-update connection) without the saved browser password, so the box kept popping up again and
> again. n8n's own login + 2FA + fail2ban gives the same protection without that problem.

## Run it (on the VM, as `ubuntu`)

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/public-n8n.sh
bash public-n8n.sh --fresh
```

`--fresh` removes the old n8n and any old public setup, then deploys a brand-new n8n. Old data is **moved**
to `~/lab/jarvis/n8n.old-<date>`, never deleted. (Without `--fresh`, the existing n8n is published as is.)

At the end it asks for your email, name and password (hidden) and creates your n8n login from the server.

**Expected tests at the end**
- `https://<name>/healthz` → **200** ✓
- owner setup from the internet → **403** ✓
- `http://<ip>:5678` → **000** (not reachable) ✓

Then open the link, log in, and go to **Settings → Personal → Enable 2FA**.

## Undo

```bash
bash public-n8n.sh --off
```
n8n goes back to server-only. The SAR site keeps running.

## Useful checks

```bash
sudo fail2ban-client status n8n-login      # who is banned
sudo tail -f /var/log/apache2/n8n-access.log # who is knocking
sudo certbot renew --dry-run                 # certificate renewal works
```
