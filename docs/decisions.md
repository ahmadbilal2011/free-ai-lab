# Design decisions

Short records of the choices behind this course: what we chose, what we didn't, and why. Most were learned the hard way while building the first version of the lab (see [PROGRESS.md](../PROGRESS.md)).

---

## Course v2 (2026-11-01) — restart around one goal

The first version grew lesson by lesson (local chat app first, Jarvis later, the PC added last). The goal is now clear, so the course was rewritten from Lesson 00: **one Jarvis, controlled by text and voice from the phone and the Windows PC, that does tasks only when asked, at $0.** The server's apps were wiped (`scripts/wipe-apps.sh`); the server itself, its hardening and Tailscale were kept. Everything that worked in v1 (scripts, fixes) is reused as each new lesson is written and tested.

## One Jarvis, two machines: the server is the brain, the laptop is the hands

| Job | Where | Why |
|---|---|---|
| Telegram front door, routines, cloud tools, voice | **Server** (n8n) | On 24/7; answers even when the laptop is off |
| AI models and all provider keys | **Server** (LiteLLM gateway + Ollama) | One set of keys; the laptop borrows the gateway |
| Apps, files, scripts on the PC; desktop voice | **Laptop** (OpenJarvis) | Only the PC can act on the PC |
| Hard jobs (coding, big automations) | **Laptop**, via Gemini CLI / Claude Code | Uses subscriptions already paid for, only on request |

