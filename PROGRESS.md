# Progress log

Newest entries at the top.

## 2026-10-28 — Day 1

- Created this repo (`free-ai-lab`)
- Planned the stack: Oracle Always Free VM + Docker + Ollama + Open WebUI + Tailscale + Vikunja
- Learned that Oracle halved Always Free Ampere A1 to **2 OCPU / 12 GB** in 2026 — the whole lab is designed to fit inside that
- Completed [Lesson 00 — Core concepts](lessons/00-concepts.md)
- Confirmed: account is **Always Free**, laptop is **Windows**
- Wrote [Lesson 01 — Create the Oracle VM](lessons/01-create-vm.md)
- Added [`scripts/create-free-vm.sh`](scripts/create-free-vm.sh): one Cloud Shell command creates the whole Always Free VM (with limit checks and capacity retries)
- Simplified the script: no key needed up front — it creates the SSH key in Cloud Shell, user `ubuntu` logs in from Cloud Shell, and the key is downloaded for Windows
- First real run failed: `ED25519 keys are not allowed in FIPS mode`. Oracle Cloud Shell is FIPS-hardened, so the script now creates an **RSA 4096** key instead
- ✅ VM created in `me-riyadh-1` and SSH login as `ubuntu` works — **Lesson 01 complete**
- Wrote [Lesson 02 — Secure the server](lessons/02-secure-server.md) and [`scripts/02-secure-server.sh`](scripts/02-secure-server.sh)
- ✅ Server secured, SSH from the Windows laptop works — **Lesson 02 complete**
- Wrote [Lesson 03 — Docker](lessons/03-docker.md), [`scripts/03-install-docker.sh`](scripts/03-install-docker.sh) and the practice stack [`stacks/hello`](stacks/hello/compose.yaml)
- Question: Kubernetes (cert-manager + ingress-nginx) instead of Docker? **Decision: Docker Compose now, K3s as a Phase 2 track** — see [docs/decisions.md](docs/decisions.md). Found that ingress-nginx was retired in March 2026
- Added autoheal (restarts frozen containers) and healthchecks to the plan
- Wrote [Lesson 04 — My own AI](lessons/04-ai.md), [`scripts/04-install-ai.sh`](scripts/04-install-ai.sh), stacks [`ai`](stacks/ai/compose.yaml) and [`autoheal`](stacks/autoheal/compose.yaml)
- ✅ Docker installed (Lesson 03) and the AI stack installed (Lesson 04)
- The SSH tunnel to Open WebUI didn't work for me, so we moved **Tailscale** straight in as the way to reach the AI — safer than opening port 3000 to the internet. The tunnel stays in Lesson 04 as an optional fallback
- Wrote [Lesson 05 — Tailscale](lessons/05-tailscale.md) and [`scripts/05-install-tailscale.sh`](scripts/05-install-tailscale.sh): private HTTPS with `tailscale serve` (not Funnel)
- ✅ Tailscale works: Open WebUI opens on my private `https://…ts.net` address — **Lesson 05 working on laptop**
- First chat: the 3B model answered, but wrongly tried a `create_calendar_event` **tool** for "Can you hear me?". Lesson: small models misuse tools; turned tools and background tasks (title/tags/follow-ups) off — added to Lesson 04
- Local 3B model works but is slow on 2 CPU cores. **Decision: hybrid AI** — free cloud APIs (Groq, Cerebras, …) for speed, local model as private fallback
- Expanded the course into a full path to my own **Jarvis**: LiteLLM gateway, n8n, Telegram bot, agents/harnesses, RAG, images, video, social posting, voice, security review — see [docs/roadmap.md](docs/roadmap.md)
- Wrote [Lesson 06 — Free cloud AI](lessons/06-free-cloud-ai.md) and [`scripts/06-test-api-key.sh`](scripts/06-test-api-key.sh) (tests a key hidden, never saves it)
- Cerebras asked for a **credit card** at signup → dropped. While checking alternatives, found that **GitHub Models was retired** (30 July 2026) → removed too. Replaced with **NVIDIA Build** and **OpenRouter** (no card)
- ✅ Added the cloud provider keys to Open WebUI — **Lesson 06 complete**
- Wrote [Lesson 07 — LiteLLM gateway](lessons/07-litellm-gateway.md), [`scripts/07-install-gateway.sh`](scripts/07-install-gateway.sh) and the [`gateway` stack](stacks/gateway/): aliases `smart` / `fast` / `private`, ordered fallback, keys in one private `.env`
- First gateway run: **no keys were entered** (they were only in Open WebUI), so every alias fell back to the local model. Fallback worked, but the script wrongly said "OK". Fixed: it now confirms each pasted key, warns when none are set, and reports `FELL BACK` honestly
- LiteLLM disables mock fallback tests by default, so the drill now uses a `drill` alias with a deliberately broken key
- Question: do we still need Open WebUI? **Yes**: LiteLLM has no chat screen; Open WebUI is the chat app. The mess was duplicated keys + practice leftovers → added [`scripts/cleanup-lab.sh`](scripts/cleanup-lab.sh) (never touches volumes or keys)
- Second run: keys saved (56/70/73 chars) but **every cloud model still fell back**. Wrote [`07-diagnose-gateway.sh`](scripts/07-diagnose-gateway.sh): keys OK, network OK — **all model names were dead** (Groq removed them, NVIDIA's hit end-of-life 26 Aug 2026, OpenRouter's no longer free)
- Big lesson: free-tier model names change constantly. Added [`07-pick-models.py`](scripts/07-pick-models.py): lists live models, tests them, generates the config automatically
- ✅ Third run: the picker found working models — Groq `openai/gpt-oss-120b` (smart) + `openai/gpt-oss-20b` (fast), NVIDIA `nvidia/nemotron-3-ultra-550b-a55b` (3 others failed their test), OpenRouter `nvidia/nemotron-3-ultra-550b-a55b:free`. **All aliases answered from the cloud; the drill fell back to a cloud backup**
- ✅ Open WebUI now uses only the gateway (`lab.smart` default, `lab.fast` task model); direct provider connections deleted; server cleaned — **Lesson 07 complete**
- Wrote [Lesson 08 — Backups and monitoring](lessons/08-backups-monitoring.md): restic → Oracle Object Storage (encrypted, nightly, restore-tested), healthchecks.io dead man's switch, `lab-status`
- Found Oracle's idle rule for A1 (CPU, network **and** memory < 20% for 7 days) → keep the private model loaded (`OLLAMA_KEEP_ALIVE=-1`) so memory stays above 20% with real usage
- ✅ Backups and monitoring set up — **Lesson 08 complete**

