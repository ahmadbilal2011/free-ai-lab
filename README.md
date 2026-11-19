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
 📱 Phone ── Telegram (text + voice notes) ──► https://n8n-<ip>.sslip.io/webhook/…  (instant)
 🌐 Browser ─► n8n editor and Bifrost page, each on its own HTTPS name with its own login
                                             ▼
 ☁️  Oracle VM (Ubuntu, Arm, 2 OCPU / 12 GB — Always Free, on 24/7) — BRAIN + FRONT DOOR
      ├── Apache ........ the only public door (80/443): Let's Encrypt HTTPS, fail2ban on logins
      │                   also serves my separate SAR→PKR calculator site, untouched
      ├── Docker ........ every app in its own container (autoheal restarts frozen ones)
      ├── n8n ........... Jarvis's skills and routines (owner login + 2FA)
      ├── Bifrost ....... AI switchboard: free providers and models added in a web page,
      │                   automatic fallback; n8n reaches it privately at http://bifrost:8080/v1
      └── restic ........ encrypted nightly backups → Oracle Object Storage (+ healthchecks.io)
      Voice: ElevenLabs (ears + voice) with free Gemini backups, all inside n8n
                                             │
                     Tailscale (paused for now; returns for the laptop part)
                                             ▼
 💻 Windows laptop (when it's on) — HANDS
      ├── OpenJarvis .... acts on the PC (apps, files, scripts), asks before risky steps
      ├── Ollama ........ offline fallback on the laptop
      └── Gemini CLI / Claude Code ... hard jobs, with subscriptions I already have
```

| Component | What it is | Cost |
|---|---|---|
| Oracle Cloud Always Free | The server | $0 within limits |
| Ubuntu, Docker, Apache | Operating system, containers, web front door | Free, open source |
| Let's Encrypt + sslip.io | HTTPS certificates and free names that point at the server | Free |
| Bifrost | AI switchboard with a web page and fallback | Free, open source (Apache 2.0) |
| Groq / Gemini / OpenRouter / Mistral / Cohere / NVIDIA / Cloudflare / SambaNova | Cloud AI models | Free tiers, no credit card |
| n8n | Automation engine (self-hosted) | Free to self-host (fair-code licence) |
| Telegram Bot API | Jarvis's front door on the phone | Free |
| ElevenLabs (+ Gemini as free backup) | Ears and voice | Free plan / free tier |
| restic + Oracle Object Storage + healthchecks.io | Backups and alerts | Free |
| OpenJarvis | Jarvis's hands on the Windows PC | Free, open source (Apache 2.0) |
| Tailscale | Private network for my devices (paused) | Free personal plan |

## Lessons

**Part 1 — Foundation (the server)**

| # | Lesson | Status |
|---|---|---|
| 00 | [The plan: what Jarvis is, and the ideas it's built on](lessons/00-concepts.md) | ✅ Written |
| 01 | [Create the Oracle VM safely](lessons/01-create-vm.md) | ✅ Tested |
| 02 | [Secure SSH access, updates and firewall](lessons/02-secure-server.md) | ✅ Tested |
| 03 | [Install and understand Docker](lessons/03-docker.md) | ✅ Tested |
| 04 | [Tailscale: one private network for server, laptop and phone](lessons/04-tailscale.md) | ⏸ Paused (back for the laptop part) |

**Part 2 — Jarvis's brain (free AI on the server)**

| # | Lesson | Status |
|---|---|---|
| 05 | [Free AI API keys: Jarvis's brain at $0](lessons/05-free-ai-keys.md) | ✅ Tested |
| 06 | [The AI gateway (LiteLLM)](lessons/06-ai-gateway.md) | 🔁 Replaced by 06b |
| 06b | [The AI switchboard: add free AI models in a web page (Bifrost)](lessons/06b-ai-switchboard.md) | ✅ Tested |
| 07 | [Backups and monitoring](lessons/07-backups-monitoring.md) | ⚠️ Not installed yet |

**Part 3 — Jarvis's front door (my phone)**

| # | Lesson | Status |
|---|---|---|
| 08 | [n8n: the engine behind every Jarvis skill](lessons/08-n8n.md) | ✅ Tested |
| 08b | [Put n8n on the internet safely, next to an existing website](lessons/08b-public-n8n.md) | ✅ Tested |
| 09 | [Telegram by polling (private setups)](lessons/09-telegram-bot.md) | 🔁 Replaced by 10b |
| 10 | [Voice with a separate voice service](lessons/10-voice.md) | 🔁 Replaced by 10b |
| 10b | [Jarvis on Telegram: text and voice in, text and voice out, free backups](lessons/10b-telegram-jarvis-voice.md) | ✅ Tested (Gemini voice backup: Written) |
| 10c | [Jarvis Live: talk in real time, like a call](lessons/10c-jarvis-live-plan.md) | ⬜ Planned |

**Part 4 — Jarvis's hands (my Windows laptop)**

| # | Lesson | Status |
|---|---|---|
| 11 | [Prepare the Windows laptop](lessons/11-prepare-windows-laptop.md) | ✅ Tested |
| 12 | [OpenJarvis on the laptop, thinking with the server's brain](lessons/12-openjarvis-laptop.md) | ✅ Written |
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
| 22 | Routines: morning briefing, SAR→PKR rate alert, new SAR request alert, reminders | ⬜ Next candidates |
| 23 | Security review | ⬜ |

**Later (optional):** Jarvis phone app · Kubernetes (K3s) track

Status: **Tested** = run for real and working · **Written** = ready to run · **Planned** = design decided · **Replaced** = kept for reference

## Restarting on a server from the first version?

The first version of this course installed different apps (Open WebUI and others). To start this version on the same server, wipe the apps but keep the server, SSH and Tailscale:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/wipe-apps.sh -o wipe-apps.sh && sudo bash wipe-apps.sh
```

It shows everything it will remove and asks you to type `WIPE` first. Then continue from Lesson 04 (re-run it to check Tailscale) and Lesson 05.

Progress log: [PROGRESS.md](PROGRESS.md)

## Ground rules for this repo

- **No secrets ever**: no passwords, SSH private keys, API tokens or real IP addresses are committed.
- **Public only behind locks**: anything published gets HTTPS, its own login, fail2ban, and nothing else from the server is exposed.
- Every lesson explains **why** before **how**.
- Every command is recorded with what it does.
- Every lesson is tested for real before it's marked ✅ Tested.
- The terminal is only for installing or updating apps on the server. **Inside n8n, everything happens in its web UI.**
