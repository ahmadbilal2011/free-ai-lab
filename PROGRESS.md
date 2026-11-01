# Progress log

Newest entries at the top.

## 2026-11-01 — Course v2: restart around one goal

- Wanted Jarvis to also **control my Windows PC** by voice. Tried Stanford's **OpenJarvis** on the laptop: the native Windows installer failed (I had **Python 3.15**; it needs 3.10–3.13, no numpy wheels for 3.14+), `winget` was missing, and the desktop app needed **Ollama** first
- Too many half-finished tries (OpenJarvis desktop + CLI, OpenClaw, Hermes) → clean slate on the laptop: every AI tool listed, each removal approved by me. Kept Python 3.13, Ollama + models, Gemini CLI. Old tools kept **API keys** in their own files → revoke keys from tools you remove
- Asked whether OpenJarvis alone is a complete Jarvis: **no** (no phone app; bots can't place phone calls; Gemini Pro / Claude Pro are subscriptions, not API keys)
- **Decision:** one Jarvis on two machines: the server is the always-on **brain and front door**, the laptop is the **hands** (OpenJarvis over Tailscale, thinking through the server's gateway). No ADB / phone control; maybe our own phone app later. See [docs/decisions.md](docs/decisions.md)
- **Restarted the course from Lesson 00** around that goal ([docs/roadmap.md](docs/roadmap.md)). Old lessons removed; what still holds (VM, security, Docker) carried over; Open WebUI dropped
- Added [`scripts/wipe-apps.sh`](scripts/wipe-apps.sh): removes every app, data, key file, backup timer and Tailscale publication from the server; keeps Ubuntu, SSH hardening, Tailscale and the Docker engine. Shows everything first and needs `WIPE` typed
- New: [Lesson 00 — The plan](lessons/00-concepts.md), [Lesson 04 — Tailscale](lessons/04-tailscale.md) + [`04-install-tailscale.sh`](scripts/04-install-tailscale.sh) (publishes nothing), [Lesson 11 — Prepare the Windows laptop](lessons/11-prepare-windows-laptop.md) + [`11-check-laptop.ps1`](scripts/11-check-laptop.ps1)
- `wipe-apps.sh` first asked for a password: it checked access with `sudo -v`, which prompts when *any* sudo rule needs a password (Ubuntu's `%sudo` rule), even though Oracle gives `ubuntu` `NOPASSWD`. Now it runs as root (`sudo bash wipe-apps.sh`) with no inner sudo calls. GitHub's raw cache served the old version for a few minutes → use a commit-pinned URL right after a fix
- Wrote [Lesson 05 — Free AI API keys](lessons/05-free-ai-keys.md) and [`05-add-ai-key.sh`](scripts/05-add-ai-key.sh): tests each key hidden, asks a live model, and saves it to one private file (`~/lab/brain/.env`, mode 600) for the gateway. Fixes v1's mistake of keys typed into one app but not the gateway
- Wrote [Lesson 06 — The AI gateway](lessons/06-ai-gateway.md): one `brain` stack (LiteLLM + Ollama) on a shared `jarvis` network, model picker reused from v1 (now also an optional Gemini `general` alias kept out of the personal chains), fallback drill, and an `ask` command for the terminal. Tested the picker, the alias checks and `ask` against fake providers
- **Next:** run Lessons 05 and 06 for real, then Lesson 07 (backups)

---

## Version 1 (2026-10-28 → 2026-11-01) — what I built and learned

The first version reached Lesson 11 (voice) on the server. Its lessons were replaced by v2; the lessons learned live on in [docs/decisions.md](docs/decisions.md) and in the new lessons as they're rewritten.

- **VM:** one Cloud Shell command creates the Always Free A1 VM (2 OCPU / 12 GB after Oracle halved the limit in 2026). Cloud Shell is FIPS-hardened, so the key is **RSA 4096**, not ED25519
- **Security, Docker:** key-only SSH, fail2ban, unattended upgrades, swap, no UFW. Docker Compose now, K3s as an optional later track (ingress-nginx retired March 2026)
- **Access:** the SSH tunnel to the chat app was awkward → **Tailscale** (`serve`, never Funnel)
- **AI:** the local 3B model was slow on 2 CPUs and misused tools → **hybrid**: free cloud models + local fallback. Cerebras wanted a credit card (dropped); GitHub Models was retired (dropped); Groq, NVIDIA Build, OpenRouter kept
- **Gateway:** first run had no keys entered, and then **every hard-coded model name was dead**. Fixed for good with a model picker that discovers and tests live models; apps only use aliases
- **Backups:** restic → Oracle Object Storage, nightly, restore-tested; healthchecks.io alerts; private model kept loaded to stay clear of Oracle's idle rule
- **n8n + Telegram:** first built with a public Funnel webhook door, then **rejected** it: n8n now **polls** Telegram, nothing public. Bot API, not my personal account. Accidentally pasted a bot token in a chat → revoked it with @BotFather
- **Voice:** Groq Whisper didn't understand my speech → ElevenLabs (Scribe ears, Eleven v3 voice with Urdu), Groq + local Piper as automatic backups. Free ElevenLabs accounts need a **pre-made** voice via the API, and the **secret key** (`sk_…`), not the Key ID
