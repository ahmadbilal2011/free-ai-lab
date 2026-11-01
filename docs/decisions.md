# Design decisions

Short records of important choices: what we chose, what we didn't, and why. Newest first.

---

## 2026-10-28 — Docker Compose now, Kubernetes (K3s) later

**Question:** Should the lab run on Kubernetes with cert-manager and ingress-nginx instead of Docker?

**Decision:** Phase 1 uses **Docker Compose + healthchecks + autoheal**. Kubernetes becomes an optional **Phase 2 track** that migrates the same apps to **K3s**.

**Why:**

| Point | Detail |
|---|---|
| ingress-nginx is retired | The Kubernetes project ended its maintenance in March 2026. New setups should use Traefik (bundled with K3s) or the Gateway API instead. |
| No public HTTPS needed | Everything is private behind Tailscale, which also provides free HTTPS certificates on `*.ts.net`. cert-manager with Let's Encrypt would need a domain and public ports 80/443. |
| RAM goes to the AI | 12 GB total. K3s needs roughly 0.5–1 GB more, which the model needs. |
| Single node | Kubernetes' biggest strength is moving work between servers. With one VM, its self-healing is close to Docker with healthchecks + autoheal. |
| Learning order | Get a working AI first; then learning Kubernetes on apps you already understand is much easier. |

**Self-healing in Phase 1:**

| Failure | Handled by |
|---|---|
| Container crashes | `restart: unless-stopped` |
| Container frozen (healthcheck failing) | autoheal |
| Docker daemon crashes | systemd restarts it |
| Server reboots | Docker starts at boot, containers come back |
| Whole VM lost | Backups (Lesson 07). No single-server setup can avoid this, Docker or Kubernetes. |

**Revisit when:** Phase 1 (Lessons 04–07) is complete.

Sources: [Ingress NGINX retirement — Kubernetes blog](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/), [Kubernetes Steering & Security Response Committees statement](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)

---

## 2026-10-28 — RSA 4096 key created in Cloud Shell

Oracle Cloud Shell runs in FIPS mode, which forbids ED25519 keys. The VM script creates an RSA 4096 key in Cloud Shell, and the user downloads it to Windows. Students who prefer a laptop-created key can pass `SSH_PUBLIC_KEY`.

## 2026-10-28 — Keep Oracle's iptables, no UFW

Oracle advises against UFW on its Ubuntu images (it can conflict with the built-in iptables rules). We keep Oracle's rules and expose nothing publicly except SSH.

## 2026-10-28 — Reach Open WebUI through Tailscale, not a public port

The SSH tunnel was awkward (PC only, window must stay open) and failed on first try. Making port 3000 public would expose the login page to the whole internet over plain HTTP. **Decision:** use Tailscale right after Lesson 04: `tailscale serve` gives tailnet-only HTTPS on `*.ts.net`, works on phone and PC, and opens no inbound port. We don't use `tailscale funnel` (public) for apps. *(Updated 2026-10-30: one narrow exception for Telegram webhooks, see below.)* The SSH tunnel remains documented as a fallback.

## 2026-10-28 — Hybrid AI: free cloud APIs + local fallback

The local 3B model is slow on 2 CPU cores. **Decision:** add free cloud API providers (Groq, Cerebras first; GitHub Models, OpenRouter, Gemini optional) to Open WebUI, and keep Ollama as a private, unlimited fallback. **Privacy rule:** personal data only goes to providers that don't train on prompts. Gemini's free tier trains on data in KSA, so it's for general questions only. Lesson 07 adds LiteLLM for automatic fallback between providers.

## 2026-10-28 — Drop Cerebras and GitHub Models; use NVIDIA Build and OpenRouter

Cerebras now asks for a credit card at signup, which breaks our $0 / no-card rule. GitHub Models was retired by GitHub on 30 July 2026. **Decision:** main providers are **Groq** and **NVIDIA Build (NIM)**, with **OpenRouter** free models as a third, and Gemini optional for general questions. If any provider starts asking for a card, it gets dropped the same way.

## 2026-10-28 — Never hard-code provider model names; discover and test them

The first gateway config used model names from memory. A live diagnosis showed **all of them** had gone: Groq no longer had `llama-3.3-70b-versatile` / `llama-3.1-8b-instant`, NVIDIA's `meta/llama-3.3-70b-instruct` reached end of life on 26 Aug 2026, and OpenRouter's Llama 3.3 70B stopped being free. **Decision:** the installer runs `07-pick-models.py`, which lists each provider's *current* models, ranks them by preference, tests candidates with a tiny request, and generates the config. Apps only ever use our aliases (`smart`, `fast`, `private`), so provider churn never reaches them.

