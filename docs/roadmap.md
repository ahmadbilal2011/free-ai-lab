# Course roadmap: learn n8n at $0

**The goal:** learn **n8n** properly, one step at a time, on my own free Oracle server. New goals come after the n8n track.

Design choices: [decisions.md](decisions.md).

Rules for the whole course:

- **$0, no credit card.** Any provider that starts asking for one is dropped.
- **Public only behind locks.** n8n and Bifrost are published through Apache (HTTPS, own login, fail2ban); app ports stay private.
- **Privacy rule:** customer data (e.g. the SAR→PKR site) never goes to free AI tiers.
- **Secrets never touch GitHub.** Keys live in `.env` files or in n8n credentials.
- **One idea per lesson.** Each n8n lesson ends with a small workflow I build myself and a check that proves it works.
- **Every step is tested** before the lesson is marked ✅ Tested.

---

## Part 1 — Foundation (done)

| # | Lesson | What I get |
|---|---|---|
| 00 | **The plan** | The whole picture before touching anything |
| 01 | **Create the Oracle VM** (one Cloud Shell command) | An Always Free Arm server |
| 02 | **Secure the server** | Key-only SSH, automatic updates, fail2ban, swap |
| 03 | **Docker** | Every app in its own container |
| 04 | **Tailscale** (optional, not used now) | A private network for my devices |
| 05 | **Bifrost**: free AI models in a web page | One address for many free models, with fallback |
| 06 | **n8n online and safe** | n8n at its own HTTPS name, owner login + 2FA |
| 07 | **A Telegram AI bot** (text and voice) | Built early; rebuilt cleanly in n8n 13 |
| 08 | **Backups** | Nightly zip of everything in /data/backups |

## Part 2 — The n8n track

| # | Lesson | What I can do after it |
|---|---|---|
| n8n 01 | [Your first workflow](../lessons/n8n/01-first-workflow.md): trigger, nodes, run, items, the three data views, executions | Build and run a 3-node workflow and read its data |
| n8n 02 | Data and expressions: `{{ }}`, `$json`, drag and drop, dates with `$now` | Calculate and reshape data (e.g. SAR → PKR) |
| n8n 03 | Triggers: Schedule, Webhook (test vs production URL), Form; Publish | Workflows that start by themselves |
| n8n 04 | Logic: If, Switch, Filter, Merge | Different paths for different data |
| n8n 05 | Many items: lists, Split Out, Aggregate, Loop Over Items | Handle 1 or 1,000 records the same way |
| n8n 06 | Talk to APIs: HTTP Request, credentials (free exchange-rate API) | Pull live data from any web service |
| n8n 07 | The Code node: small JavaScript when nodes aren't enough | Custom logic in a few lines |
| n8n 08 | Errors: error outputs, retries, an Error workflow that tells you on Telegram | Workflows that fail loudly and safely |
| n8n 09 | Storing data: n8n Data tables | Keep lists and history between runs |
| n8n 10 | AI nodes: Basic LLM Chain, structured output, Bifrost models | Summarise, classify and extract with free AI |
| n8n 11 | AI Agent: tools and memory | An assistant that uses your workflows as tools |
| n8n 12 | Sub-workflows: build once, reuse everywhere | Tidy, reusable building blocks |
| n8n 13 | Projects: SAR→PKR rate alert; the Telegram voice bot rebuilt cleanly | Real automations from scratch |
| n8n 14 | Good habits: names, notes, versions, export to GitHub, backups | Workflows you can trust and restore |

## Later

New goals, decided after the n8n track.
