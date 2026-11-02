# Design decisions

Short records of the choices behind this course: what we chose, what we didn't, and why. Most were learned the hard way while building the first version of the lab (see [PROGRESS.md](../PROGRESS.md)).

---

## Course v2 (2026-11-01) — restart around one goal

The first version grew lesson by lesson (local chat app first, Jarvis later, the PC added last). The goal is now clear, so the course was rewritten from Lesson 00: **one Jarvis, controlled by text and voice from the phone and the Windows PC, that does tasks only when asked, at $0.** The server's apps were wiped ([`scripts/wipe-apps.sh`](../scripts/wipe-apps.sh)); the server itself, its hardening and Tailscale were kept. Everything that worked in v1 (scripts, fixes) is reused as each new lesson is written and tested.

## One Jarvis, two machines: the server is the brain, the laptop is the hands

| Job | Where | Why |
|---|---|---|
| Telegram front door, routines, cloud tools, voice | **Server** (n8n) | On 24/7; answers even when the laptop is off |
| AI models and all provider keys | **Server** (LiteLLM gateway + Ollama) | One set of keys; the laptop borrows the gateway |
| Apps, files, scripts on the PC; desktop voice | **Laptop** (OpenJarvis) | Only the PC can act on the PC |
| Hard jobs (coding, big automations) | **Laptop**, via Gemini CLI / Claude Code | Uses subscriptions already paid for, only on request |

Connection (checked in OpenJarvis's source, v1.0): OpenJarvis serves an **OpenAI-compatible** `/v1/chat/completions` (`jarvis serve`, Bearer key via `OPENJARVIS_API_KEY`, `127.0.0.1` by default) → published to the **tailnet only**; n8n calls it like any AI model. OpenJarvis's `litellm` engine sends its thinking to our gateway. Tool confirmation stays on (`security.enforce_tool_confirmation = true`), and n8n adds a Telegram **Yes / No** step for irreversible actions. **Only n8n polls the Telegram bot** (two pollers on one bot steal each other's messages), so OpenJarvis's own Telegram channel stays off.

Why OpenJarvis on the laptop, not on the server: it's built for on-device AI (GPU / Apple Silicon); on a 2-CPU server its strengths sit idle. On the laptop they fit: PC tools, approval queue, voice, an OpenAI-compatible API.

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
