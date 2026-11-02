# Course roadmap: my own Jarvis at $0

**The goal:** one assistant, **Jarvis**, that I control by **text and voice** from my **phone** and my **Windows PC**, that **does tasks** for me (reminders, calendar, search, writing, and work on my PC) **only when I ask**, and asks before anything irreversible. **$0**: open source, Oracle Always Free, free AI tiers. Subscriptions I already pay for (Gemini Pro, Claude Pro) are used only for hard jobs.

Design: [decisions.md](decisions.md). The server is Jarvis's always-on **brain and front door**; the laptop is its **hands**.

Rules for the whole course:

- **$0, no credit card.** Any provider that starts asking for one is dropped.
- **Private by default.** Only SSH is public; everything else sits behind Tailscale. Nothing reaches in from the internet.
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
| 04 | **Tailscale**: one private network for server, laptop and phone | Everything reachable from anywhere, nothing public |

## Part 2 — Jarvis's brain (free AI on the server)

| # | Lesson | What I get |
|---|---|---|
| 05 | **Free AI API keys** (Groq, NVIDIA, OpenRouter; Gemini optional), tested and kept in one private file | Access to strong free models |
| 06 | **The AI gateway**: LiteLLM + a small private model (Ollama), models discovered and tested automatically | One address, aliases `smart` / `fast` / `private`, automatic fallback |
| 07 | **Backups and monitoring**: restic → Oracle Object Storage, healthchecks.io | Keys and workflows safe before Jarvis gets my data |

## Part 3 — Jarvis's front door (my phone)

| # | Lesson | What I get |
|---|---|---|
| 08 | **n8n**: the automation engine, private editor, connected to the gateway | The engine every Jarvis skill runs on |
| 09 | **Telegram bot** by polling (no public door) | Text Jarvis from my phone, anywhere |
| 10 | **Voice in, voice out**: ElevenLabs first, free backups automatic | Send a voice note → Jarvis understands and answers with a voice |

## Part 4 — Jarvis's hands (my Windows laptop)

| # | Lesson | What I get |
|---|---|---|
| 11 | **Prepare the Windows laptop**: Python 3.13, git, Ollama, Tailscale, one check script | A laptop ready for OpenJarvis |
| 12 | **OpenJarvis on the laptop**, thinking through the server's gateway | Jarvis on the PC, no AI keys on the laptop |
| 13 | **PC jobs from my phone**: n8n → OpenJarvis over Tailscale with a key, **Yes / No** on Telegram first | "Open my QA report", "zip yesterday's screenshots" from Telegram |
| 14 | **Talk to Jarvis at the desk**: microphone in, spoken replies out | Voice control on the PC itself |
| 15 | **Hard jobs**: hand off to Gemini CLI / Claude Code (my subscriptions), only when asked | Coding and big automations without API bills |
| later | **WhatsApp through the laptop**: Jarvis uses the WhatsApp desktop app for my 2 accounts, drafts → I approve → it sends (postponed, see decisions) | Replies on WhatsApp without risky unofficial bridges |

## Part 5 — Jarvis does things

| # | Lesson | What I get |
|---|---|---|
| 16 | **Agents and tools**: n8n AI Agent, MCP, approval before any action | Jarvis picks the right tool and asks before acting |
| 17 | **My free cloud tools**: calendar, reminders, email, web search | "Remind me tomorrow at 9", "What's on my calendar?" |
| 18 | **Memory and knowledge (RAG)** | Jarvis remembers my preferences and reads my notes |

## Part 6 — Jarvis creates

| # | Lesson | What I get |
|---|---|---|
| 19 | **Free image generation** | "Make an image of…" from Telegram |
| 20 | **Video**: what's honestly possible for free | Short clips / slideshows, real limits explained |
| 21 | **Social media posting**: draft → I approve → it posts (official APIs only) | Hands-free posting within each platform's rules |

## Part 7 — Jarvis complete

| # | Lesson | What I get |
|---|---|---|
| 22 | **Routines**: morning briefing, proactive reminders, "call me" = loud Telegram voice note | Jarvis works for me without being asked |
| 23 | **Security review**: prompt injection, key scopes, approval gates, what the laptop may and may not do | Confidence Jarvis can't be tricked into harm |

## Later (optional)

| Track | What |
|---|---|
| **Jarvis phone app** | Our own Android app as a front door, if Telegram isn't enough |
| **Kubernetes** | Move the server apps from Docker Compose to K3s: manifests, Helm, Traefik / Gateway API, cert-manager, probes |

---

## Honest limits to know up front

| Area | Reality |
|---|---|
| **Server (2 CPU / 12 GB)** | Coordinates and runs one small private model. The heavy thinking happens on free cloud models |
| **The laptop** | PC jobs only run while it's on and logged in. The server keeps answering either way |
| **"Call me"** | Bots can't place phone calls. Free: a loud Telegram voice note. Real calls need paid services |
| **Free text AI** | Plenty of options, each with daily caps; the gateway rotates between them |
| **Free voice** | ElevenLabs' free plan is about 10 minutes of speech a month; the local backup voice sounds more robotic |
| **Free images / video** | Small, changing free tiers; video is the hardest. Lesson 20 is honest about it |
| **Social media APIs** | Each platform has rules, approvals and limits; some are paid. Official APIs only, with my approval |
| **Cloud tools** | Calendar, email and tasks are stored by their providers (Google, Microsoft). Truly private things go to `private` |
| **"Does everything"** | Jarvis grows one ability per lesson; each works on its own |
