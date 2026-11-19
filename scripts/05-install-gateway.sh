#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 05: install Bifrost (AI switchboard with a web page) next to n8n
#
# Run ON THE VM as ubuntu:
#   bash install-gateway.sh          # install / update (web page locked to YOUR IP until you create the admin)
#   bash install-gateway.sh --open   # after creating the admin login: open the page from anywhere
#   bash install-gateway.sh --off    # stop it and take its web page offline (data kept)
#   AI_DOMAIN=ai.example.org bash install-gateway.sh   # use your own name instead of sslip.io
#
# What it does:
#   1. Retires the old LiteLLM gateway (stopped; folder renamed, nothing deleted)
#   2. Starts Bifrost on the private "jarvis" network (n8n reaches it at http://bifrost:8080/v1)
#   3. Publishes ONLY its web page through Apache: https://ai-<ip>.sslip.io (Let's Encrypt)
#      The AI endpoints (/v1 ...) are blocked from the internet.
#   4. fail2ban bans IPs that keep failing the Bifrost login
#   5. Prints a one-time SETUP TOKEN for creating your admin login in the web page
# The SAR site and n8n are not changed.
# =============================================================================
set -euo pipefail

BRANCH="${BRANCH:-main}"
RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/$BRANCH}"
DIR="$HOME/lab/gateway"
ENVF="$DIR/.env"
SITE=/etc/apache2/sites-available/ai-gateway.conf
JAIL=/etc/fail2ban/jail.d/bifrost-login.conf
FILTER=/etc/fail2ban/filter.d/bifrost-login.conf
MODE="${1:-}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; chmod 600 "$ENVF"; }

write_site() {   # $1 = IP to lock to, or empty for open
  local LOCKBLOCK=""
  if [ -n "${1:-}" ]; then LOCKBLOCK="    <Location />
        Require ip $1
    </Location>"; fi
  sudo tee "$SITE" >/dev/null <<EOF
  # free-ai-lab: Bifrost web page published by Apache. AI endpoints stay private (n8n uses them inside the server).
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
  
      # Setup lock: until the admin login exists, only your own IP may open the page
  $LOCKBLOCK
      # AI and metrics endpoints: never from the internet
      <LocationMatch "^/(v1|openai|anthropic|genai|gemini|bedrock|cohere|litellm|langchain|pydanticai|mcp|metrics)(/|$)">
          Require all denied
      </LocationMatch>
  
      ProxyPreserveHost On
      ProxyRequests Off
      RequestHeader set X-Forwarded-Proto "https"
      RewriteEngine On
      RewriteCond %{HTTP:Upgrade} =websocket [NC]
      RewriteRule ^/?(.*) ws://127.0.0.1:8080/\$1 [P,L]
      ProxyPass        / http://127.0.0.1:8080/
      ProxyPassReverse / http://127.0.0.1:8080/
  
      ErrorLog  \${APACHE_LOG_DIR}/ai-gateway-error.log
      CustomLog \${APACHE_LOG_DIR}/ai-gateway-access.log combined
  </VirtualHost>
EOF
  sudo a2ensite -q ai-gateway >/dev/null
  if sudo apache2ctl configtest 2>/dev/null; then sudo systemctl reload apache2; echo "Apache reloaded."
  else sudo a2dissite -q ai-gateway >/dev/null; sudo apache2ctl configtest || true
       die "Apache config test failed, so the gateway site was disabled again. SAR and n8n keep running."; fi
}

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0 $MODE"
command -v docker >/dev/null || die "Docker isn't installed (Lesson 03)."
systemctl is-active --quiet apache2 || die "Apache isn't running."
case "$MODE" in ""|--off|--open) ;; *) die "Unknown option '$MODE'. Use --open, --off or nothing." ;; esac

if [ "$MODE" = "--off" ]; then
  step "Stopping Bifrost and taking its web page offline (data kept in $DIR/data)"
  sudo a2dissite -q ai-gateway >/dev/null 2>&1 || true
  sudo apache2ctl configtest >/dev/null 2>&1 && sudo systemctl reload apache2
  sudo rm -f "$JAIL" "$FILTER"; sudo systemctl restart fail2ban 2>/dev/null || true
  [ -f "$DIR/compose.yaml" ] && (cd "$DIR" && docker compose down >/dev/null 2>&1) || true
  echo "Done."; exit 0
fi

if [ "$MODE" = "--open" ]; then
  step "Opening the Bifrost web page to the internet"
  DOMAIN=$(env_get AI_PUBLIC_HOST); [ -n "$DOMAIN" ] || die "Install first: bash $0"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8080/api/config || true)
  [ "$code" = 401 ] || die "Bifrost answered $code (not 401): the admin password is NOT on yet. In the page: Workspace → Config → Security → 'Password protect the dashboard'. Then run again."
  write_site ""
  echo "Done. https://$DOMAIN now asks for your Bifrost login from anywhere."; exit 0
fi

# ---------- 1. retire LiteLLM ----------
step "1/6  Retiring the old LiteLLM gateway (nothing deleted)"
if [ -d "$HOME/lab/brain" ]; then
  (cd "$HOME/lab/brain" && docker compose down >/dev/null 2>&1) || true
  docker rm -f litellm ollama >/dev/null 2>&1 || true
  mv "$HOME/lab/brain" "$HOME/lab/brain.retired-$(date +%Y%m%d)"
  echo "Stopped; folder kept as ~/lab/brain.retired-$(date +%Y%m%d) (its old keys stay there, private)."
else echo "No old gateway found."; fi

