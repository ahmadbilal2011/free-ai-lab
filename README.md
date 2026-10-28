# free-ai-lab

My personal, **zero-cost** AI lab on Oracle Cloud Always Free, built step by step as a beginner.

## Goal

Build **one free, private system** — reachable from my phone and PC — that grows step by step into my own AI assistant ("Jarvis"):

- Chat with fast free cloud AI models, with a private local model as backup
- Manage my daily tasks and automate my day (n8n)
- Agents that can act for me, with my approval
- Code, images, video and social media posting, all from the same system
- Everything open source or free tier, documented here so others can repeat it

Full plan: **[docs/roadmap.md](docs/roadmap.md)**

## The stack

```
My phone / PC
      │   Tailscale (free private network — no public ports opened)
      ▼
Oracle Cloud VM  (Ubuntu, Arm Ampere A1, 2 OCPU / 12 GB RAM — Always Free)
  ├── Docker ........ runs every app in its own isolated container
  ├── autoheal ...... restarts any app that freezes
  ├── Ollama ........ engine that runs open-source AI models on the CPU
  ├── Open WebUI .... ChatGPT-style web interface (installable on phone)
  └── Vikunja ....... to-do lists and daily task management
```

| Component | What it is | Cost |
|---|---|---|
| Oracle Cloud Always Free | The server (virtual machine) | $0 within limits |
| Ubuntu Server | Operating system | Free, open source |
| Docker | Container runtime | Free, open source |
| Ollama | Local AI model runner | Free, open source |
| Open WebUI | AI chat interface | Free, open source |
| Tailscale | Private remote access | Free personal plan |
| Vikunja | Task manager | Free, open source |

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
| 06 | [Free cloud AI via API keys (Groq, NVIDIA, OpenRouter, …)](lessons/06-free-cloud-ai.md) | ⏳ Next |
| 07 | LiteLLM gateway: one endpoint, automatic fallback | ⬜ |
| 08 | Backups and monitoring | ⬜ |

**Part 3 — Daily life and automation**

| # | Lesson | Status |
|---|---|---|
| 09 | Vikunja task manager | ⬜ |
| 10 | n8n basics: workflows, triggers, credentials | ⬜ |
| 11 | Telegram bot + n8n: talk to my AI, daily briefing | ⬜ |

**Part 4 — Agents**

| # | Lesson | Status |
|---|---|---|
| 12 | AI agents and tools (n8n AI Agent, MCP) | ⬜ |
| 13 | Agent harnesses and coding agents with free APIs | ⬜ |
| 14 | Memory and knowledge (RAG) | ⬜ |

**Part 5 — Creative and social**

| # | Lesson | Status |
|---|---|---|
| 15 | Free image generation | ⬜ |
| 16 | Video generation: what's honestly possible for free | ⬜ |
| 17 | Social media posting with approval | ⬜ |

**Part 6 — Jarvis**

| # | Lesson | Status |
|---|---|---|
| 18 | Voice: speech-to-text and text-to-speech | ⬜ |
| 19 | Jarvis: tie everything together | ⬜ |
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
