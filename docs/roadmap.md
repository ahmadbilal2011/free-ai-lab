# Course roadmap: from a free server to my own "Jarvis"

The goal: **one free, private system** I reach from my phone and PC, that can chat, code, create images and video, manage my tasks, automate my day, post to social media (with my approval), and act as a personal assistant ("Jarvis").

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
| 06 | **Free cloud AI via API keys** (Groq, Cerebras, + optional GitHub Models, OpenRouter, Gemini) | Fast, smart chat in Open WebUI today |
| 07 | **LiteLLM gateway** | One endpoint for every provider, automatic fallback when a free limit is hit, usage logs |
| 08 | **Backups and monitoring** | Chats, settings and keys are safe before Jarvis gets my data |

## Part 3 — Daily life and automation

| # | Lesson | What I get |
|---|---|---|
| 09 | **Vikunja** task manager | My to-do lists, on phone and PC |
| 10 | **n8n basics**: workflows, triggers, credentials | The "nervous system" that connects everything |
| 11 | **Telegram bot + n8n** | Talk to my AI from Telegram; daily morning briefing; reminders |

## Part 4 — Agents (the Jarvis brain)

| # | Lesson | What I get |
|---|---|---|
| 12 | **AI agents and tools**: n8n AI Agent, function calling, MCP | The AI can *do* things: add tasks, search the web, read my calendar |
| 13 | **Agent harnesses and coding agents** (e.g. OpenCode / Aider) with free APIs | An AI that writes and fixes code on my server, safely sandboxed |
| 14 | **Memory and knowledge (RAG)** | The AI knows my notes and documents, privately |

## Part 5 — Creative and social

| # | Lesson | What I get |
|---|---|---|
| 15 | **Free image generation** (free API tiers; checked when we get there) | Images from a prompt, inside my system |
| 16 | **Video generation**: what's honestly possible for free | Short clips / slideshow-style videos; real limits explained |
| 17 | **Social media posting** (self-hosted scheduler + n8n, approval step) | Draft → I approve → it posts. Within each platform's rules |

## Part 6 — Jarvis

| # | Lesson | What I get |
|---|---|---|
| 18 | **Voice**: speech-to-text and text-to-speech | Talk to it, it answers out loud |
| 19 | **Jarvis**: tie everything together | One assistant on Telegram + Open WebUI that chats, plans, creates, automates |
| 20 | **Security review**: prompt injection, key scopes, approval gates, audit logs | Confidence that Jarvis can't be tricked into harm |

## Phase 2 — Kubernetes track (optional, after Part 6)

K3s, manifests and Helm, Traefik / Gateway API, cert-manager, probes. See [decisions.md](decisions.md).

---

## Honest limits to know up front

| Area | Reality |
|---|---|
| **Server RAM (12 GB)** | n8n, a social scheduler and databases all need RAM. When we add them, we may shrink or pause the local model. Cloud models do the heavy thinking. |
| **Free text AI** | Plenty of good options; each has daily caps. The gateway (Lesson 07) rotates between them. |
| **Free image generation** | Some free API tiers exist but are small and change often. |
| **Free video generation** | The hardest one. Truly free, reliable video APIs are rare; most are trials or paid. Lesson 16 shows what works and what doesn't. |
| **Social media APIs** | Each platform has its own rules, approvals and limits; some have restricted or paid APIs. We post only through official APIs, with my approval, and never spam. |
| **"Does everything"** | Jarvis grows one ability at a time. Each lesson adds one skill that works on its own. |