# ---------- 2. name ----------
step "2/6  Public name for the Bifrost web page"
PUBIP=$(curl -fsS --max-time 10 https://ifconfig.me || curl -fsS --max-time 10 https://api.ipify.org) || die "Couldn't find the public IP."
mkdir -p "$DIR"; touch "$ENVF"; chmod 600 "$ENVF"
DOMAIN="${AI_DOMAIN:-$(env_get AI_PUBLIC_HOST)}"
[ -n "$DOMAIN" ] || DOMAIN="ai-$(echo "$PUBIP" | tr . -).sslip.io"
RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)
[ "$RESOLVED" = "$PUBIP" ] || die "$DOMAIN points to '${RESOLVED:-nothing}', not $PUBIP. Choose another: AI_DOMAIN=... bash $0"
env_set AI_PUBLIC_HOST "$DOMAIN"
echo "Web page will be: https://$DOMAIN"

# ---------- 3. Bifrost ----------
step "3/6  Starting Bifrost (private, on the jarvis network)"
if ss -ltnH 'sport = :8080' | grep -q . && ! docker ps --format '{{.Names}}' | grep -qx bifrost; then
  die "Port 8080 is already used by something else: $(sudo ss -ltnp 'sport = :8080' | tail -1)"
fi
curl -fsSL "$RAW/stacks/gateway/compose.yaml" -o "$DIR/compose.yaml"
[ -n "$(env_get BIFROST_SETUP_TOKEN)" ] || env_set BIFROST_SETUP_TOKEN "$(openssl rand -hex 32)"
docker network inspect jarvis >/dev/null 2>&1 || docker network create jarvis >/dev/null
sudo install -d -o 1000 -g 0 -m 770 "$DIR/data"         # Bifrost runs as uid 1000, group 0
(cd "$DIR" && docker compose pull -q && docker compose up -d >/dev/null)
w=0; until curl -fsS --max-time 5 http://127.0.0.1:8080/health >/dev/null 2>&1; do
  (( w >= 120 )) && { docker logs --tail 40 bifrost; die "Bifrost didn't answer on /health."; }; sleep 3; w=$((w+3)); done
echo "Bifrost is running ($(docker stats --no-stream --format '{{.MemUsage}}' bifrost | cut -d/ -f1 | xargs))."
docker exec n8n node -e "fetch('http://bifrost:8080/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null \
  && echo "n8n can reach it at http://bifrost:8080/v1 ✓" || warn "n8n couldn't reach bifrost yet (is n8n on the 'jarvis' network?)"

# ---------- 4. certificate ----------
step "4/6  HTTPS certificate for $DOMAIN"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
sudo apt-get install -y -q certbot python3-certbot-apache fail2ban >/dev/null
if sudo test -d "/etc/letsencrypt/live/$DOMAIN"; then echo "Certificate already exists (auto-renews)."
else sudo certbot certonly --apache -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email \
       || die "Let's Encrypt refused the certificate (see above)."; fi

# ---------- 5. Apache: web page only ----------
step "5/6  Apache site (web page only; AI endpoints blocked from the internet)"
sudo a2enmod -q ssl proxy proxy_http proxy_wstunnel headers rewrite >/dev/null
MYIP="${SSH_CLIENT%% *}"
[ -n "$MYIP" ] || die "Run this over SSH (needed to lock the page to your IP during setup)."
write_site "$MYIP"
echo "Page is locked to your IP ($MYIP) until you create the admin login."

# ---------- 6. fail2ban ----------
step "6/6  fail2ban: ban IPs that keep failing the Bifrost login"
sudo tee "$FILTER" >/dev/null <<'EOF'
[Definition]
failregex = ^<HOST> \S+ \S+ \[[^\]]+\] "POST /api/session/login[^"]*" 401
ignoreregex =
EOF
sudo tee "$JAIL" >/dev/null <<'EOF'
[bifrost-login]
enabled  = true
port     = http,https
filter   = bifrost-login
logpath  = /var/log/apache2/ai-gateway-access.log
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
sudo touch /var/log/apache2/ai-gateway-access.log
sudo systemctl restart fail2ban; sleep 2
if sudo fail2ban-client status bifrost-login >/dev/null 2>&1; then echo "Watching: 5 failed logins in 10 min = banned 1 hour."
else warn "fail2ban jail didn't start; check: sudo fail2ban-client status"; fi

step "Tests"
c1=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/" || true)
c2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST "https://$DOMAIN/v1/chat/completions" || true)
c3=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$PUBIP:8080/" || true)
printf "  %-30s HTTP %s  (403 from the server itself = IP lock works ✓)\n" "https://$DOMAIN/" "$c1"
printf "  %-30s HTTP %s  (403 = AI endpoints blocked from internet ✓)\n" "/v1 from internet" "$c2"
printf "  %-30s HTTP %s  (000 = port 8080 not public ✓)\n" "http://<ip>:8080" "$c3"

step "Done! Do this NOW (until you do, the page has no admin):"
echo -e "  1) Open ${c_ok}https://$DOMAIN${c_off}"
echo "  2) When it asks for the setup token, paste this (don't share it anywhere else):"
echo -e "       ${c_warn}$(env_get BIFROST_SETUP_TOKEN)${c_off}"
echo "  3) Workspace → Config → Security: turn on 'Password protect the dashboard',"
echo "     username + strong password (12+ chars, upper, lower, digit, symbol). Keep 'Enforce Virtual Keys' on."
echo "  4) Back here run:  bash $0 --open   (removes the IP lock; refuses if the password isn't on)"
echo "  Then follow Lesson 05 to add your free providers and connect n8n."
echo "  Undo: bash $0 --off"