## 2026-10-30 — Day 2

- Drafted a Vikunja (self-hosted task manager) lesson, then **dropped it**: Jarvis doesn't need its own task app; it will connect to the free cloud tools I already use. The server hosts only what must be ours — see [docs/decisions.md](docs/decisions.md)
- Reshaped the roadmap around the real goal: **Jarvis controlled by text and voice, doing things for me, at $0**. Voice moved up to Lesson 11; Part 4 connects my cloud tools
- Asked whether Jarvis = Stanford's OpenJarvis. Decision: no, build our own from n8n + gateway + Telegram; OpenJarvis targets on-device AI (GPU / Apple Silicon, local fine-tuning), the opposite of a thin server. Kept as an optional comparison lesson
- Goal restated: **maximum quality, minimum server load** → thin server (gateway, n8n, private model, backups), heavy work on free cloud APIs. No OpenAI account needed: "OpenAI-compatible" is only the request format
- Wrote [Lesson 09 — n8n basics](lessons/09-n8n-basics.md), [`scripts/09-install-n8n.sh`](scripts/09-install-n8n.sh) and the [`jarvis` stack](stacks/jarvis/compose.yaml): SQLite (no Postgres), 1 GB memory cap, private editor on `:8443`, connected to the gateway, backed up nightly
- ✅ n8n installed, `Lab gateway` credential works — **Lesson 09 complete**
- Wrote [Lesson 10 — Telegram bot](lessons/10-telegram-bot.md) and [`scripts/10-telegram-webhook.sh`](scripts/10-telegram-webhook.sh): Telegram needs to reach n8n, so **only** the webhook paths go public via Tailscale Funnel (port 10000); editor and everything else stay private. Protected by path-only exposure, random IDs, Telegram secret token and a user-ID restriction
- Asked: why a script, can't Telegram be set up in n8n's UI? The bot **is** configured in the UI; the script only builds the network door Telegram needs to reach the server (outside n8n's control)
- While answering, found a bug: the door used port **10000**, but Telegram only delivers to 443/80/88/8443. Fixed: webhook door on **8443**, n8n editor moved to private **9443**. The script also cleans up the old setup
- **Next:** re-run the Lesson 10 script, open the editor at `:9443`, build `Jarvis chat`
