# free-ai-lab

My personal, **zero-cost** AI lab on Oracle Cloud Always Free, built step by step as a beginner.

## Goal

- Run my own private AI assistant using only open-source software
- Manage my daily tasks with a self-hosted task manager
- Reach both from anywhere — PC browser or phone — without paying anything
- Document every step here so I (and others) can learn and repeat it

## The stack

```
My phone / PC
      │   Tailscale (free private network — no public ports opened)
      ▼
Oracle Cloud VM  (Ubuntu, Arm Ampere A1, 2 OCPU / 12 GB RAM — Always Free)
  ├── Docker ........ runs every app in its own isolated container
  ├── autoheal ...... restarts any app that freezes
  ├── Ollama ........ engine that runs open-source AI models on the CPU
  ├── Open WebUI .... ChatGPT-style web interface (installable on phone)
  └── Vikunja ....... to-do lists and daily task management
```

| Component | What it is | Cost |
|---|---|---|
| Oracle Cloud Always Free | The server (virtual machine) | $0 within limits |
| Ubuntu Server | Operating system | Free, open source |
| Docker | Container runtime | Free, open source |
| Ollama | Local AI model runner | Free, open source |
| Open WebUI | AI chat interface | Free, open source |
| Tailscale | Private remote access | Free personal plan |
| Vikunja | Task manager | Free, open source |

## Lessons

| # | Lesson | Status |
|---|---|---|
| 00 | [Core concepts before we start](lessons/00-concepts.md) | ✅ Done |
| 01 | [Create the Oracle VM safely](lessons/01-create-vm.md) | ✅ Done |
| 02 | [Secure SSH access, updates and firewall](lessons/02-secure-server.md) | ✅ Done |
| 03 | [Install and understand Docker](lessons/03-docker.md) | ⏳ In progress |
| 04 | [Run my own AI: Ollama + Open WebUI](lessons/04-ai.md) | ⏳ Ready |
| 05 | Access from anywhere with Tailscale (PC + mobile) | ⬜ |
| 06 | Daily task management with Vikunja | ⬜ |
| 07 | Backups, monitoring and keeping it alive | ⬜ |

### Phase 2 — Kubernetes track (optional, after Phase 1)

Move the same apps from Docker Compose to Kubernetes, on the same free VM.

| # | Lesson | Status |
|---|---|---|
| K1 | K3s: lightweight Kubernetes on one node | ⬜ |
| K2 | Translate the Compose stacks into Kubernetes manifests and Helm | ⬜ |
| K3 | Traffic routing with Traefik / Gateway API (ingress-nginx is retired) | ⬜ |
| K4 | cert-manager and HTTPS certificates | ⬜ |
| K5 | Probes, resource limits and rolling updates vs. Docker autoheal | ⬜ |

Why this order: [docs/decisions.md](docs/decisions.md)

Progress log: [PROGRESS.md](PROGRESS.md)

## Ground rules for this repo

- **No secrets ever** — no passwords, SSH private keys, API tokens or real IP addresses are committed.
- Every lesson explains **why** before **how**.
- Every command I run is recorded with what it does.
