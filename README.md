# free-ai-lab

My personal, **zero-cost** AI lab on Oracle Cloud Always Free, built step by step as a beginner.

## Goal

Build my own **Jarvis**: one AI assistant I control by **text and voice**, from my phone and PC, that **does things** for me (on my Windows PC too), at **$0 cost**.

- Fast free cloud AI models, with a private local model as backup
- Text and voice control through Telegram
- Connects to the free cloud tools I already use (calendar, reminders, email, search) through n8n
- Agents that act for me **with my approval**: plan, remind, write, code, create images and video, post to social media
- My Windows laptop as Jarvis's **hands** (OpenJarvis): opens apps, handles files, runs scripts, only when I ask
- The server hosts only what must be ours; everything is open source or free tier, documented here so others can repeat it

Full plan: **[docs/roadmap.md](docs/roadmap.md)**

## The stack

```
My phone / PC
      │   Tailscale (free private network) — no public ports at all; n8n only reaches OUT
      ▼
Oracle Cloud VM  (Ubuntu, Arm Ampere A1, 2 OCPU / 12 GB RAM — Always Free)
  ├── Docker ........ runs every app in its own isolated container
  ├── autoheal ...... restarts any app that freezes
  ├── restic ........ encrypted nightly backups → Oracle Object Storage (+ healthchecks.io alerts)
  ├── LiteLLM ....... AI gateway: Groq → NVIDIA → OpenRouter → local, automatic fallback
  ├── Ollama ........ engine that runs open-source AI models on the CPU (private fallback)
  ├── Open WebUI .... ChatGPT-style web interface (installable on phone)
  ├── voice ......... Jarvis's voice: ElevenLabs first, local Piper when credits run out; no host port
  └── n8n ........... automation engine: Jarvis's skills and connections (editor private on https://…ts.net:9443)

Jarvis's front door: Telegram (text + voice) ◄── n8n asks for new messages ──► gateway ──► free cloud tools
                                                          │
                                                          │ Tailscale only, with a key (Part 4)
                                                          ▼
Windows laptop — Jarvis's hands (on when I'm at my PC)
  ├── OpenJarvis ...... acts on the PC (apps, files, scripts), asks before risky actions; thinks via the gateway
  ├── Ollama .......... offline fallback models on the laptop
  └── Gemini CLI / Claude Code ... hard jobs, using subscriptions I already have
```

| Component | What it is | Cost |
|---|---|---|
| Oracle Cloud Always Free | The server (virtual machine) | $0 within limits |
| Ubuntu Server | Operating system | Free, open source |
| Docker | Container runtime | Free, open source |
| Ollama | Local AI model runner | Free, open source |
| Open WebUI | AI chat interface | Free, open source |
| LiteLLM | AI gateway with fallback | Free, open source |
| Groq / NVIDIA Build / OpenRouter | Cloud AI models | Free tiers, no credit card |
| Tailscale | Private remote access | Free personal plan |
| restic + Oracle Object Storage | Encrypted backups | Free, open source + Always Free 20 GB |
| healthchecks.io | Email alerts if the server or a backup stops | Free plan |
| n8n | Automation engine (self-hosted) | Free to self-host (fair-code licence) |
| Telegram Bot API | Text and voice front door for Jarvis | Free |
| ElevenLabs | Best ears (Scribe) and voice (Eleven v3, speaks Urdu) | Free plan: 10k credits/month, personal use |
| Groq Whisper | Backup ears | Free tier |
| Piper | Backup voice, runs locally | Free, open source |
| OpenJarvis | Jarvis's hands on the Windows laptop | Free, open source (Apache 2.0) |
| Ollama (laptop) | Offline models on the laptop | Free, open source |

## Lessons

**Part 1 — Foundation**

