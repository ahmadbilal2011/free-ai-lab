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
- **Next:** follow Lesson 01 (SSH key → instance → first login)
