#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 09: Jarvis Live — holographic dashboard, digital twin, live voice, working agents
#
# Run ON THE VM as ubuntu (over SSH):
#   bash 09-install-live.sh            # install / update (asks only for what's missing)
#   bash 09-install-live.sh --password # change the page password
#   bash 09-install-live.sh --off      # stop it and take the page offline (settings kept)
#   LIVE_MODEL=<name> bash 09-install-live.sh   # force a specific Gemini Live model
#
# What it does:
#   1. Asks for your free Gemini key (AI Studio, project without billing) and a page password (both hidden)
#   2. Finds a Gemini Live model your key can use, and checks one-time tokens work
#   3. Builds and starts the small "jarvis-live" container (private, port 8090)
#   4. Publishes https://live-<ip>.sslip.io through Apache (Let's Encrypt), fail2ban on the login
#   5. Prints the secret n8n needs for Jarvis's tools (Lesson 09, Part D)
# The SAR site, n8n and Bifrost are not changed.
# =============================================================================
set -euo pipefail

BRANCH="${BRANCH:-main}"
RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/$BRANCH}"
DIR="$HOME/lab/live"
ENVF="$DIR/.env"
SITE=/etc/apache2/sites-available/jarvis-live.conf
JAIL=/etc/fail2ban/jail.d/live-login.conf
FILTER=/etc/fail2ban/filter.d/live-login.conf
MODE="${1:-}"
API=https://generativelanguage.googleapis.com

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; chmod 600 "$ENVF"; }

ask_password() {
  local p1 p2
  while :; do
    read -r -s -p "  Page password (12+ characters, hidden): " p1; echo
    read -r -s -p "  Same password again: " p2; echo
    [ "$p1" = "$p2" ] && [ ${#p1} -ge 12 ] && break
    warn "Didn't match or shorter than 12 characters. Try again."
  done
  env_set LIVE_PASSWORD_HASH "$(PW="$p1" python3 -c '
import hashlib, os
salt = os.urandom(16)
h = hashlib.scrypt(os.environ["PW"].encode(), salt=salt, n=16384, r=8, p=1, dklen=32)
print("scrypt:" + salt.hex() + ":" + h.hex())')"
  echo "  Saved (scrypt-hashed). Keep the password in your password manager."
}

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0 $MODE"
command -v docker >/dev/null || die "Docker isn't installed (Lesson 03)."
systemctl is-active --quiet apache2 || die "Apache isn't running."
case "$MODE" in ""|--off|--password) ;; *) die "Unknown option '$MODE'. Use --password, --off or nothing." ;; esac

if [ "$MODE" = "--off" ]; then
  step "Stopping Jarvis Live and taking its page offline (settings kept in $DIR)"
  sudo a2dissite -q jarvis-live >/dev/null 2>&1 || true
  sudo apache2ctl configtest >/dev/null 2>&1 && sudo systemctl reload apache2
  sudo rm -f "$JAIL" "$FILTER"; sudo systemctl restart fail2ban 2>/dev/null || true
  [ -f "$DIR/compose.yaml" ] && (cd "$DIR" && docker compose down >/dev/null 2>&1) || true
  echo "Done."; exit 0
fi
mkdir -p "$DIR/public"; touch "$ENVF"; chmod 600 "$ENVF"

if [ "$MODE" = "--password" ]; then
  [ -f "$DIR/compose.yaml" ] || die "Install first: bash $0"
  ask_password
  (cd "$DIR" && docker compose up -d --force-recreate >/dev/null)
  echo "Password changed; Jarvis Live restarted (everyone is signed out)."; exit 0
fi

# ---------- 1. secrets ----------
step "1/6  Gemini key and page password"
KEY="$(env_get GEMINI_API_KEY)"
if [ -z "$KEY" ]; then
  echo "  Your free Gemini key from https://aistudio.google.com/apikey (project WITHOUT billing)."
  read -r -s -p "  Gemini API key (hidden): " KEY; echo
  KEY=$(printf '%s' "$KEY" | tr -d '[:space:]')
fi
code=$(curl -s -o /tmp/live-models.json -w '%{http_code}' --max-time 20 "$API/v1beta/models?pageSize=1000&key=$KEY" || true)
[ "$code" = 200 ] || { rm -f /tmp/live-models.json; die "Google refused the key (HTTP $code). Check it in AI Studio and run again."; }
env_set GEMINI_API_KEY "$KEY"
echo "  Key works."
[ -n "$(env_get LIVE_PASSWORD_HASH)" ] || ask_password
[ -n "$(env_get SESSION_SECRET)" ]    || env_set SESSION_SECRET "$(openssl rand -hex 32)"
[ -n "$(env_get N8N_TOOL_SECRET)" ]   || env_set N8N_TOOL_SECRET "$(openssl rand -hex 24)"
[ -n "$(env_get N8N_TOOL_URL)" ]      || env_set N8N_TOOL_URL "http://n8n:5678/webhook/jarvis-live-tool"
if [ -z "$(env_get OWNER_NAME)" ]; then
  read -r -p "  Your first name (how Jarvis calls you): " OWN; env_set OWNER_NAME "${OWN:-friend}"