## 2026-10-28 — Backups: restic to Oracle Object Storage, healthchecks.io alerts

Off-server, encrypted, tested, automatic and watched. restic encrypts before upload and deduplicates; Oracle Always Free gives 20 GB of Object Storage via an S3-compatible API. AI models are excluded (re-downloadable). Open WebUI is paused a few seconds so its SQLite file is copied consistently. A healthchecks.io dead man's switch (heartbeat every 5 min + nightly backup ping) emails us when the server or a backup stops, which an on-server monitor can't do. To stay clear of Oracle's A1 idle-reclaim rule, the private model stays loaded (real memory use > 20%) rather than running fake load.

## 2026-10-30 — No self-hosted task app; Jarvis connects to free cloud tools

Lesson 09 was going to self-host Vikunja. **Decision: dropped before installing.** Jarvis doesn't need its own task app: the tasks just need to live somewhere Jarvis can reach, and free cloud tools (calendar, reminders, email) already have polished phone apps and notifications, keep working when our server is down, and n8n has ready-made connectors for them. Self-hosting would add a container to update and back up for little gain. **Principle from now on:** the server hosts only what must be ours (AI gateway, n8n, private model, backups); everything else stays in free cloud tools. Trade-off: that data is stored by those providers, so truly private things go to the local model. Voice moved earlier (Lesson 11) because text **and voice** control is the core of Jarvis.

## 2026-10-30 — Our own Jarvis on n8n, not OpenJarvis; thin server, cloud brains

Goal: maximum quality with minimum server load. **Decision:** the server only coordinates (n8n, LiteLLM gateway, small private model, backups); thinking, speech, images and video run on free cloud APIs. n8n uses its built-in SQLite (no Postgres container) and a 1 GB memory cap. Stanford's OpenJarvis (Apache 2.0) was considered: good ideas (Telegram channel, MCP, scheduler, presets), but it's designed to run models on-device with GPU/Apple Silicon and fine-tune locally, so its strengths would sit idle on a 2-CPU, no-GPU VM. Kept as an optional comparison lesson. The small local model stays: privacy option, last fallback, and keeps memory above Oracle's idle threshold.

## 2026-10-30 — Telegram by polling: n8n reaches out, nothing reaches in

Telegram can deliver messages by **push** (calling a webhook on our server) or **pull** (`getUpdates`). A first version of Lesson 10 used push through a Tailscale Funnel "door" for n8n's webhook paths (it also had a port bug: Telegram only delivers webhooks to 443/80/88/8443). **Withdrawn** before use: it needed a public entry point and server-side networking outside the n8n UI. **Decision:** pull. An n8n workflow long-polls `getUpdates` (20 s wait, every 30 s), **confirms** each batch with `offset = last update_id + 1` *before* calling the AI (no double replies), filters to the owner's user ID, then answers via the gateway. Everything is built in the n8n UI; **no Funnel, no public port**. Costs: ~3k tiny runs/day (successful runs not saved), and the bot token lives in two HTTP node URLs because n8n's Telegram credential can't be used by the HTTP Request node, so the workflow must never be shared with the token in it. n8n's built-in Telegram *Trigger* (push-only) is not used. The n8n editor moved to private port 9443. Earlier decisions mentioning Funnel are superseded by this.

## 2026-10-30 — Telegram Bot API, not the user API

Question: why a bot instead of connecting Telegram's API straight to n8n? A bot *is* that API connection: the Bot API is Telegram's API for programs, and n8n has built-in nodes for it. The alternative, the user API (MTProto) acting as the owner's personal account, needs an extra always-running program on the server (no n8n support), exposes every private chat, turns a leaked key into full account takeover, and risks account limits for automation. **Decision:** Bot API. Acting inside personal chats can be a separate, careful advanced lesson later.

## 2026-10-30 — Voice: cloud ears (Groq Whisper), local voice (Piper)

**Ears:** Groq's free `whisper-large-v3-turbo` (accepts Telegram's OGG directly, multilingual, zero server load), added to the gateway as alias `listen` by the model picker, so keys stay in one place. **Voice:** no free cloud TTS fit: Groq's only covers English and Saudi Arabic (no Urdu); others are small, need a card, or train on data in KSA. **Piper** (open source, built for small CPUs, has en/ar/ur voices) runs as a tiny service with **no host port**, a 768 MB cap, and auto language detection from the reply's letters. Output is converted to OGG/Opus and sent with Telegram's `sendVoice` for a real voice-note bubble. Rule: text in → text out; voice in → text + voice out. Trade-off: Piper sounds slightly robotic; voice notes leave the server for Groq.