| # | Lesson | Status |
|---|---|---|
| 00 | [Core concepts before we start](lessons/00-concepts.md) | ✅ Done |
| 01 | [Create the Oracle VM safely](lessons/01-create-vm.md) | ✅ Done |
| 02 | [Secure SSH access, updates and firewall](lessons/02-secure-server.md) | ✅ Done |
| 03 | [Install and understand Docker](lessons/03-docker.md) | ✅ Done |
| 04 | [Run my own AI: Ollama + Open WebUI](lessons/04-ai.md) | ✅ Done |
| 05 | [Access from anywhere with Tailscale (PC + mobile)](lessons/05-tailscale.md) | ✅ Done |

**Part 2 — Smart AI for free**

| # | Lesson | Status |
|---|---|---|
| 06 | [Free cloud AI via API keys (Groq, NVIDIA, OpenRouter, …)](lessons/06-free-cloud-ai.md) | ✅ Done |
| 07 | [LiteLLM gateway: one endpoint, automatic fallback](lessons/07-litellm-gateway.md) | ✅ Done |
| 08 | [Backups and monitoring](lessons/08-backups-monitoring.md) | ✅ Done |

**Part 3 — Jarvis's nervous system and front door**

| # | Lesson | Status |
|---|---|---|
| 09 | [n8n basics: workflows, triggers, credentials, connected to my AI gateway](lessons/09-n8n-basics.md) | ✅ Done |
| 10 | [Telegram bot: text Jarvis from anywhere](lessons/10-telegram-bot.md) | ✅ Done |
| 11 | [Voice in, voice out: free speech-to-text and text-to-speech](lessons/11-voice.md) | ⏳ Almost done |

**Part 4 — Jarvis on my PC**

| # | Lesson | Status |
|---|---|---|
| 12 | [Prepare the Windows laptop: clean installs, Python 3.13, git, Ollama](lessons/12-prepare-windows-laptop.md) | ⏳ In progress |
| 13 | OpenJarvis on the laptop, thinking through the server's gateway | ⬜ |
| 14 | Server → laptop over Tailscale: PC jobs from Telegram, Yes / No before risky actions | ⬜ |
| 15 | Talk to Jarvis at the desk: microphone in, spoken replies out | ⬜ |
| 16 | Hard jobs: Gemini CLI / Claude Code with my subscriptions | ⬜ |
| 17 | Phone apps via ADB (Android, optional) | ⬜ |

**Part 5 — Jarvis does things**

| # | Lesson | Status |
|---|---|---|
| 18 | Agents and tools (n8n AI Agent, MCP), with approval before actions | ⬜ |
| 19 | Connect my free cloud tools: calendar, reminders, email, web search | ⬜ |
| 20 | Memory and knowledge (RAG) | ⬜ |

**Part 6 — Jarvis creates**

| # | Lesson | Status |
|---|---|---|
| 21 | Free image generation | ⬜ |
| 22 | Video generation: what's honestly possible for free | ⬜ |
| 23 | Social media posting with approval | ⬜ |

**Part 7 — Jarvis complete**

| # | Lesson | Status |
|---|---|---|
| 24 | Jarvis routines: morning briefing, reminders, "call me" alerts on Telegram | ⬜ |
| 25 | Security review: prompt injection, key scopes, approval gates, laptop limits | ⬜ |

### Phase 2 — Kubernetes track (optional, after Part 7)

Move the same server apps from Docker Compose to Kubernetes, on the same free VM.

| # | Lesson | Status |
|---|---|---|
| K1 | K3s: lightweight Kubernetes on one node | ⬜ |
| K2 | Translate the Compose stacks into Kubernetes manifests and Helm | ⬜ |
| K3 | Traffic routing with Traefik / Gateway API (ingress-nginx is retired) | ⬜ |
| K4 | cert-manager and HTTPS certificates | ⬜ |
| K5 | Probes, resource limits and rolling updates vs. Docker autoheal | ⬜ |

Why this order: [docs/decisions.md](docs/decisions.md)

Progress log: [PROGRESS.md](PROGRESS.md)

## Ground rules for this repo

- **No secrets ever** — no passwords, SSH private keys, API tokens or real IP addresses are committed.
- Every lesson explains **why** before **how**.
- Every command I run is recorded with what it does.
