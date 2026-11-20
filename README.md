# free-ai-lab

Learn **n8n** step by step, at **$0**, on your own free server. A beginner's lab notebook.

## Goal

1. **Foundation:** a free Oracle server, made safe, with Docker, a switchboard for free AI models (Bifrost), n8n online with HTTPS, and nightly backups. *(Done.)*
2. **The n8n track:** one idea per lesson, with a small workflow you build and test yourself, from your first node to AI agents and real projects.
3. **New goals** come after the n8n track.

Plan: **[docs/roadmap.md](docs/roadmap.md)** · Why it's built this way: **[docs/decisions.md](docs/decisions.md)**

## What runs on the server

```
 🌐 Browser / 📱 Telegram ─► HTTPS (each app has its own name and login)
                                             ▼
 ☁️  Oracle VM (Ubuntu, Arm, 2 OCPU / 12 GB — Always Free, on 24/7)
      ├── Apache ........ the only public door (80/443): Let's Encrypt HTTPS, fail2ban on logins
      │                   also serves my separate SAR→PKR calculator site, untouched
      ├── Docker ........ every app in its own container (autoheal restarts frozen ones)
      ├── n8n ........... where I build workflows (owner login + 2FA)
      ├── Bifrost ....... AI switchboard: free AI models added in a web page, automatic fallback;
      │                   n8n reaches it privately at http://bifrost:8080/v1
      └── backups ....... nightly .zip in /data/backups (14 kept)
```

| Component | What it is | Cost |
|---|---|---|
| Oracle Cloud Always Free | The server | $0 within limits |
| Ubuntu, Docker, Apache | Operating system, containers, web front door | Free, open source |
| Let's Encrypt + sslip.io | HTTPS certificates and free names that point at the server | Free |
| Bifrost | AI switchboard with a web page and fallback | Free, open source (Apache 2.0) |
| Groq / Gemini / OpenRouter / Mistral / NVIDIA … | Cloud AI models | Free tiers, no credit card |
| n8n | Automation engine (self-hosted) | Free to self-host (fair-code licence) |
| Telegram Bot API | Chat with my workflows from the phone | Free |
| zip + systemd timer | Nightly backups on the server | Free |

## Lessons

**Part 1 — Foundation (the server)**

| # | Lesson | Status |
|---|---|---|
| 00 | [The plan: learn n8n on your own free server](lessons/00-concepts.md) | ✅ Written |
| 01 | [Create the Oracle VM safely](lessons/01-create-vm.md) | ✅ Tested |
| 02 | [Secure SSH access, updates and firewall](lessons/02-secure-server.md) | ✅ Tested |
| 03 | [Install and understand Docker](lessons/03-docker.md) | ✅ Tested |
| 04 | [Tailscale: a private network for your devices](lessons/04-tailscale.md) | ⏸ Optional, not used now |
| 05 | [The AI switchboard: free AI keys, added in a web page (Bifrost)](lessons/05-ai-switchboard.md) | ✅ Tested |
| 06 | [n8n online and safe](lessons/06-n8n.md) | ✅ Tested |
| 07 | [A Telegram AI bot: text and voice in and out](lessons/07-telegram-voice-bot.md) | ✅ Tested (built before the n8n track; rebuilt cleanly in n8n 13) |
| 08 | [Backups: nightly .zip files on the server](lessons/08-backups-monitoring.md) | ⚠️ Written, install pending |

**Part 2 — The n8n track (step by step)**

| # | Lesson | What you can do after it | Status |
|---|---|---|---|
| n8n 01 | [Your first workflow](lessons/n8n/01-first-workflow.md): trigger, nodes, run, items, the three data views, executions | Build and run a 3-node workflow and read its data | ✅ Written |
| n8n 02 | Data and expressions: `{{ }}`, `$json`, drag and drop, dates with `$now` | Calculate and reshape data (e.g. SAR → PKR) | ⬜ |
| n8n 03 | Triggers: Schedule, Webhook (test vs production URL), Form; Publish | Workflows that start by themselves | ⬜ |
| n8n 04 | Logic: If, Switch, Filter, Merge | Different paths for different data | ⬜ |
| n8n 05 | Many items: lists, Split Out, Aggregate, Loop Over Items | Handle 1 or 1,000 records the same way | ⬜ |
| n8n 06 | Talk to APIs: HTTP Request, credentials (free exchange-rate API) | Pull live data from any web service | ⬜ |
| n8n 07 | The Code node: small JavaScript when nodes aren't enough | Custom logic in a few lines | ⬜ |
| n8n 08 | Errors: error outputs, retries, an Error workflow that tells you on Telegram | Workflows that fail loudly and safely | ⬜ |
| n8n 09 | Storing data: n8n Data tables | Keep lists and history between runs | ⬜ |
| n8n 10 | AI nodes: Basic LLM Chain, structured output, Bifrost models | Summarise, classify and extract with free AI | ⬜ |
| n8n 11 | AI Agent: tools and memory | An assistant that uses your workflows as tools | ⬜ |
| n8n 12 | Sub-workflows: build once, reuse everywhere | Tidy, reusable building blocks | ⬜ |
| n8n 13 | Projects: SAR→PKR rate alert; the Telegram voice bot rebuilt cleanly | Real automations from scratch | ⬜ |
| n8n 14 | Good habits: names, notes, versions, export to GitHub, backups | Workflows you can trust and restore | ⬜ |

Status: **Tested** = run for real and working · **Written** = ready to run · ⬜ = planned

Progress log: [PROGRESS.md](PROGRESS.md) · Removed lessons (Jarvis Live, OpenJarvis) remain only in the git history.

## Ground rules for this repo

- **No secrets ever**: no passwords, SSH private keys, API tokens or real IP addresses are committed.
- **Public only behind locks**: anything published gets HTTPS, its own login, fail2ban, and nothing else from the server is exposed.
- Every lesson explains **why** before **how**, and every step is checked before it's marked ✅ Tested.
- The terminal is only for installing or updating apps on the server. **Inside n8n, everything happens in its web UI.**
