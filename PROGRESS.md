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
- **Next:** create Groq + NVIDIA/OpenRouter keys and add them to Open WebUI
