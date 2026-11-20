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
      └── backups ....... nightly .zip in /data/backups (14 kept) + a copy on the laptop now and then
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
| zip + systemd timer | Nightly backups on the server | Free |
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

**Part 2 — Jarvis's brain and front door**

| # | Lesson | Status |
|---|---|---|
| 05 | [The AI switchboard: free AI keys, added in a web page (Bifrost)](lessons/05-ai-switchboard.md) | ✅ Tested |
| 06 | [n8n: the engine behind every skill, online and safe](lessons/06-n8n.md) | ✅ Tested |
| 07 | [Jarvis on Telegram: text and voice in and out, with free backups](lessons/07-telegram-jarvis-voice.md) | ✅ Tested (Gemini speaking backup: Written) |
| 08 | [Backups: nightly .zip files on the server](lessons/08-backups-monitoring.md) | ⚠️ Written, not installed yet: **do next** |
| 09 | [Jarvis Live: talk in real time, like a call](lessons/09-jarvis-live-plan.md) | ⬜ Planned |

**Part 3 — Jarvis's hands (my Windows laptop)**

| # | Lesson | Status |
|---|---|---|
| 10 | [Prepare the Windows laptop](lessons/10-prepare-windows-laptop.md) | ✅ Tested (on hold) |
| 11 | [OpenJarvis on the laptop](lessons/11-openjarvis-laptop.md) | ⚠️ Needs update for Bifrost |
| 12 | PC jobs from my phone, with Yes / No first | ⬜ |
| 13 | Talk to Jarvis at the desk | ⬜ |
| 14 | Hard jobs: Gemini CLI / Claude Code | ⬜ |

**Part 4 — Jarvis does things**

| # | Lesson | Status |
|---|---|---|
| 15 | Agents and tools, with approval before actions | ⬜ |
| 16 | My free cloud tools: calendar, reminders, email, web search | ⬜ |
| 17 | Memory and knowledge (RAG) | ⬜ |
| 18 | Routines: SAR→PKR rate alert, new SAR request alert, morning summary | ⬜ Next candidates |

**Part 5 — Jarvis creates**

| # | Lesson | Status |
|---|---|---|
| 19 | Free image generation | ⬜ |
| 20 | Video: what's honestly possible for free | ⬜ |
| 21 | Social media posting with approval | ⬜ |
| 22 | Security review | ⬜ |

**Later (optional):** Jarvis phone app · Kubernetes (K3s) track

Status: **Tested** = run for real and working · **Written** = ready to run · **Planned** = design decided

Progress log: [PROGRESS.md](PROGRESS.md) · Replaced lessons and scripts were removed to keep the repo clean; they remain in the git history.

## Ground rules for this repo

- **No secrets ever**: no passwords, SSH private keys, API tokens or real IP addresses are committed.
- **Public only behind locks**: anything published gets HTTPS, its own login, fail2ban, and nothing else from the server is exposed.
- Every lesson explains **why** before **how**.
- Every command is recorded with what it does.
- Every lesson is tested for real before it's marked ✅ Tested.
- The terminal is only for installing or updating apps on the server. **Inside n8n, everything happens in its web UI.**
