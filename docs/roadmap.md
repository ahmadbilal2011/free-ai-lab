# Course roadmap: from a free server to my own "Jarvis"

The goal: **my own "Jarvis"**: one assistant I control by **text and voice**, from my phone and PC, that **does things** for me (including on my Windows PC and phone apps) (plans my day, reminds me, searches, writes, codes, creates images and video, posts to social media with my approval) at **$0 cost**.

Design principle: the server runs only what *must* be ours (the AI gateway, the automation engine, the private model, backups). Everything else (calendar, tasks, email, storage, social media) stays in the **free cloud tools I already use**, and Jarvis connects to them.

Rules for the whole course:

- **$0.** Open-source software, Oracle Always Free, and free API tiers only.
- **Private by default.** Everything sits behind Tailscale; no public ports.
- **Hybrid AI.** Fast free cloud models for general work; the local model stays as a private, unlimited fallback.
- **Privacy rule:** personal data (tasks, emails, calendar) only goes to providers that **don't train on it**, or stays local.
- **Jarvis asks before acting.** Anything irreversible (sending, posting, deleting) needs my approval. No payments, ever.
- **Secrets never touch GitHub.** API keys live in `.env` files or app settings on the server.
- **Free tiers change.** Every lesson re-checks the provider's current limits before we rely on it.

---

## Part 1 — Foundation ✅

| # | Lesson |
|---|---|
| 00 | Core concepts |
| 01 | Create the Oracle VM (one Cloud Shell command) |
| 02 | Secure the server |
| 03 | Docker |
| 04 | Local AI: Ollama + Open WebUI + autoheal |
| 05 | Tailscale: private HTTPS on laptop and phone |

## Part 2 — Smart AI for free

| # | Lesson | What I get |
|---|---|---|
| 06 | **Free cloud AI via API keys** (Groq, NVIDIA, OpenRouter, + optional Gemini) | Fast, smart chat in Open WebUI today |
| 07 | **LiteLLM gateway** | One endpoint for every provider, automatic fallback when a free limit is hit, usage logs |
| 08 | **Backups and monitoring** | Chats, settings and keys are safe before Jarvis gets my data |

## Part 3 — Jarvis's nervous system and front door

| # | Lesson | What I get |
|---|---|---|
| 09 | **n8n basics**: self-hosted automation engine, workflows, triggers, credentials, connected to my AI gateway | The engine every Jarvis skill runs on |
| 10 | **Telegram bot: text Jarvis from anywhere** | Message Jarvis on my phone; it answers using `smart` |
| 11 | **Voice in, voice out**: free speech-to-text and text-to-speech | Send a voice note → Jarvis understands and can reply with voice |

## Part 4 — Jarvis on my PC (the laptop joins as Jarvis's hands)

Design: [decisions.md — One Jarvis, two machines](decisions.md). The server stays the brain and front door; the Windows laptop runs OpenJarvis and acts only when told.

| # | Lesson | What I get |
|---|---|---|
| 12 | **Prepare the Windows laptop**: clean old installs, Python 3.13, git, Ollama, one check script | A laptop ready for OpenJarvis, and the reasons installs failed |
| 13 | **OpenJarvis on the laptop**, thinking through the server's gateway (no keys on the laptop) | Jarvis chat on the PC, using the same free models as Telegram |
| 14 | **Server → laptop over Tailscale**: n8n sends PC jobs to OpenJarvis with a key, **Yes / No on Telegram** before anything irreversible | "Open my QA report", "zip yesterday's screenshots" from my phone |
| 15 | **Talk to Jarvis at the desk**: microphone in, spoken replies out | Voice control on the PC itself |
| 16 | **Hard jobs**: hand off to Gemini CLI / Claude Code (my subscriptions), only when asked | Coding and big automations without API bills |
| 17 | **Phone apps** (Android, via ADB from the laptop), optional | Jarvis taps through Android apps when I ask |

## Part 5 — Jarvis does things

| # | Lesson | What I get |
|---|---|---|
| 18 | **Agents and tools**: n8n AI Agent, function calling, MCP, **approval before any action** | Jarvis decides which tool to use, and asks before acting |
| 19 | **Connect my free cloud tools** (calendar, tasks/reminders, email, web search: the ones I already use) | "Remind me tomorrow at 9", "What's on my calendar?", "Search the web for…" |
| 20 | **Memory and knowledge (RAG)** | Jarvis remembers my preferences and can answer from my own notes and documents |

## Part 6 — Jarvis creates

| # | Lesson | What I get |
|---|---|---|
| 21 | **Free image generation** (free API tiers, checked when we get there) | "Make an image of…" from Telegram |
| 22 | **Video generation**: what's honestly possible for free | Short clips / slideshow-style videos; real limits explained |
| 23 | **Social media posting** via official APIs, **draft → I approve → it posts** | Hands-free posting, within each platform's rules |

## Part 7 — Jarvis complete

| # | Lesson | What I get |
|---|---|---|
| 24 | **Jarvis routines**: morning briefing, daily summary, proactive reminders, "call me" = loud Telegram voice note | An assistant that works for me without being asked |
| 25 | **Security review**: prompt injection, key scopes, approval gates, audit logs, what the laptop may and may not do | Confidence that Jarvis can't be tricked into harm |

## Phase 2 — Kubernetes track (optional, after Part 7)

K3s, manifests and Helm, Traefik / Gateway API, cert-manager, probes. See [decisions.md](decisions.md).

---

## Honest limits to know up front

| Area | Reality |
|---|---|
| **Server RAM (12 GB)** | We host only what must be ours. n8n needs some RAM; if the server gets tight, we shrink the local model. Cloud models do the heavy thinking. |
| **Free text AI** | Plenty of good options; each has daily caps. The gateway (Lesson 07) rotates between them. |
| **Free image generation** | Some free API tiers exist but are small and change often. |
| **Free video generation** | The hardest one. Truly free, reliable video APIs are rare; most are trials or paid. Lesson 22 shows what works and what doesn't. |
| **Social media APIs** | Each platform has its own rules, approvals and limits; some have restricted or paid APIs. We post only through official APIs, with my approval, and never spam. |
| **"Does everything"** | Jarvis grows one ability at a time. Each lesson adds one skill that works on its own. |
| **The laptop** | PC jobs only run while the laptop is on and logged in. The server answers either way |
| **"Call me"** | Bots can't place phone calls. Free: a loud Telegram voice note. Real calls need a paid service |
| **Free cloud tools** | Calendar, tasks and email live with providers like Google or Microsoft. Convenient and free, but that data is stored by them. Truly private things go to `private` (the local model) |