Connection (checked in OpenJarvis's source, v1.0): OpenJarvis serves an **OpenAI-compatible** `/v1/chat/completions` (`jarvis serve`, Bearer key via `OPENJARVIS_API_KEY`, `127.0.0.1` by default) → published to the **tailnet only**; n8n calls it like any AI model. OpenJarvis's `litellm` engine sends its thinking to our gateway. Tool confirmation stays on (`security.enforce_tool_confirmation = true`), and n8n adds a Telegram **Yes / No** step for irreversible actions. **Only n8n polls the Telegram bot** (two pollers on one bot steal each other's messages), so OpenJarvis's own Telegram channel stays off.

Why OpenJarvis on the laptop, not on the server: it's built for on-device AI (GPU / Apple Silicon); on a 2-CPU server its strengths sit idle. On the laptop they fit: PC tools, approval queue, voice, an OpenAI-compatible API.

**How the laptop reaches the brain (Lesson 12):** the gateway is published to the tailnet with `tailscale serve` on HTTPS **:4443** (Funnel can't publish that port). OpenJarvis uses its generic OpenAI-compatible connector (registered as `vllm`: `engine.default = vllm`, `engine.vllm.host = https://<server>:4443`, key in the Windows user variable `VLLM_API_KEY`), model `smart`. Its built-in "cloud" engine was not used: it only routes genuine OpenAI model names (`gpt-*`) to a custom base URL. The native Windows install compiles a Rust extension and **needs Microsoft C++ Build Tools** (~7 GB); Lesson 11's check now tests for it.

Native Windows, not WSL2: WSL2 is smoother to install but can't easily drive Windows apps. Native needs Python **3.10–3.13** (3.14+ has no numpy wheels yet) and **git**.

Sources: [OpenJarvis](https://github.com/open-jarvis/OpenJarvis), [native Windows guide](https://github.com/open-jarvis/OpenJarvis/blob/main/docs/getting-started/windows-native.md)

## Not in the course (for now)

| Idea | Decision | Why |
|---|---|---|
| Open WebUI (chat web app) on the server | **Dropped** in v2 | Telegram (phone) and OpenJarvis (PC) are the chat apps; one less container to update and back up |
| Self-hosted task app (Vikunja) | **Dropped** | Jarvis connects to the free cloud tools already in use (calendar, reminders, email): polished apps, work when the server is down, n8n connectors exist. The server hosts only what must be ours |
| WhatsApp (2 accounts): Jarvis reads and replies to my chats | **Postponed** (2026-11-02) | No free, official, ban-free way exists for *personal* chats: unofficial QR-linked bridges (WAHA, Evolution API, Baileys) break WhatsApp's terms and bans are permanent; the official Cloud API only works with Business numbers, needs a public webhook and can't see groups. **Plan:** in Part 4, Jarvis uses the **WhatsApp desktop app on the laptop**, with Yes / No before sending. To check again then: what WhatsApp's terms say about automating its desktop app, and what's possible for calls |
| Facebook Messenger: Jarvis reads my unread messages and replies | **Postponed to the laptop part** (2026-11-02) | Meta's Messenger API only covers Facebook **Pages**, not personal inboxes (the inbox-reading permission was removed years ago). Unofficial libraries (`fbchat`, `fca`) log in as me with my password or cookies: against Facebook's terms, risk of lock / ban, the server would hold my login, and default end-to-end encryption often blocks them anyway. **Plan:** the laptop reads Messenger in my own logged-in browser, only when asked, drafts → I approve → it sends |
| Controlling phone apps via ADB | **Not used** | Owner's choice: the phone won't be wired to the laptop for Jarvis. A Jarvis phone app of our own may come later |
| "Jarvis calls me" (real phone calls) | **Not possible for free** | Telegram / Messenger bots can't place calls. Free option: a Telegram voice note with a loud notification. Real calls need paid services (e.g. Twilio) |
| Telegram user API (acting as my own account) | **Rejected** | Needs an extra program, sees every private chat, a leaked key = account takeover, automation can get the account limited. Bot API instead |
| Unofficial "Edge TTS" | **Rejected** | Uses Microsoft's service without permission |

## Private by default: Tailscale, never Funnel

Only SSH is public. Server, laptop and phone share a Tailscale tailnet; apps are published with `tailscale serve` (tailnet-only HTTPS on `*.ts.net`). `tailscale funnel` (public) is never used. An SSH tunnel was tried first in v1 and was awkward (PC only, window must stay open).

## Telegram by polling: n8n reaches out, nothing reaches in

Telegram can **push** (call a webhook on our server, which needs a public door) or be **pulled** (`getUpdates`). v1 first built push through a Funnel door (and found Telegram only delivers to ports 443/80/88/8443), then withdrew it. **Decision: pull.** n8n long-polls (20 s wait, every 30 s), **confirms** each batch (`offset = last update_id + 1`) *before* calling the AI so nothing is answered twice, and only accepts the owner's user ID. Trade-off: n8n's Telegram nodes can't poll, so the two Telegram requests are HTTP nodes and the bot token sits in their URLs (inside n8n's database, never in a file); that workflow is never shared with the token in it.

**v2 (2026-11-02): inside n8n, everything happens in the UI.** A first v2 draft had a shell installer that imported and published the workflow; the owner rejected it: n8n runs permanently in Docker, the shell is only for installing or updating containers, and everything *inside* n8n is done in its web UI. Now: **Import from URL** (a template on GitHub with a placeholder instead of the token), paste the token into **one Settings node**, pick the gateway credential, **Publish**. Setup mode (`OWNER_ID = 0`) makes Jarvis reply with the sender's user ID, so no extra tool is needed to find it. A failed poll automatically removes a leftover webhook. The AI call uses the OpenAI-type credential (no key in the workflow); memory is the workflow's static data (last 10 exchanges, `/new` resets). n8n 2.x renamed "Active" to **Publish**. **Speed:** checks every 10 s, each holding the line open 8 s (first version: every 30 s / 20 s left gaps of up to 10 s with nobody listening). Typical reply 1–4 s, about 8,600 tiny runs a day; truly instant would need a webhook (public door), so no.

## Hybrid AI: free cloud models first, private model last

The server has 2 Arm CPUs and no GPU: a local 3B model is slow. **Decision:** free cloud APIs do the thinking; Ollama keeps a small model on the server as a private, unlimited last fallback (and its memory use keeps the VM clear of Oracle's idle-reclaim rule, `OLLAMA_KEEP_ALIVE=-1`).

Rules learned in v1:

- **No credit card, ever.** Cerebras asked for one → dropped. GitHub Models was retired (30 July 2026) → dropped. Current: **Groq**, **NVIDIA Build**, **OpenRouter** free models; **Gemini** optional.
- **Privacy rule:** personal data (calendar, email, tasks) only goes to providers that don't train on it, or stays local. Gemini's free tier trains on data in KSA → general questions only.
- **Never hard-code model names.** In v1 every hard-coded model had disappeared within weeks (removed, end-of-life, or no longer free). The installer discovers each provider's *current* models, tests them, and writes the config. Apps only use our aliases (`smart`, `fast`, `private`, `listen`, `speak`).
- **"OpenAI-compatible" is just a request format.** No OpenAI account needed.

## Voice: ElevenLabs first, free backups automatic

**v2 (2026-11-02):** same design on the new layout: keys in `~/lab/brain/.env`, voice service on the `jarvis` network, no port. The Telegram workflow gained a voice path in the n8n UI (import the new version): voice note → download → rename `.oga` to `.ogg` → `listen` → normal message marked "by voice" → brain (short, speakable answer) → text reply with 🎙️ transcript + voice note. Voice notes over 2 minutes are refused to save credits.


Groq Whisper didn't understand the owner's speech well. **Ears:** ElevenLabs Scribe; **voice:** ElevenLabs Eleven v3 (speaks Urdu). Free plan: 10,000 credits/month shared (≈ 30 min listening or ≈ 10 min speech), personal use. Backups switch in automatically: Groq Whisper (ears) and local **Piper** (voice: en/ar/ur, no host port, 768 MB cap). Lessons from v1: free ElevenLabs accounts must use a **pre-made** voice via the API (library voices return `paid_plan_required`), and the API needs the **secret key** (`sk_…`), not the Key ID. Text in → text out; voice in → text + voice out. Test speech models with your own voice and accent.

## Backups: restic to Oracle Object Storage, healthchecks.io alerts

Off-server, encrypted, deduplicated, nightly, restore-tested. Oracle gives 20 GB Object Storage (S3-compatible). AI models are excluded (re-downloadable). A healthchecks.io dead man's switch emails when the server or a backup stops, which an on-server monitor can't do.

## Thin server

n8n uses its built-in SQLite (no Postgres) with a 1 GB memory cap; every app has a memory cap; autoheal restarts frozen containers. Whatever can live in a free cloud tool stays there.

## Docker Compose now, Kubernetes (K3s) later

Single node, no public HTTPS needed (Tailscale gives certificates), and RAM goes to the AI. **Phase 1:** Docker Compose + healthchecks + autoheal. **Phase 2 (optional):** migrate to K3s with Traefik / Gateway API; **ingress-nginx was retired in March 2026**, so it isn't used. Sources: [Ingress NGINX retirement](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/), [statement](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)

## Small server decisions

- **RSA 4096 key, created in Cloud Shell:** Oracle Cloud Shell runs in FIPS mode, which forbids ED25519 keys.
- **No UFW:** Oracle advises against it on its Ubuntu images; we keep Oracle's iptables rules.
- **Swap 4 GB:** safety net when the private model loads.

## 2026-11-16 — n8n public through Apache (Tailscale paused)

- The SAR→PKR calculator stays live as is on the same VM (Apache on 80/443). The AI lab runs beside it.
- Tailscale is skipped for now; n8n is published through the **existing Apache** on its own name
  (`n8n-<ip>.sslip.io` by default), so no new ports and the SAR site's config isn't touched.
- Locks: HTTPS (Let's Encrypt), n8n login created from the server (public owner-setup blocked), 2FA, fail2ban on `/rest/login` 401s.
- **Apache Basic Auth was dropped the same day:** the browser kept asking for it again and again, because n8n loads some
  files (manifest, live-update connection) without the saved credentials. n8n was redeployed fresh (`--fresh`); old data moved aside.
- n8n still binds to `127.0.0.1:5678`; public settings live in `compose.public.yaml`, switched on by
  `COMPOSE_FILE` in `.env` and off with `public-n8n.sh --off`.

## 2026-11-18 — Bifrost replaces LiteLLM as the AI switchboard

- Wanted: add many free AI providers/models **in a web page**, with n8n using them automatically. LiteLLM needed config
  files (its web admin needs Postgres) → **Bifrost** (open source, Go, one container ~160 MB, built-in web page and login).
- n8n uses one address on the private network (`http://bifrost:8080/v1`). Levels of work = Bifrost virtual keys
  (`quick`, `smart`, `code`), one n8n credential each. Bifrost handles fallback between providers.
- Web page public over HTTPS with Bifrost's own login + fail2ban; locked to the installer's IP until the admin exists.
  AI endpoints blocked from the internet so nobody can spend the free quotas.
- Old LiteLLM stack stopped and its folder renamed (`~/lab/brain.retired-<date>`), nothing deleted.

## 2026-11-19 — Telegram by Trigger, voice with free backups, live talk planned

- n8n is public, so Telegram uses n8n's **Telegram Trigger** (instant webhook) instead of polling every 10 s. Token in an
  encrypted credential. Only-me check = sender ID **equals** my ID ("is not empty" would let anyone in).
- Listening: ElevenLabs Scribe first; on error → **Gemini** transcription (free). Speaking: ElevenLabs first; on error →
  **Gemini TTS** (free) turned into WAV by a Code node. Both voices failing still leaves a text reply.
- Real-time talk: **Jarvis Live** later, with the Gemini Live API (free tier) and n8n webhooks as tools. ElevenLabs
  Agents rejected (only ~15 free minutes a month). The Gemini app's Live mode covers general chat meanwhile.
- No customer (SAR) data goes to free AI tiers that may train on it.

## 2026-11-19 — Repo cleanup

- Replaced content removed instead of kept with "replaced" banners: LiteLLM gateway + model picker, polling Telegram,
  the separate voice service, the old keys script and `wipe-apps.sh`. They remain in git history.
- Lessons renumbered 00–11 in the order they're actually done; n8n's two lessons merged into one (06); the n8n stack
  is now a single compose file (public settings built in). The n8n installer also starts autoheal.

## 2026-11-20 — Backups as local .zip files instead of Object Storage

- Chosen: nightly `.zip` in `/data/backups` on the server (root-only, newest 14 kept, n8n and Bifrost stopped for a
  few seconds for consistent SQLite copies). Simpler than restic + bucket keys + an encryption password.
- Accepted limit: the zips share the server's disk, so they cover mistakes, not losing the VM. Mitigation: copy a zip
  to the laptop monthly and before big changes (one PowerShell line in Lesson 08).
- healthchecks.io alerts dropped for now; `lab-status` shows the age of the last backup.

## 2026-11-20 — Jarvis Live design

- Small dependency-free Node container: password page (scrypt hash, signed cookie), `/api/token` mints single-use
  Gemini Live tokens (v1alpha `auth_tokens`, 1 min to start, 30 min max), `/api/tool` forwards to n8n with a secret.
- The browser streams audio straight to Google (WebSocket, 16 kHz in / 24 kHz out): lowest delay, no audio load on the server.
- Tools are an allow-list of two; skills grow inside one n8n workflow shared by Telegram and Live.
- Model picked at install from what the key can use, preferring `gemini-3.1-flash-live-preview` (listed as free).

## 2026-11-20 — Jarvis Live becomes the "personal AI OS" dashboard

- Spec given: orchestrator + sub-agents, event-driven, full-duplex voice + text, RAG, holographic HUD with an animated
  avatar of the user. Decisions taken with the user:
  - **Orchestrator: free now** (Gemini Live), Claude later as a paid premium pool via Bifrost. The Claude API has no free tier.
  - **Avatar: own photo animated in the browser** (breathing, ripple, jaw + waveform from the real voice). True lip-sync
    needs a GPU or a paid service that would also receive the user's face.
  - **Scope:** dashboard + agents + live events now; RAG as Lesson 17.
- Agents = one n8n workflow routed by agent name (`ask_agent` tool, parallel calls); System Monitor built in.
  Events: SSE to screens; n8n pushes via `/api/event` (private network + secret, blocked at Apache).

## 2026-11-20 — Digital twin, globe, and agents that do real work

- Photo avatar replaced by a **vector digital twin** (cap, beard, striped shirt) per the user's request: animated blinks,
  gaze, breathing, ripple, and mouth shapes from voice loudness and pitch. No face data uploaded anywhere.
- Agent graph replaced by a **dotted holographic globe** (continents from simplified outlines in code; map packages
  weren't reachable) with the server marked and an orbit ring of agents; arcs and pulses for working agents.
- **AI agents run in jarvis-live** on free models through Bifrost (Web Scout with web search + page reading, Writer,
  Analyst, Planner); n8n agents come from one importable workflow (Messenger live; others stubbed for later lessons).
- Design pass: sentence-case titles, technical display face (Bahnschrift, already on Windows), tabular numbers,
  boldness spent on the twin.

## 2026-11-20 — No built-in agents; agents come from n8n; original avatar

- User asked: no face, use something creative; no agents until their lessons; must connect to the n8n from Lesson 06.
- Avatar: an **original AI sentinel** (faceted helm, visor eyes, voice-grille bars, orbit ring). Film characters such as
  Transformers aren't reproduced (studio-owned designs).
- jarvis-live has **no agents of its own**: it asks n8n `GET /webhook/jarvis-agents` for the list (refresh every 60 s,
  on each call, on the ↻ button, or when n8n posts `{ "refresh": true }`) and sends tasks to `POST /webhook/jarvis-live-tool`.
  The starter workflow `jarvis-agents.json` lists none. With no agents, Jarvis is told not to pretend to act.
- Built-in AI agents (Web Scout, Writer, Analyst, Planner) and the Bifrost key prompt removed; future AI agents are
  built in n8n with Bifrost models, so Telegram and Live share the same agents.

## 2026-11-20 — Jarvis thinks with Bifrost

- User asked that Jarvis communicate through Bifrost (Lesson 05). Jarvis Live now has **two brains**, chosen at the top:
  **Bifrost** (default: free models with fallback; text, browser speech-to-text in English/Urdu, replies read aloud by the
  device) and **Gemini Live** (real-time voice calls). Both call the same n8n agents (OpenAI-style tool calls through Bifrost).
- The Bifrost key and `CHAT_MODEL` live only in `~/lab/live/.env`; the browser never sees them. Claude later = one Bifrost model.

## 2026-11-20 — Pick as many models as you like; setup lock fix

- Jarvis's Bifrost brain uses a **model list chosen on the dashboard** (Models dialog: all models Bifrost offers, add/order/remove),
  saved in `~/lab/live/data/settings.json`. Jarvis tries them in order and moves on when one is busy, out of quota or failing.
- Bifrost page "Forbidden": the setup lock used the SSH client's IP (Cloud Shell ≠ browser). New `05-install-gateway.sh --allow [IP]`
  reads the last blocked IP from Apache's log (with confirmation) and unlocks it.

## 2026-11-20 — Bifrost page: unlock link instead of an IP lock

- The IP lock (and `--allow`) still failed for the user: IPs differ between Cloud Shell, laptop and phone and change over
  time. Replaced with: **admin login exists → page fully open, Bifrost's login protects it**; **no admin yet → private
  unlock link** (`?unlock=<token>` sets a 24 h cookie via Apache mod_rewrite; any IP). The installer detects which case applies.

## 2026-11-20 — Jarvis Live: AI providers you configure yourself

- The Models dialog only listed what Bifrost reported, so the user couldn't add or fix providers from Jarvis. Replaced
  with an **AI providers** screen: add / edit / delete / test any OpenAI-compatible provider (ready-made: Groq, Google
  Gemini, OpenRouter, NVIDIA, Mistral, Cerebras, SambaNova, Cohere, Cloudflare, Bifrost; or custom), **Fetch models**
  or type names, and one ordered line of models **across providers** with fallback.
- Bifrost is now **optional**: just one provider. The installer no longer asks for a Bifrost key; older installs are
  migrated (the Bifrost key and chosen models become the first provider).
- Keys are stored in `~/lab/live/data/providers.json` (mode 600) and never returned to the browser (last 4 only).
- Addresses must be `https://`; `http://` only for single-name hosts inside the server (`http://bifrost:8080/v1`).
