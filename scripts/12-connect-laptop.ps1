# =============================================================================
# free-ai-lab - Lesson 12: make OpenJarvis on the laptop think with the SERVER's brain
#
# Run in a NORMAL PowerShell (not "Run as administrator"), after installing OpenJarvis:
#   irm https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/12-connect-laptop.ps1 | iex
#
# What it does:
#   1. Finds your server on Tailscale and checks the gateway answers (https://<server>:4443)
#   2. Asks for the gateway key (hidden), tests it, and saves it for your Windows user only
#   3. Points OpenJarvis at the gateway:  engine = OpenAI-compatible, model = smart
#   4. Asks Jarvis a test question through the server
#
# No AI provider keys are stored on the laptop: only the gateway's key.
# Safe to re-run (e.g. after the key changes).
# =============================================================================

# (No global ErrorActionPreference=Stop: in Windows PowerShell 5.1 it turns any text a program
#  prints to stderr into a fatal error. Each web call below uses -ErrorAction Stop instead.)
function Ok($m)   { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Info($m) { Write-Host "         $m" }
function Step($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "  [fail] $m" -ForegroundColor Red; throw "Stopped: $m" }

$Port = 4443

# ---------------------------------------------------------------------------
Step "1/4  Finding the server's gateway on Tailscale"
if (-not (Get-Command jarvis -ErrorAction SilentlyContinue)) {
    Fail "The 'jarvis' command isn't found. Install OpenJarvis first (Lesson 12, Part C), then open a NEW PowerShell window."
}
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) { $ts = "$env:ProgramFiles\Tailscale\tailscale.exe" }
if (-not $ts) { Fail "Tailscale isn't installed on this laptop (Lesson 11)." }
$server = $null
try {
    $st = (& $ts status --json) -join "`n" | ConvertFrom-Json -ErrorAction Stop
    $suffix = $st.MagicDNSSuffix
    foreach ($p in $st.Peer.PSObject.Properties) {
        if ($p.Value.HostName -eq 'free-ai-lab' -or $p.Value.DNSName -like 'free-ai-lab.*') { $server = $p.Value.DNSName.TrimEnd('.') }
    }
} catch { }
if (-not $server) {
    $server = Read-Host "  Your server's Tailscale name (e.g. free-ai-lab.tailXXXX.ts.net)"
    $server = $server.Trim().TrimEnd('/') -replace '^https?://', ''
}
$base = "https://${server}:$Port"
Info "Gateway address: $base"
try {
    $null = Invoke-WebRequest -UseBasicParsing -Uri "$base/health/liveliness" -TimeoutSec 15 -ErrorAction Stop
    Ok "The gateway answers over Tailscale"
} catch {
    Fail "No answer from $base. On the SERVER run:  sudo tailscale serve --bg --https=$Port http://127.0.0.1:4000   (Lesson 12, Part B). Is Tailscale connected on this laptop?"
}

# ---------------------------------------------------------------------------
Step "2/4  The gateway key"
Info "On the server, show it with:  grep LITELLM_MASTER_KEY ~/lab/brain/.env   (copy only the part after '=')"
$current = [Environment]::GetEnvironmentVariable('VLLM_API_KEY', 'User')
$prompt = if ($current) { "  Gateway key (hidden; Enter keeps the saved one ...$($current.Substring([Math]::Max(0, $current.Length - 4))))" } else { "  Gateway key (hidden)" }
$secure = Read-Host $prompt -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
$key = ($key -replace '\s', '') -replace '^LITELLM_MASTER_KEY=', ''
if (-not $key) { $key = $current }
if (-not $key) { Fail "No key entered." }
try {
    $models = Invoke-RestMethod -Uri "$base/v1/models" -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 20 -ErrorAction Stop
    $names = @($models.data | ForEach-Object { $_.id })
    Ok ("Key works. Brain aliases: " + (($names | Where-Object { $_ -in @('smart','fast','private','general') }) -join ', '))
} catch {
    Fail "The gateway rejected the key (copy it again, only the part after LITELLM_MASTER_KEY=)."
}
[Environment]::SetEnvironmentVariable('VLLM_API_KEY', $key, 'User')   # only your Windows user can read it
$env:VLLM_API_KEY = $key
Ok "Key saved for your Windows user (variable VLLM_API_KEY)"
Remove-Variable key, secure -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Step "3/4  Pointing OpenJarvis at the server's brain"
# OpenJarvis's generic "OpenAI-compatible server" connector is registered under the name 'vllm'.
# Our gateway speaks exactly that language, so we use it (nothing to do with the vLLM software).
& jarvis config set engine.default vllm
& jarvis config set engine.vllm.host $base
& jarvis config set intelligence.default_model smart
if ($LASTEXITCODE -ne 0) { Fail "jarvis config set failed (see above)." }
Ok "OpenJarvis now thinks with 'smart' on your server (free cloud models, automatic fallback)"
Info "Config file: $(& jarvis config path 2>$null)"

# ---------------------------------------------------------------------------
Step "4/4  Test question (through the server)"
& jarvis ask --no-stream "In one short sentence: who are you and where is your brain running?"

Write-Host ""
Write-Host "Done. Open a NEW PowerShell and type  jarvis  to chat. Offline? Use the laptop's own model:" -ForegroundColor Green
Write-Host "  jarvis chat -e ollama -m qwen3.5:4b"
