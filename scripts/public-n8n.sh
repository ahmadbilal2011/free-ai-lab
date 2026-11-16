#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — publish n8n on the internet, safely, next to an existing Apache site
#
# Run ON THE VM as ubuntu:
#   bash public-n8n.sh --fresh   # remove the old n8n + old public setup, deploy a brand-new n8n (recommended)
#   bash public-n8n.sh           # publish the n8n you already have (keeps its workflows)
#   bash public-n8n.sh --off     # take n8n off the internet again
#   N8N_DOMAIN=n8n.example.org bash public-n8n.sh --fresh   # use your own name instead of sslip.io
#
# Locks: HTTPS (Let's Encrypt) · n8n login (owner created from the server, never via a public page)
#        · 2FA (you switch it on) · fail2ban bans IPs that keep failing the login
# Only n8n's own login is used (no extra browser password box; that one kept popping up).
# Your other Apache site (SAR calculator) is never edited.
# Old data is never deleted: --fresh moves it aside to ~/lab/jarvis/n8n.old-<date>.
# =============================================================================
set -euo pipefail

BRANCH="${BRANCH:-main}"
RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/$BRANCH}"
DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
SITE=/etc/apache2/sites-available/n8n-public.conf
OLD_HTPASS=/etc/apache2/n8n.htpasswd
OLD_JAIL=/etc/fail2ban/jail.d/n8n-apache.conf
JAIL=/etc/fail2ban/jail.d/n8n-login.conf
FILTER=/etc/fail2ban/filter.d/n8n-login.conf
MODE="${1:-}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; chmod 600 "$ENVF"; }
env_del() { local t; t=$(mktemp); grep -vE "^($1)=" "$ENVF" > "$t" 2>/dev/null || true; cat "$t" > "$ENVF"; rm -f "$t"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' n8n 2>/dev/null || echo missing; }
up_n8n() {
  (cd "$DIR" && docker compose up -d --force-recreate >/dev/null)
  local w=0; until [ "$(health)" = "healthy" ]; do
    (( w >= 240 )) && { docker logs --tail 40 n8n; die "n8n didn't become healthy."; }; sleep 5; w=$((w+5)); done
  echo "n8n is running and healthy."
}

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0 $MODE"
command -v docker >/dev/null || die "Docker isn't installed (Lesson 03)."
systemctl is-active --quiet apache2 || die "Apache isn't running; this script adds n8n next to your Apache site."
case "$MODE" in ""|--fresh|--off) ;; *) die "Unknown option '$MODE'. Use --fresh, --off or nothing." ;; esac

# ---------- clean the previous public setup (all modes) ----------
step "Removing the previous public n8n setup (the SAR site is not touched)"
sudo a2dissite -q n8n-public >/dev/null 2>&1 || true
sudo rm -f "$SITE" "$OLD_HTPASS" "$OLD_JAIL"
if sudo apache2ctl configtest >/dev/null 2>&1; then sudo systemctl reload apache2
else die "Apache config test fails for a reason not related to n8n. Check: sudo apache2ctl configtest"; fi
sudo systemctl restart fail2ban 2>/dev/null || true
echo "Old browser password box, old n8n site and old jail removed."

if [ "$MODE" = "--off" ]; then
  sudo rm -f "$JAIL" "$FILTER"; sudo systemctl restart fail2ban 2>/dev/null || true
  if [ -f "$ENVF" ]; then env_del "COMPOSE_FILE|N8N_PUBLIC_HOST"; up_n8n; fi
  echo "Done. n8n is server-only again (127.0.0.1:5678)."; exit 0
fi

# ---------- 1. name ----------
step "1/7  Public name for n8n"
PUBIP=$(curl -fsS --max-time 10 https://ifconfig.me || curl -fsS --max-time 10 https://api.ipify.org) || die "Couldn't find the public IP."
DOMAIN="${N8N_DOMAIN:-}"
[ -n "$DOMAIN" ] || DOMAIN="$(env_get N8N_PUBLIC_HOST)"
[ -n "$DOMAIN" ] || DOMAIN="n8n-$(echo "$PUBIP" | tr . -).sslip.io"
RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)
[ "$RESOLVED" = "$PUBIP" ] || die "$DOMAIN points to '${RESOLVED:-nothing}', not $PUBIP. Choose another: N8N_DOMAIN=... bash $0 $MODE"
echo "n8n will live at: https://$DOMAIN"

