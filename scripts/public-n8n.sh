#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — publish n8n on the internet, safely, next to an existing Apache site
#
# Run ON THE VM as ubuntu:
#   bash public-n8n.sh                      # picks a name automatically
#   N8N_DOMAIN=n8n.example.org bash public-n8n.sh   # or choose the name
#
# What it does (your existing Apache site is NOT changed):
#   1. Picks a free public name for n8n that points at this server
#   2. Gets a free HTTPS certificate (Let's Encrypt) for that name only
#   3. Adds a separate Apache site for n8n with 4 locks:
#        HTTPS only · Apache password prompt · n8n's own login (+2FA) · fail2ban
#      Only /webhook/... paths skip the Apache password (so apps like Telegram can call in)
#   4. Restarts n8n with its new public address (data and credentials are kept)
#   5. Tests: no password -> 401, webhooks reachable, editor works with the password
#
# Undo: bash public-n8n.sh --off   (n8n goes back to server-only)
# =============================================================================
set -euo pipefail

BRANCH="${BRANCH:-main}"
RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/$BRANCH}"
DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
SITE=/etc/apache2/sites-available/n8n-public.conf
HTPASS=/etc/apache2/n8n.htpasswd
JAIL=/etc/fail2ban/jail.d/n8n-apache.conf

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' n8n 2>/dev/null || echo missing; }
restart_n8n() {
  (cd "$DIR" && docker compose up -d --force-recreate >/dev/null)
  local w=0; until [ "$(health)" = "healthy" ]; do
    (( w >= 180 )) && { docker logs --tail 30 n8n; die "n8n didn't come back healthy."; }; sleep 5; w=$((w+5)); done
  echo "n8n restarted and healthy."
}

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
[ -f "$ENVF" ] || die "n8n isn't installed in ~/lab/jarvis (Lesson 08)."
systemctl is-active --quiet apache2 || die "Apache isn't running; this script adds n8n next to your Apache site."

# ---------- --off ----------
if [ "${1:-}" = "--off" ]; then
  step "Taking n8n off the internet"
  sudo a2dissite -q n8n-public >/dev/null 2>&1 || true
  sudo apache2ctl configtest && sudo systemctl reload apache2
  t=$(mktemp); grep -vE '^(COMPOSE_FILE|N8N_PUBLIC_HOST)=' "$ENVF" > "$t" || true; cat "$t" > "$ENVF"; rm -f "$t"
  restart_n8n
  echo "Done. n8n is server-only again (127.0.0.1:5678). Your other Apache site is unchanged."
  exit 0
fi

# ---------- 1. name ----------
step "1/6  Choosing a public name for n8n"
PUBIP=$(curl -fsS --max-time 10 https://ifconfig.me || curl -fsS --max-time 10 https://api.ipify.org) || die "Couldn't find the public IP."
echo "Public IP: $PUBIP"
echo "Existing Apache names (left untouched):"
sudo apache2ctl -S 2>/dev/null | grep -Eo '(namevhost|alias) [^ ]+' | awk '{print "  " $2}' | sort -u || true
DOMAIN="${N8N_DOMAIN:-$(env_get N8N_PUBLIC_HOST)}"
if [ -z "$DOMAIN" ]; then
  SAR=$(sudo apache2ctl -S 2>/dev/null | grep -Eo 'namevhost [^ ]+' | awk '{print $2}' | grep -v -e localhost -e "^n8n\." | head -1 || true)
  case "$SAR" in
    *.duckdns.org) DOMAIN="n8n.$SAR" ;;                                   # DuckDNS answers every sub-name
    *)             DOMAIN="n8n-$(echo "$PUBIP" | tr . -).sslip.io" ;;    # free name that always points at this IP
  esac
fi
echo "n8n will live at: https://$DOMAIN"
RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)
[ "$RESOLVED" = "$PUBIP" ] || die "$DOMAIN points to '${RESOLVED:-nothing}', not $PUBIP. Choose another: N8N_DOMAIN=... bash $0"

# ---------- 2. tools + certificate ----------
step "2/6  HTTPS certificate (Let's Encrypt) for $DOMAIN only"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
sudo apt-get install -y -q certbot python3-certbot-apache apache2-utils fail2ban >/dev/null
if sudo test -d "/etc/letsencrypt/live/$DOMAIN"; then
  echo "Certificate already exists."
else
  sudo certbot certonly --apache -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email \
    || die "Let's Encrypt refused the certificate (see above). If it says 'rate limit', choose another name with N8N_DOMAIN=..."
fi
echo "Renewal is automatic (certbot timer)."

# ---------- 3. password prompt (lock 2) ----------
step "3/6  Apache password (asked before n8n even loads)"
if sudo test -s "$HTPASS"; then
  read -r -p "  A password already exists. Change it? (y/N): " ch