fi
[ -n "$(env_get LIVE_VOICE)" ] || env_set LIVE_VOICE "Kore"
if [ -z "$(env_get BIFROST_KEY)" ]; then
  echo "  AI agents (Web Scout, Writer, Analyst, Planner) think with your free models through Bifrost (Lesson 05)."
  echo "  Paste a Bifrost virtual key (e.g. your 'smart' key). Enter = skip for now (those agents will say they need it)."
  read -r -s -p "  Bifrost virtual key (hidden): " BK; echo
  BK=$(printf '%s' "$BK" | tr -d '[:space:]'); [ -n "$BK" ] && env_set BIFROST_KEY "$BK"
fi
[ -n "$(env_get BIFROST_URL)" ] || env_set BIFROST_URL "http://bifrost:8080/v1"
[ -n "$(env_get AGENT_MODEL)" ] || env_set AGENT_MODEL "groq/openai/gpt-oss-120b"

# ---------- 2. model ----------
step "2/6  Choosing a Gemini Live model"
if [ -n "${LIVE_MODEL:-}" ]; then MODEL="$LIVE_MODEL"
else
  MODEL=$(python3 - <<'PY'
import json, re
d = json.load(open('/tmp/live-models.json'))
live = [m['name'].split('/', 1)[1] for m in d.get('models', [])
        if 'bidiGenerateContent' in m.get('supportedGenerationMethods', [])]
PREFERRED = 'gemini-3.1-flash-live-preview'   # listed as free of charge on the Gemini API (2026)
def score(n):
    v = re.findall(r'(\d+(?:\.\d+)?)', n)
    return (n == PREFERRED, 'live' in n or 'native-audio' in n, float(v[0]) if v else 0)
live.sort(key=score, reverse=True)
print(live[0] if live else '')
PY
)
fi
rm -f /tmp/live-models.json
[ -n "$MODEL" ] || die "No Live model is available for this key. Try again later, or set LIVE_MODEL=<name>."
env_set LIVE_MODEL "$MODEL"
echo "  Model: $MODEL"
code=$(curl -s -o /tmp/live-token.json -w '%{http_code}' --max-time 20 -X POST "$API/v1alpha/auth_tokens?key=$KEY" \
  -H 'Content-Type: application/json' -d "{\"uses\":1,\"expireTime\":\"$(date -u -d '+5 min' +%FT%TZ)\",\"newSessionExpireTime\":\"$(date -u -d '+1 min' +%FT%TZ)\"}" || true)
if [ "$code" = 200 ] && grep -q '"name"' /tmp/live-token.json; then echo "  One-time tokens work."
else warn "Token test answered HTTP $code: $(head -c 300 /tmp/live-token.json). The page may not connect; send me this line."; fi
rm -f /tmp/live-token.json

# ---------- 3. container ----------
step "3/6  Building and starting jarvis-live (private, port 8090)"
for f in Dockerfile compose.yaml server.mjs public/index.html public/login.html public/login.css public/hud.css public/app.js public/avatar.js public/globe.js public/pcm-worklet.js public/manifest.json public/icon.svg; do
  curl -fsSL "$RAW/stacks/live/$f" -o "$DIR/$f"
done
rm -f "$DIR/public/style.css" "$DIR/public/avatar-placeholder.svg"   # older versions
docker network inspect jarvis >/dev/null 2>&1 || docker network create jarvis >/dev/null
(cd "$DIR" && docker compose build -q && docker compose up -d --force-recreate >/dev/null)
w=0; until curl -fsS --max-time 3 http://127.0.0.1:8090/health >/dev/null 2>&1; do
  (( w >= 60 )) && { docker logs --tail 30 jarvis-live; die "jarvis-live didn't start."; }; sleep 2; w=$((w+2)); done
echo "  Running ($(docker stats --no-stream --format '{{.MemUsage}}' jarvis-live | cut -d/ -f1 | xargs))."

# ---------- 4. name + certificate ----------
step "4/6  Public name and HTTPS certificate"
PUBIP=$(curl -fsS --max-time 10 https://ifconfig.me || curl -fsS --max-time 10 https://api.ipify.org) || die "Couldn't find the public IP."
DOMAIN="${LIVE_DOMAIN:-$(env_get LIVE_PUBLIC_HOST)}"
[ -n "$DOMAIN" ] || DOMAIN="live-$(echo "$PUBIP" | tr . -).sslip.io"
RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)
[ "$RESOLVED" = "$PUBIP" ] || die "$DOMAIN points to '${RESOLVED:-nothing}', not $PUBIP. Choose another: LIVE_DOMAIN=... bash $0"
env_set LIVE_PUBLIC_HOST "$DOMAIN"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
sudo apt-get install -y -q certbot python3-certbot-apache fail2ban >/dev/null
if sudo test -d "/etc/letsencrypt/live/$DOMAIN"; then echo "  Certificate already exists (auto-renews)."
else sudo certbot certonly --apache -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email \
       || die "Let's Encrypt refused the certificate (see above)."; fi