# ---------- 2. remove old n8n (fresh) ----------
mkdir -p "$DIR"
if [ "$MODE" = "--fresh" ]; then
  step "2/7  Removing the old n8n deployment (data is moved aside, not deleted)"
  if [ -f "$DIR/compose.yaml" ]; then (cd "$DIR" && docker compose down --remove-orphans >/dev/null 2>&1) || true; fi
  docker rm -f n8n >/dev/null 2>&1 || true
  STAMP=$(date +%Y%m%d-%H%M)
  if [ -d "$DIR/n8n" ]; then mv "$DIR/n8n" "$DIR/n8n.old-$STAMP"; echo "Old data kept in: $DIR/n8n.old-$STAMP"; fi
  if [ -f "$ENVF" ]; then cp "$ENVF" "$DIR/.env.old-$STAMP"; chmod 600 "$DIR/.env.old-$STAMP"; fi
  touch "$ENVF"; chmod 600 "$ENVF"
  env_set N8N_ENCRYPTION_KEY "$(openssl rand -hex 32)"   # brand-new instance, brand-new key
else
  step "2/7  Keeping your current n8n (use --fresh for a brand-new one)"
  [ -f "$ENVF" ] || die "No n8n in ~/lab/jarvis. Run: bash $0 --fresh"
fi

# ---------- 3. n8n files ----------
step "3/7  n8n settings"
curl -fsSL "$RAW/stacks/jarvis/compose.yaml"        -o "$DIR/compose.yaml"
curl -fsSL "$RAW/stacks/jarvis/compose.public.yaml" -o "$DIR/compose.public.yaml"
[ -n "$(env_get N8N_ENCRYPTION_KEY)" ] || die "N8N_ENCRYPTION_KEY missing in $ENVF"
[ -n "$(env_get TS_NAME)" ] || env_set TS_NAME localhost        # Tailscale setting, unused while public
[ -n "$(env_get TZ_NAME)" ] || env_set TZ_NAME Asia/Riyadh
env_set N8N_PUBLIC_HOST "$DOMAIN"
env_set COMPOSE_FILE "compose.yaml:compose.public.yaml"
docker network inspect jarvis >/dev/null 2>&1 || docker network create jarvis >/dev/null
sudo install -d -o 1000 -g 1000 "$DIR/n8n"                     # n8n runs as user 1000 inside the container
echo "Saved in $DIR/.env (private, never on GitHub)."

# ---------- 4. certificate ----------
step "4/7  HTTPS certificate for $DOMAIN"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
sudo apt-get install -y -q certbot python3-certbot-apache fail2ban >/dev/null
if sudo test -d "/etc/letsencrypt/live/$DOMAIN"; then echo "Certificate already exists (auto-renews)."
else sudo certbot certonly --apache -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email \
       || die "Let's Encrypt refused the certificate (see above)."; fi

# ---------- 5. Apache site ----------
step "5/7  Apache site for n8n"
sudo a2enmod -q ssl proxy proxy_http proxy_wstunnel headers rewrite >/dev/null
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

    Header always set Strict-Transport-Security "max-age=31536000"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "same-origin"
    Header always set X-Frame-Options "SAMEORIGIN"

    # The owner account is created from the server itself; nobody can do it from the internet.
    <LocationMatch "^/rest/owner/setup">
        Require all denied
    </LocationMatch>

    ProxyPreserveHost On
    ProxyRequests Off
    RequestHeader set X-Forwarded-Proto "https"
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule ^/?(.*) ws://127.0.0.1:5678/\$1 [P,L]
    ProxyPass        / http://127.0.0.1:5678/
    ProxyPassReverse / http://127.0.0.1:5678/

    ErrorLog  \${APACHE_LOG_DIR}/n8n-error.log
    CustomLog \${APACHE_LOG_DIR}/n8n-access.log combined