else ch=y; fi
if [ "${ch,,}" = y ]; then
  read -r -p "  Username (Enter = admin): " AUSER; AUSER="${AUSER:-admin}"
  while :; do
    read -r -s -p "  Password (min 12 chars, hidden): " P1; echo
    read -r -s -p "  Same password again: " P2; echo
    [ "$P1" = "$P2" ] && [ ${#P1} -ge 12 ] && break
    warn "Passwords didn't match or were shorter than 12 characters. Try again."
  done
  printf '%s\n' "$P1" | sudo htpasswd -i -B -c "$HTPASS" "$AUSER" >/dev/null
  sudo chown root:www-data "$HTPASS"; sudo chmod 640 "$HTPASS"
  unset P1 P2
  echo "  Saved (bcrypt-hashed) for user '$AUSER'. Keep it in your password manager."
fi

# ---------- 4. Apache site ----------
step "4/6  Apache site for n8n (your other site is not touched)"
sudo a2enmod -q ssl proxy proxy_http proxy_wstunnel headers rewrite auth_basic authn_file >/dev/null
sudo tee "$SITE" >/dev/null <<EOF
# free-ai-lab: n8n published by Apache, next to (not instead of) the existing site.
<VirtualHost *:80>
    ServerName $DOMAIN
    RewriteEngine On
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN
    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    <IfFile "/etc/letsencrypt/options-ssl-apache.conf">
        Include /etc/letsencrypt/options-ssl-apache.conf
    </IfFile>

    # Security headers
    Header always set Strict-Transport-Security "max-age=31536000"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "same-origin"
    Header always set X-Frame-Options "SAMEORIGIN"

    # Reverse proxy to n8n (which only listens on the server itself)
    ProxyPreserveHost On
    ProxyRequests Off
    RequestHeader set X-Forwarded-Proto "https"
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule ^/?(.*) ws://127.0.0.1:5678/\$1 [P,L]
    ProxyPass        / http://127.0.0.1:5678/
    ProxyPassReverse / http://127.0.0.1:5678/

    # Lock 2: password prompt for everything...
    <Location />
        AuthType Basic
        AuthName "Private"
        AuthUserFile $HTPASS
        Require valid-user
    </Location>
    # ...except webhooks, which outside apps (Telegram etc.) must reach. Each has a long random ID.
    <LocationMatch "^/(webhook|webhook-test|webhook-waiting)/">
        Require all granted
    </LocationMatch>

    ErrorLog  \${APACHE_LOG_DIR}/n8n-error.log
    CustomLog \${APACHE_LOG_DIR}/n8n-access.log combined
</VirtualHost>
EOF
sudo a2ensite -q n8n-public >/dev/null
if sudo apache2ctl configtest 2>/dev/null; then
  sudo systemctl reload apache2
  echo "Apache reloaded."
else
  sudo a2dissite -q n8n-public >/dev/null
  sudo apache2ctl configtest || true
  die "Apache config test failed, so the n8n site was disabled again. Your other site keeps running."
fi

# ---------- 5. fail2ban (lock 4) ----------
step "5/6  fail2ban: block password guessers"
sudo tee "$JAIL" >/dev/null <<'EOF'
# free-ai-lab: ban IPs that keep failing the n8n Apache password
[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/n8n-error.log
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
sudo touch /var/log/apache2/n8n-error.log
sudo systemctl enable --now fail2ban >/dev/null 2>&1 || true
sudo systemctl restart fail2ban
sleep 2
sudo fail2ban-client status apache-auth >/dev/null 2>&1 && echo "Watching: 5 wrong passwords in 10 min = banned 1 hour." \
  || warn "fail2ban jail didn't start; check: sudo fail2ban-client status"

# ---------- 6. n8n's public address ----------
step "6/6  Telling n8n its public address"
curl -fsSL "$RAW/stacks/jarvis/compose.public.yaml" -o "$DIR/compose.public.yaml"
[ -n "$(env_get TS_NAME)" ] || env_set TS_NAME localhost      # old Tailscale setting, unused when public
env_set N8N_PUBLIC_HOST "$DOMAIN"
env_set COMPOSE_FILE "compose.yaml:compose.public.yaml"     # docker compose reads both files from now on
chmod 600 "$ENVF"
restart_n8n

step "Tests"
code_noauth=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/")
code_hook=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/webhook/free-ai-lab-check")
printf "  %-44s HTTP %s  (401 = password required ✓)\n" "https://$DOMAIN/" "$code_noauth"
printf "  %-44s HTTP %s  (404 from n8n = webhooks reachable ✓)\n" "https://$DOMAIN/webhook/..." "$code_hook"
[ "$code_noauth" = 401 ] || warn "The editor didn't ask for a password! Run: bash $0 --off   and send the output."

step "Done!"
echo -e "  n8n: ${c_ok}https://$DOMAIN${c_off}"
echo "  1) Open it: your browser asks for the Apache username/password first."
echo "  2) Then log in to n8n as usual."
echo "  3) In n8n: Settings → Personal → Enable 2FA (lock 3). Do this now."
echo "  Undo any time: bash $0 --off"
