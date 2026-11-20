# Course roadmap: my own Jarvis at $0

**The goal:** one assistant, **Jarvis**, that I control by **text and voice** from my **phone** and my **Windows PC**, that **does tasks** for me (reminders, calendar, search, writing, and work on my PC) **only when I ask**, and asks before anything irreversible. **$0**: open source, Oracle Always Free, free AI tiers. Subscriptions I already pay for (Gemini Pro, Claude Pro) are used only for hard jobs.

Design: [decisions.md](decisions.md). The server is Jarvis's always-on **brain and front door**; the laptop is its **hands**.

Rules for the whole course:

- **$0, no credit card.** Any provider that starts asking for one is dropped.
- **Public only behind locks.** Since 2026-11-16 n8n and Bifrost are published through Apache (HTTPS, own login, fail2ban); AI endpoints and app ports stay private. Tailscale returns for the laptop part.
- **Jarvis asks before acting.** Sending, posting, deleting, anything irreversible needs my "Yes". No payments, ever.
- **Privacy rule:** personal data only goes to AI providers that don't train on it, or stays on my machines.
- **Secrets never touch GitHub.** Keys live in `.env` files or app settings.
- **Free tiers change.** Every lesson checks the live state and falls back automatically.
- **Every lesson is tested for real** before the next one is written.

---

## Part 1 — Foundation (the server)

| # | Lesson | What I get |
|---|---|---|
| 00 | **The plan**: what Jarvis is, and the ideas it's built on | The whole picture before touching anything |
| 01 | **Create the Oracle VM** (one Cloud Shell command) | An Always Free Arm server |
| 02 | **Secure the server** | Key-only SSH, automatic updates, fail2ban, swap |
| 03 | **Docker** | Every app installed and removed cleanly |
| 04 | **Tailscale** (paused) | A private network for the laptop part |

## Part 2 — Jarvis's brain and front door

| # | Lesson | What I get |
|---|---|---|
| 05 | **The AI switchboard (Bifrost)**: free AI keys added in a web page; levels `quick` / `smart` / `code` | Many free AIs through one private address, with fallback |
| 06 | **n8n online and safe**: Apache, HTTPS, login + 2FA, fail2ban, next to the SAR site | The engine every Jarvis skill runs on, reachable anywhere |
| 07 | **Jarvis on Telegram**: instant trigger, ElevenLabs ears and voice, free Gemini backups | Text or voice → Jarvis answers in text, and in voice when spoken to |
| 08 | **Backups**: nightly .zip in `/data/backups` on the server, a copy on the laptop now and then | Undo any mistake; survive losing the VM |
| 09 | **Jarvis Live dashboard**: holographic HUD, my animated avatar, Gemini Live orchestrator, agents as n8n workflows, live event loop | Talk to Jarvis and watch its agents work |

## Part 3 — Jarvis's hands (my Windows laptop)

| # | Lesson | What I get |
|---|---|---|
| 10 | **Prepare the Windows laptop** | A laptop ready for OpenJarvis |
| 11 | **OpenJarvis on the laptop**, thinking through the server's switchboard | Jarvis on the PC, no AI keys on the laptop |
| 12 | **PC jobs from my phone**, with **Yes / No** on Telegram first | "Open my QA report" from Telegram |
| 13 | **Talk to Jarvis at the desk** | Voice control on the PC itself |
| 14 | **Hard jobs**: Gemini CLI / Claude Code (my subscriptions), only when asked | Coding and big automations without API bills |
| later | **WhatsApp and Messenger through the laptop**, drafts I approve | Replies without risky unofficial bridges |

## Part 4 — Jarvis does things

| # | Lesson | What I get |
|---|---|---|
| 15 | **Agents and tools**, approval before any action | Jarvis picks the right tool and asks before acting |
| 16 | **My free cloud tools**: calendar, reminders, email, web search | "Remind me tomorrow at 9" |
| 17 | **Memory and knowledge (RAG)**: vector database + embeddings, exposed as a `memory` agent | Jarvis remembers my preferences, past talks and documents |
| 18 | **Routines**: SAR→PKR rate alert, new SAR request alert, morning summary | Jarvis works for me without being asked |

## Part 5 — Jarvis creates, and a final check

| # | Lesson | What I get |
|---|---|---|
| 19 | **Free image generation** | "Make an image of…" from Telegram |
| 20 | **Video**: what's honestly possible for free | Real limits explained |
| 21 | **Social media posting**: draft → I approve → it posts | Hands-free posting within each platform's rules |
| 22 | **Security review** | Confidence Jarvis can't be tricked into harm |

## Later (optional)

| Track | What |
|---|---|
| **Jarvis phone app** | Our own Android app as a front door, if Telegram isn't enough |
| **Kubernetes** | Move the server apps from Docker Compose to K3s: manifests, Helm, Traefik / Gateway API, cert-manager, probes |

---

## Honest limits to know up front

| Area | Reality |
|---|---|
| **Server (2 CPU / 12 GB)** | Coordinates; the thinking happens on free cloud models |
| **The laptop** | PC jobs only run while it's on and logged in. The server keeps answering either way |
| **"Call me"** | Bots can't place phone calls. Free: a loud Telegram voice note. Real calls need paid services |
| **Free text AI** | Plenty of options, each with daily caps; the gateway rotates between them |
| **Free voice** | ElevenLabs' free plan is about 10 minutes of speech a month; Gemini is the free backup |
| **Free images / video** | Small, changing free tiers; video is the hardest. Lesson 20 is honest about it |
| **Social media APIs** | Each platform has rules, approvals and limits; some are paid. Official APIs only, with my approval |
| **Cloud tools** | Calendar, email and tasks are stored by their providers (Google, Microsoft). Truly private things stay off free AI tiers |
| **"Does everything"** | Jarvis grows one ability per lesson; each works on its own |