## 2026-10-30 — Voice v2: ElevenLabs first, free backups automatic

Real-world test: Groq Whisper **did not understand Ahmad's speech well**. **Decision:** ElevenLabs for both ears (Scribe, `listen`) and voice (Eleven v3, `speak`; the only ElevenLabs model that speaks Urdu), via the gateway so the key stays in one `.env`. The free plan is 10,000 credits/month shared between listening and speaking (≈ 30 min listening or ≈ 10 min speech), personal use only, attribution if published. Backups switch in automatically: `listen-backup` (Groq Whisper) through an n8n error branch, and local Piper inside the voice service, which pauses cloud attempts for an hour after a quota/auth error. Rejected: Azure / Google speech (need a credit card), unofficial "Edge TTS" (uses Microsoft's service without permission). Lesson: test speech models with your own voice and accent.

**Update (2026-11-01):** first real run: Scribe ears worked; the voice failed with ElevenLabs `paid_plan_required`: "Free users cannot use library voices via the API." LiteLLM's `alloy` name maps to a library voice. Fix: use a **pre-made** voice ID (default George `JBFqnCBsd6RMkjVDRZzb`), chosen during install. Diagnosis via `11-diagnose-voice.sh`.

## 2026-11-01 — One Jarvis, two machines: the server is the brain, my laptop is the hands

**Question:** I also want Jarvis to control my Windows PC (and later my phone's apps) by voice, and I tried Stanford's OpenJarvis on the laptop. Separate project, or one?

**Decision: one project.** The Oracle server stays Jarvis's **always-on brain and front door**; my Windows laptop joins as Jarvis's **hands**, running OpenJarvis. They talk only over Tailscale.

| Job | Where | Why |
|---|---|---|
| Telegram front door (text + voice notes), reminders, schedules, cloud tools | **Server (n8n)** | On 24/7, so Jarvis answers even when the laptop is off |
| AI models and keys | **Server (LiteLLM gateway)** | One set of free provider keys; the laptop uses the gateway too, so keys never live on the laptop |
| Opening apps, files, scripts, desktop voice | **Laptop (OpenJarvis)** | Only the PC can act on the PC |
| Hard jobs (coding, big automations) | **Laptop**, handed to Gemini CLI / Claude Code | Uses subscriptions I already pay for, only when needed |

How they connect (checked in OpenJarvis's source, v1.0):

- OpenJarvis serves an **OpenAI-compatible** endpoint (`/v1/chat/completions`, `jarvis serve`). n8n calls it like any other AI model, over Tailscale, with a **Bearer key** (`OPENJARVIS_API_KEY`). By default it listens only on `127.0.0.1`; we publish it to the tailnet only.
- OpenJarvis has a `litellm` engine, so its thinking goes to **our gateway** (`smart` / `fast`), not to separate keys on the laptop.
- OpenJarvis asks before running tools by default (`security.enforce_tool_confirmation = true`). We keep it on, and n8n adds a Telegram **"Yes / No"** step for anything irreversible.
- **Only n8n polls the Telegram bot.** OpenJarvis also has a Telegram channel, but two programs polling one bot steal each other's messages, so the laptop never uses it.

**Why OpenJarvis now, when we rejected it for the server:** the earlier decision is unchanged for the server (on-device AI makes no sense on a 2-CPU VM). On a laptop, its strengths fit: tools that act on the PC, approval queue, voice I/O, an OpenAI-compatible API. Its local models (Ollama) are the laptop's offline fallback.

**Honest limits, recorded up front:**

| Want | Reality |
|---|---|
| "Jarvis calls me" | Telegram and Messenger bots **can't place phone calls**. Free option: a Telegram **voice note** with a loud notification. Real ringing calls need a paid service (e.g. Twilio) → not in a $0 course |
| Jarvis on my phone when the laptop is off | Works for everything the server does; PC jobs wait (or Jarvis says the PC is offline) |
| Gemini Pro / Claude Pro subscriptions | Chat subscriptions, **not API keys**. They power **Gemini CLI** and **Claude Code** on the laptop, used for hard jobs only |
| Control phone apps | Android: possible through ADB from the laptop. iPhone: very limited (Shortcuts) |
| Native Windows install | Needs Python **3.10–3.13** (3.14+ has no numpy wheels yet) and **git** on PATH; WSL2 is smoother but can't easily drive Windows apps, so we use native Windows |

Supersedes: "OpenJarvis kept as an optional comparison lesson" (2026-10-30).

Sources: [OpenJarvis on GitHub](https://github.com/open-jarvis/OpenJarvis), [Native Windows install guide](https://github.com/open-jarvis/OpenJarvis/blob/main/docs/getting-started/windows-native.md)
