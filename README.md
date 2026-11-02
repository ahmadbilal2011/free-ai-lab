# free-ai-lab

Build your own **Jarvis** at **$0**, step by step, as a beginner.

## Goal

One AI assistant I control by **text and voice**, from my **phone** and my **Windows PC**, that **does tasks** for me, **only when I ask**:

- Answers by text and voice (Urdu, English, Arabic…)
- Reminders, calendar, web search, writing, through the free cloud tools I already use
- On my PC: opens apps, handles files, runs scripts
- Asks **"Yes / No?"** before anything that can't be undone; never pays for anything
- **$0**: open source, Oracle Always Free, free AI tiers. Subscriptions I already have (Gemini Pro, Claude Pro) only for hard jobs

Full plan: **[docs/roadmap.md](docs/roadmap.md)** · Why it's built this way: **[docs/decisions.md](docs/decisions.md)**

## The design: one brain, two hands

```
 📱 Phone ── Telegram (text + voice notes) ──┐      nothing reaches in: n8n reaches OUT to Telegram
                                             ▼
 ☁️  Oracle VM (Ubuntu, Arm, 2 OCPU / 12 GB — Always Free, on 24/7) — BRAIN + FRONT DOOR
      ├── Docker ........ every app in its own container (autoheal restarts frozen ones)
      ├── LiteLLM ....... AI gateway: free cloud models → private model, automatic fallback
      ├── Ollama ........ small private model on the server (last fallback, stays private)
      ├── n8n ........... Jarvis's skills and routines (editor private on Tailscale)
      ├── voice ......... ears + voice: ElevenLabs, with free backups
      └── restic ........ encrypted nightly backups → Oracle Object Storage (+ healthchecks.io)
                                             │
                     Tailscale (private network: server + laptop + phone), with a key
                                             ▼
 💻 Windows laptop (when it's on) — HANDS
      ├── OpenJarvis .... acts on the PC (apps, files, scripts), asks before risky steps; thinks via the gateway
      ├── Ollama ........ offline fallback on the laptop
      └── Gemini CLI / Claude Code ... hard jobs, with subscriptions I already have
```

| Component | What it is | Cost |
|---|---|---|
| Oracle Cloud Always Free | The server | $0 within limits |
| Ubuntu, Docker | Operating system, containers | Free, open source |
| Tailscale | Private network for all my devices | Free personal plan |
| LiteLLM | AI gateway with fallback | Free, open source |
| Groq / NVIDIA Build / OpenRouter (+ Gemini optional) | Cloud AI models | Free tiers, no credit card |
| Ollama | Runs small AI models locally | Free, open source |
| n8n | Automation engine (self-hosted) | Free to self-host (fair-code licence) |
| Telegram Bot API | Jarvis's front door | Free |
| ElevenLabs (+ Groq Whisper, Piper as backups) | Ears and voice | Free plan / free tier / open source |
| restic + Oracle Object Storage + healthchecks.io | Backups and alerts | Free |
| OpenJarvis | Jarvis's hands on the Windows PC | Free, open source (Apache 2.0) |

## Lessons

**Part 1 — Foundation (the server)**

| # | Lesson | Status |
|---|---|---|
| 00 | [The plan: what Jarvis is, and the ideas it's built on](lessons/00-concepts.md) | ✅ Written |
| 01 | [Create the Oracle VM safely](lessons/01-create-vm.md) | ✅ Tested |
| 02 | [Secure SSH access, updates and firewall](lessons/02-secure-server.md) | ✅ Tested |
| 03 | [Install and understand Docker](lessons/03-docker.md) | ✅ Tested |
| 04 | [Tailscale: one private network for server, laptop and phone](lessons/04-tailscale.md) | ✅ Written |

**Part 2 — Jarvis's brain (free AI on the server)**

| # | Lesson | Status |
|---|---|---|
| 05 | [Free AI API keys: Jarvis's brain at $0](lessons/05-free-ai-keys.md) | ✅ Tested |
| 06 | [The AI gateway: one address, free models, automatic fallback](lessons/06-ai-gateway.md) | ✅ Tested |
| 07 | [Backups and monitoring](lessons/07-backups-monitoring.md) | ✅ Done |

**Part 3 — Jarvis's front door (my phone)**

| # | Lesson | Status |
|---|---|---|
| 08 | [n8n: the engine behind every Jarvis skill](lessons/08-n8n.md) | ✅ Tested |
| 09 | [Telegram: talk to Jarvis from your phone](lessons/09-telegram-bot.md) | ✅ Written |
| 10 | Voice in, voice out | ⏳ Next |

**Part 4 — Jarvis's hands (my Windows laptop)**

| # | Lesson | Status |
|---|---|---|
| 11 | [Prepare the Windows laptop](lessons/11-prepare-windows-laptop.md) | ✅ Written |
| 12 | OpenJarvis on the laptop, thinking through the server's gateway | ⬜ |
| 13 | PC jobs from my phone, with Yes / No first | ⬜ |
| 14 | Talk to Jarvis at the desk | ⬜ |
| 15 | Hard jobs: Gemini CLI / Claude Code | ⬜ |

**Part 5 — Jarvis does things**

| # | Lesson | Status |
|---|---|---|
| 16 | Agents and tools, with approval before actions | ⬜ |
| 17 | My free cloud tools: calendar, reminders, email, web search | ⬜ |
| 18 | Memory and knowledge (RAG) | ⬜ |

**Part 6 — Jarvis creates**

| # | Lesson | Status |
|---|---|---|
| 19 | Free image generation | ⬜ |
| 20 | Video: what's honestly possible for free | ⬜ |
| 21 | Social media posting with approval | ⬜ |

**Part 7 — Jarvis complete**

| # | Lesson | Status |
|---|---|---|
| 22 | Routines: morning briefing, reminders, "call me" alerts | ⬜ |
| 23 | Security review | ⬜ |

**Later (optional):** Jarvis phone app · Kubernetes (K3s) track

Status: **Tested** = run for real and working · **Written** = ready to run · **Next** = being written

## Restarting on a server from the first version?

The first version of this course installed different apps (Open WebUI and others). To start this version on the same server, wipe the apps but keep the server, SSH and Tailscale:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/wipe-apps.sh -o wipe-apps.sh && sudo bash wipe-apps.sh
```

It shows everything it will remove and asks you to type `WIPE` first. Then continue from Lesson 04 (re-run it to check Tailscale) and Lesson 05.

Progress log: [PROGRESS.md](PROGRESS.md)

## Ground rules for this repo

- **No secrets ever**: no passwords, SSH private keys, API tokens or real IP addresses are committed.
- Every lesson explains **why** before **how**.
- Every command is recorded with what it does.
- Every lesson is tested for real before it's marked ✅ Tested.
