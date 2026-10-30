# Design decisions

Short records of important choices: what we chose, what we didn't, and why. Newest first.

---

## 2026-10-28 — Docker Compose now, Kubernetes (K3s) later

**Question:** Should the lab run on Kubernetes with cert-manager and ingress-nginx instead of Docker?

**Decision:** Phase 1 uses **Docker Compose + healthchecks + autoheal**. Kubernetes becomes an optional **Phase 2 track** that migrates the same apps to **K3s**.

**Why:**

| Point | Detail |
|---|---|
| ingress-nginx is retired | The Kubernetes project ended its maintenance in March 2026. New setups should use Traefik (bundled with K3s) or the Gateway API instead. |
| No public HTTPS needed | Everything is private behind Tailscale, which also provides free HTTPS certificates on `*.ts.net`. cert-manager with Let's Encrypt would need a domain and public ports 80/443. |
| RAM goes to the AI | 12 GB total. K3s needs roughly 0.5–1 GB more, which the model needs. |
| Single node | Kubernetes' biggest strength is moving work between servers. With one VM, its self-healing is close to Docker with healthchecks + autoheal. |
| Learning order | Get a working AI first; then learning Kubernetes on apps you already understand is much easier. |

**Self-healing in Phase 1:**

| Failure | Handled by |
|---|---|
| Container crashes | `restart: unless-stopped` |
| Container frozen (healthcheck failing) | autoheal |
| Docker daemon crashes | systemd restarts it |
| Server reboots | Docker starts at boot, containers come back |
| Whole VM lost | Backups (Lesson 07). No single-server setup can avoid this, Docker or Kubernetes. |

**Revisit when:** Phase 1 (Lessons 04–07) is complete.

Sources: [Ingress NGINX retirement — Kubernetes blog](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/), [Kubernetes Steering & Security Response Committees statement](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)

---

## 2026-10-28 — RSA 4096 key created in Cloud Shell

Oracle Cloud Shell runs in FIPS mode, which forbids ED25519 keys. The VM script creates an RSA 4096 key in Cloud Shell, and the user downloads it to Windows. Students who prefer a laptop-created key can pass `SSH_PUBLIC_KEY`.

## 2026-10-28 — Keep Oracle's iptables, no UFW

Oracle advises against UFW on its Ubuntu images (it can conflict with the built-in iptables rules). We keep Oracle's rules and expose nothing publicly except SSH.

## 2026-10-28 — Reach Open WebUI through Tailscale, not a public port

The SSH tunnel was awkward (PC only, window must stay open) and failed on first try. Making port 3000 public would expose the login page to the whole internet over plain HTTP. **Decision:** use Tailscale right after Lesson 04: `tailscale serve` gives tailnet-only HTTPS on `*.ts.net`, works on phone and PC, and opens no inbound port. We don't use `tailscale funnel` (public) for apps. *(Updated 2026-10-30: one narrow exception for Telegram webhooks, see below.)* The SSH tunnel remains documented as a fallback.

## 2026-10-28 — Hybrid AI: free cloud APIs + local fallback

The local 3B model is slow on 2 CPU cores. **Decision:** add free cloud API providers (Groq, Cerebras first; GitHub Models, OpenRouter, Gemini optional) to Open WebUI, and keep Ollama as a private, unlimited fallback. **Privacy rule:** personal data only goes to providers that don't train on prompts. Gemini's free tier trains on data in KSA, so it's for general questions only. Lesson 07 adds LiteLLM for automatic fallback between providers.

## 2026-10-28 — Drop Cerebras and GitHub Models; use NVIDIA Build and OpenRouter

Cerebras now asks for a credit card at signup, which breaks our $0 / no-card rule. GitHub Models was retired by GitHub on 30 July 2026. **Decision:** main providers are **Groq** and **NVIDIA Build (NIM)**, with **OpenRouter** free models as a third, and Gemini optional for general questions. If any provider starts asking for a card, it gets dropped the same way.

## 2026-10-28 — Never hard-code provider model names; discover and test them

The first gateway config used model names from memory. A live diagnosis showed **all of them** had gone: Groq no longer had `llama-3.3-70b-versatile` / `llama-3.1-8b-instant`, NVIDIA's `meta/llama-3.3-70b-instruct` reached end of life on 26 Aug 2026, and OpenRouter's Llama 3.3 70B stopped being free. **Decision:** the installer runs `07-pick-models.py`, which lists each provider's *current* models, ranks them by preference, tests candidates with a tiny request, and generates the config. Apps only ever use our aliases (`smart`, `fast`, `private`), so provider churn never reaches them.

## 2026-10-28 — Backups: restic to Oracle Object Storage, healthchecks.io alerts

Off-server, encrypted, tested, automatic and watched. restic encrypts before upload and deduplicates; Oracle Always Free gives 20 GB of Object Storage via an S3-compatible API. AI models are excluded (re-downloadable). Open WebUI is paused a few seconds so its SQLite file is copied consistently. A healthchecks.io dead man's switch (heartbeat every 5 min + nightly backup ping) emails us when the server or a backup stops, which an on-server monitor can't do. To stay clear of Oracle's A1 idle-reclaim rule, the private model stays loaded (real memory use > 20%) rather than running fake load.

## 2026-10-30 — No self-hosted task app; Jarvis connects to free cloud tools

Lesson 09 was going to self-host Vikunja. **Decision: dropped before installing.** Jarvis doesn't need its own task app: the tasks just need to live somewhere Jarvis can reach, and free cloud tools (calendar, reminders, email) already have polished phone apps and notifications, keep working when our server is down, and n8n has ready-made connectors for them. Self-hosting would add a container to update and back up for little gain. **Principle from now on:** the server hosts only what must be ours (AI gateway, n8n, private model, backups); everything else stays in free cloud tools. Trade-off: that data is stored by those providers, so truly private things go to the local model. Voice moved earlier (Lesson 11) because text **and voice** control is the core of Jarvis.

## 2026-10-30 — Our own Jarvis on n8n, not OpenJarvis; thin server, cloud brains

Goal: maximum quality with minimum server load. **Decision:** the server only coordinates (n8n, LiteLLM gateway, small private model, backups); thinking, speech, images and video run on free cloud APIs. n8n uses its built-in SQLite (no Postgres container) and a 1 GB memory cap. Stanford's OpenJarvis (Apache 2.0) was considered: good ideas (Telegram channel, MCP, scheduler, presets), but it's designed to run models on-device with GPU/Apple Silicon and fine-tune locally, so its strengths would sit idle on a 2-CPU, no-GPU VM. Kept as an optional comparison lesson. The small local model stays: privacy option, last fallback, and keeps memory above Oracle's idle threshold.

## 2026-10-30 — One narrow public door: Tailscale Funnel for n8n webhook paths only

Telegram delivers messages by calling a webhook on our server, and n8n's Telegram Trigger only supports webhooks. **Decision:** Tailscale Funnel on port 10000, **only** for `/webhook` and `/webhook-test`. The n8n editor (:8443), Open WebUI (:443), the gateway and SSH stay private, and no Oracle port is opened. Four layers protect the door: path-only exposure, random webhook IDs, Telegram's secret token (n8n's Telegram Trigger rejects requests without it with HTTP 403), and "Restrict to User IDs" so only the owner's messages are processed. Rejected: exposing n8n publicly (editor holds all credentials) and hand-made polling (wasteful, slower). `10-telegram-webhook.sh --off` closes the door.
