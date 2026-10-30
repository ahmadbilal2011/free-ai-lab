# Lesson 00 — Core concepts before we start

Before creating anything, it helps to understand the handful of ideas the whole lab is built on. Nothing here costs money or changes your Oracle account.

---

## 1. Cloud and virtual machines (VM)

A **cloud** is someone else's data centre that you rent computers from over the internet.
A **virtual machine (VM)** is a computer made of software: one big physical server is sliced into many smaller "virtual" computers. Each VM has its own CPU share, RAM, disk and operating system, and behaves like a real computer you reach over the network.

Oracle calls VMs **Compute Instances**.

## 2. Oracle Always Free — and its limits

Oracle gives every account a set of resources that stay free forever, in your **home region** (the region you chose at signup, which can never be changed).

What matters for us (as of 2026):

| Resource | Free limit |
|---|---|
| Ampere A1 (Arm) compute | **2 OCPU and 12 GB RAM in total** (halved from 4 OCPU / 24 GB in mid-2026) |
| AMD micro VMs | 2 VMs, each 1/8 OCPU and 1 GB RAM |
| Block storage (disks) | 200 GB total, including boot disks |

Important warnings:

- **Stay inside the limits.** Going over 2 OCPU / 12 GB on A1 can mean charges, or Oracle disabling the instances.
- **Free Trial vs Always Free.** New accounts get a 30-day trial with extra credit. If A1 usage is above the free limit when the trial ends, *all* A1 instances can be disabled. We will build within the free limit from day one, so this never affects us.
- **Idle accounts can be reclaimed.** Oracle may stop accounts or resources that sit unused. Running real services (like our AI) keeps it active.
- **"Out of host capacity" errors** are common when creating A1 instances. It just means Oracle's free Arm servers are busy; we retry. It is not your mistake.

## 3. Arm vs x86

CPUs come in "families" (architectures). Most laptops are **x86** (Intel/AMD). Oracle's free Ampere A1 is **Arm** (like phones and Apple M-chips).
Software must be built for the right family. Everything we use (Ubuntu, Docker, Ollama, Open WebUI, LiteLLM, n8n) supports Arm, so this is fine — but it's why we always check.

## 4. Linux and Ubuntu

The VM needs an operating system. We use **Ubuntu Server** — free, popular, and well documented. There's no desktop or mouse; you control it by typing commands in a **terminal**.

## 5. SSH and key pairs

**SSH (Secure Shell)** is how you open a terminal on a remote computer safely.

Instead of a password, we use an **SSH key pair**:

- **Private key** — stays on *your* PC, never shared, never committed to GitHub.
- **Public key** — uploaded to the server. Think of it as a lock that only your private key opens.

Key-based login is much safer than passwords, because there's nothing for attackers to guess.

## 6. IP addresses, ports and firewalls

- An **IP address** is the server's address on the network (like a phone number).
- A **port** is a numbered "door" on that address. Each service listens on its own port (SSH uses 22, websites use 80/443).
- A **firewall** decides which doors are open.

Oracle has **two** firewall layers: the cloud **Security List** (outside the VM) and the VM's own Linux firewall. Both must allow traffic for something to be reachable.

Our safety strategy: **open as few doors as possible to the public internet.** Only SSH will be public, and even that could be closed later.

## 7. Containers and Docker

A **container** packages an app with everything it needs, so it runs the same everywhere and doesn't mess up the rest of the system.
**Docker** is the tool that runs containers. Benefits for a beginner:

- Install an app with one command or one file (`docker compose`)
- Delete it cleanly if something goes wrong
- Update it easily

## 8. Running AI yourself

- An **LLM (Large Language Model)** is the "brain" behind chat AI. Many are open source (e.g. Llama, Qwen, Gemma, Phi).
- **Ollama** downloads and runs these models on your server.
- **Open WebUI** gives you a ChatGPT-like page to talk to them, and can be installed on your phone's home screen like an app.

**Honest expectation:** our server has no GPU and only 12 GB RAM, so we'll run **small models (about 1–4 billion parameters)**. They're good for everyday questions, drafting, summaries and simple coding help, but slower and less capable than ChatGPT or Claude. Answers may take several seconds to start.

Models are measured in **parameters** (e.g. "3B" = 3 billion). Bigger = smarter but needs more RAM. **Quantization** shrinks a model so it fits in less memory with a small loss of quality.

## 9. Reaching it from anywhere — safely

The risky way is to open the AI's port to the whole internet. Anyone could find it.

The safe way is **Tailscale**: it creates a private, encrypted network between *your* devices only (PC, phone, server). Your phone can reach the AI as if it were on your home Wi-Fi, but the rest of the internet can't even see it. The personal plan is free.

## 10. Git and GitHub

- **Git** tracks changes to files over time (like "save points").
- **GitHub** stores that history online.
- A **commit** is one save point with a message describing what changed.

This repo is our lab notebook: every lesson, config file and lesson learned is committed here.

---

## Check your understanding

1. Why do we use an SSH key instead of a password?
2. What's the difference between the Oracle Security List and the Linux firewall?
3. Why is Tailscale safer than opening the AI's port to the internet?
4. Why must we keep A1 usage at or below 2 OCPU / 12 GB?

## Next

**Lesson 01 — Create the Oracle VM safely.**