# ---------- 5. Apache ----------
step "5/6  Apache site https://$DOMAIN"
sudo a2enmod -q ssl proxy proxy_http headers rewrite >/dev/null
sudo tee "$SITE" >/dev/null <<EOF
# free-ai-lab: Jarvis Live page published by Apache, next to (not instead of) the existing sites.
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
    Header always set X-Frame-Options "DENY"
    Header always set Permissions-Policy "microphone=(self), camera=()"
    Header always set Content-Security-Policy "default-src 'self'; connect-src 'self' wss://generativelanguage.googleapis.com; img-src 'self' data: blob:; frame-ancestors 'none'"

    # n8n pushes events in over the private network only
    <Location /api/event>
        Require all denied
    </Location>

    ProxyPreserveHost On
    ProxyRequests Off
    RequestHeader set X-Forwarded-Proto "https"
    # live event stream: no buffering, long-lived
    ProxyPass        /api/events http://127.0.0.1:8090/api/events flushpackets=on timeout=86400
    <Location /api/events>
        SetEnv no-gzip 1
    </Location>
    ProxyPass        / http://127.0.0.1:8090/
    ProxyPassReverse / http://127.0.0.1:8090/

    ErrorLog  \${APACHE_LOG_DIR}/live-error.log
    CustomLog \${APACHE_LOG_DIR}/live-access.log combined
</VirtualHost>
EOF
sudo a2ensite -q jarvis-live >/dev/null
if sudo apache2ctl configtest 2>/dev/null; then sudo systemctl reload apache2; echo "  Apache reloaded."
else sudo a2dissite -q jarvis-live >/dev/null; sudo apache2ctl configtest || true
     die "Apache config test failed, so the Live site was disabled again. Other sites keep running."; fi

# ---------- 6. fail2ban ----------
step "6/6  fail2ban: ban IPs that keep failing the Jarvis Live password"
sudo tee "$FILTER" >/dev/null <<'EOF'
[Definition]
failregex = ^<HOST> \S+ \S+ \[[^\]]+\] "POST /login[^"]*" 401
ignoreregex =
EOF
sudo tee "$JAIL" >/dev/null <<'EOF'
[live-login]
enabled  = true
port     = http,https
filter   = live-login
logpath  = /var/log/apache2/live-access.log
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
sudo touch /var/log/apache2/live-access.log
sudo systemctl restart fail2ban; sleep 2
if sudo fail2ban-client status live-login >/dev/null 2>&1; then echo "  Watching: 5 wrong passwords in 10 min = banned 1 hour."
else warn "fail2ban jail didn't start; check: sudo fail2ban-client status"; fi

step "Tests"
c1=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/" || true)
c2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST "https://$DOMAIN/api/token" || true)
c3=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$PUBIP:8090/" || true)
c4=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST "https://$DOMAIN/api/event" || true)
c6=$(docker exec jarvis-live node -e "fetch(process.env.BIFROST_URL+'/models',{headers:{Authorization:'Bearer '+process.env.BIFROST_KEY}}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null && echo yes || echo no)
c5=$(docker exec n8n node -e "fetch('http://jarvis-live:8080/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null && echo yes || echo no)
printf "  %-28s HTTP %s  (200 = sign-in page ✓)\n" "https://$DOMAIN/" "$c1"
printf "  %-28s HTTP %s  (401 = tokens need the password ✓)\n" "token without sign-in" "$c2"
printf "  %-28s HTTP %s  (000 = port 8090 not public ✓)\n" "http://<ip>:8090" "$c3"
printf "  %-28s HTTP %s  (403 = event input blocked from internet ✓)\n" "/api/event from internet" "$c4"
printf "  %-28s %s       (yes = n8n can send events ✓)\n" "n8n → jarvis-live" "$c5"
printf "  %-28s %s       (yes = AI agents can reach your free models ✓)\n" "jarvis-live → Bifrost" "$c6"

step "Done!"
echo -e "  Open: ${c_ok}https://$DOMAIN${c_off}  (sign in, then tap the mic to talk or type in the bar)"
echo "  Add it to your home screen for an app-like icon."
echo
echo "  For the n8n agents, import stacks/jarvis/workflows/jarvis-live-tools.json (Lesson 09, Part E)"
echo "  and give its webhook this secret. Paste it ONLY into n8n:"
echo -e "    Header Auth credential  Name: X-Jarvis-Secret   Value: ${c_warn}$(env_get N8N_TOOL_SECRET)${c_off}"
echo
echo "  Change the password: bash $0 --password     Undo: bash $0 --off"
