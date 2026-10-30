# free-ai-lab

My personal, **zero-cost** AI lab on Oracle Cloud Always Free, built step by step as a beginner.

## Goal

Build my own **Jarvis**: one AI assistant I control by **text and voice**, from my phone and PC, that **does things** for me, at **$0 cost**.

- Fast free cloud AI models, with a private local model as backup
- Text and voice control through Telegram
- Connects to the free cloud tools I already use (calendar, reminders, email, search) through n8n
- Agents that act for me **with my approval**: plan, remind, write, code, create images and video, post to social media
- The server hosts only what must be ours; everything is open source or free tier, documented here so others can repeat it

Full plan: **[docs/roadmap.md](docs/roadmap.md)**

## The stack

```
My phone / PC
      │   Tailscale (free private network) — the only public door is n8n's webhook path for Telegram
      ▼
Oracle Cloud VM  (Ubuntu, Arm Ampere A1, 2 OCPU / 12 GB RAM — Always Free)
  ├── Docker ........ runs every app in its own isolated container
  ├── autoheal ...... restarts any app that freezes
  ├── restic ........ encrypted nightly backups → Oracle Object Storage (+ healthchecks.io alerts)
  ├── LiteLLM ....... AI gateway: Groq → NVIDIA → OpenRouter → local, automatic fallback
  ├── Ollama ........ engine that runs open-source AI models on the CPU (private fallback)
  ├── Open WebUI .... ChatGPT-style web interface (installable on phone)
  └── n8n ........... automation engine: Jarvis's skills and connections (https://…ts.net:8443)

Jarvis's front door: Telegram (text + voice) ──► n8n ──► gateway ──► free cloud tools
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
| 10 | [Telegram bot: text Jarvis from anywhere](lessons/10-telegram-bot.md) | ⏳ Next |
| 11 | Voice in, voice out: free speech-to-text and text-to-speech | ⬜ |

**Part 4 — Jarvis does things**

| # | Lesson | Status |
|---|---|---|
| 12 | Agents and tools (n8n AI Agent, MCP), with approval before actions | ⬜ |
| 13 | Connect my free cloud tools: calendar, reminders, email, web search | ⬜ |
| 14 | Memory and knowledge (RAG) | ⬜ |
| 15 | Coding agent harness with free models | ⬜ |

**Part 5 — Jarvis creates**

| # | Lesson | Status |
|---|---|---|
| 16 | Free image generation | ⬜ |
| 17 | Video generation: what's honestly possible for free | ⬜ |
| 18 | Social media posting with approval | ⬜ |

**Part 6 — Jarvis complete**

| # | Lesson | Status |
|---|---|---|
| 19 | Jarvis routines: morning briefing, reminders, alerts on Telegram | ⬜ |
| 20 | Security review: prompt injection, key scopes, approval gates | ⬜ |

### Phase 2 — Kubernetes track (optional, after Part 6)

Move the same apps from Docker Compose to Kubernetes, on the same free VM.

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