</VirtualHost>
EOF
sudo a2ensite -q n8n-public >/dev/null
if sudo apache2ctl configtest 2>/dev/null; then sudo systemctl reload apache2; echo "Apache reloaded."
else sudo a2dissite -q n8n-public >/dev/null; sudo apache2ctl configtest || true
     die "Apache config test failed, so the n8n site was disabled again. Your other site keeps running."; fi

# ---------- 6. fail2ban on n8n logins ----------
step "6/7  fail2ban: ban IPs that keep failing the n8n login"
sudo tee "$FILTER" >/dev/null <<'EOF'
[Definition]
failregex = ^<HOST> \S+ \S+ \[[^\]]+\] "POST /rest/login[^"]*" 401
ignoreregex =
EOF
sudo tee "$JAIL" >/dev/null <<'EOF'
[n8n-login]
enabled  = true
port     = http,https
filter   = n8n-login
logpath  = /var/log/apache2/n8n-access.log
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
sudo touch /var/log/apache2/n8n-access.log
sudo systemctl enable --now fail2ban >/dev/null 2>&1 || true
sudo systemctl restart fail2ban; sleep 2
if sudo fail2ban-client status n8n-login >/dev/null 2>&1; then echo "Watching: 5 failed logins in 10 min = banned 1 hour."
else warn "fail2ban jail didn't start; check: sudo fail2ban-client status"; fi

# ---------- 7. start n8n + owner ----------
step "7/7  Starting n8n"
up_n8n
if [ "$MODE" = "--fresh" ]; then
  echo
  echo "Create YOUR n8n login now (typed here on the server, never on a public page)."
  read -r -p "  Email: " OEMAIL
  read -r -p "  First name: " OFIRST; read -r -p "  Last name: " OLAST
  while :; do
    read -r -s -p "  Password (8+ chars, 1 capital, 1 number; hidden): " P1; echo
    read -r -s -p "  Same password again: " P2; echo
    if [ "$P1" = "$P2" ] && [ ${#P1} -ge 8 ] && [[ "$P1" =~ [A-Z] ]] && [[ "$P1" =~ [0-9] ]]; then break; fi
    warn "Didn't match the rules, try again."
  done
  BODY=$(OE="$OEMAIL" OF="$OFIRST" OL="$OLAST" OP="$P1" python3 -c 'import json,os;print(json.dumps({"email":os.environ["OE"],"firstName":os.environ["OF"],"lastName":os.environ["OL"],"password":os.environ["OP"]}))')
  unset P1 P2
  OUT=$(mktemp)
  code=$(curl -s -o "$OUT" -w '%{http_code}' -X POST http://127.0.0.1:5678/rest/owner/setup \
          -H 'Content-Type: application/json' --data-binary @- <<<"$BODY"); unset BODY
  if [ "$code" = 200 ]; then echo "  Owner account created."; else
    warn "Owner setup answered HTTP $code: $(head -c 300 "$OUT")"
    warn "Nobody else can create it (blocked from the internet). Send me this output."; fi
  rm -f "$OUT"
fi

step "Tests"
c1=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/healthz" || true)
c2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST "https://$DOMAIN/rest/owner/setup" || true)
c3=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$PUBIP:5678/" || true)
printf "  %-34s HTTP %s  (200 = n8n reachable over HTTPS ✓)\n" "https://$DOMAIN/healthz" "$c1"
printf "  %-34s HTTP %s  (403 = blocked from internet ✓)\n" "owner setup from internet" "$c2"
printf "  %-34s HTTP %s  (000 = n8n's own port not public ✓)\n" "http://<ip>:5678" "$c3"

step "Done!"
echo -e "  Open: ${c_ok}https://$DOMAIN${c_off}  and log in with the email/password you just set."
echo "  Then: Settings → Personal → Enable 2FA. Do this now."
echo "  Undo: bash $0 --off"
