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
- **Next:** finish Lesson 03 hands-on, then run Lesson 04
