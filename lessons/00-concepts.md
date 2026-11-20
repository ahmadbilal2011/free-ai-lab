# Lesson 00 — The plan: learn n8n on your own free server

Before creating anything, here's **what we're building** and the handful of ideas the whole course rests on. Nothing in this lesson costs money or changes any account.

---

## 1. The goal

Learn **n8n**, step by step, on a server you own:

- **First, the foundation (Lessons 01–08):** a free Oracle server, made safe, with Docker, a switchboard for free AI models (Bifrost), n8n online with HTTPS, and daily backups.
- **Then n8n itself (the n8n track):** one idea per lesson, with a small workflow you build and test yourself: nodes and data, expressions, triggers, logic, APIs, code, errors, storage, AI, and finally small real projects.
- It costs **$0**: free and open-source software, Oracle's Always Free server, and free AI tiers.

New goals come after the n8n track.

## 2. The design

```
 📱 Phone / 💻 PC browser
          │  HTTPS
          ▼
 ☁️  SERVER  (Oracle Always Free, on 24/7)
      • Apache ......... the one public door: HTTPS, logins, fail2ban (the SAR→PKR site lives here too)
      • n8n ............ where you build workflows, in a web page
      • Bifrost ........ AI switchboard: many free AI models, added in a web page, automatic fallback
      • backups ........ a zip every night in /data/backups
```

| Choice | Reason |
|---|---|
| n8n runs on your own server | No monthly n8n bill, no limit on workflows or runs |
| The thinking uses **free cloud AI** | Free cloud models are far smarter and faster than anything a free 2-CPU server can run |
| One public door (Apache) | Each app gets its own HTTPS address with a login; nothing else is open |

**Honest limits, up front:**

| You might expect | Reality |
|---|---|
| Free AI forever, unchanged | Free tiers change often. Bifrost lets you swap models in a web page |
| The free server is always yours | Oracle may reclaim idle Always Free VMs; keep real work running and keep backups |

## 3. Cloud and virtual machines (VM)

A **cloud** is someone else's data centre that you rent computers from over the internet.
A **virtual machine (VM)** is a computer made of software: one big physical server is sliced into many smaller "virtual" computers. Each VM has its own CPU share, RAM, disk and operating system.

Oracle calls VMs **Compute Instances**.

## 4. Oracle Always Free, and its limits

Oracle gives every account resources that stay free forever, in your **home region** (chosen at signup, can't be changed).

| Resource | Free limit (2026) |
|---|---|
| Ampere A1 (Arm) compute | **2 OCPU and 12 GB RAM in total** (halved from 4 OCPU / 24 GB in mid-2026) |
| Block storage (disks) | 200 GB total, including boot disks |
| Object Storage | 20 GB (not used: backups are zips on the server, Lesson 08) |

Warnings:

- **Stay inside the limits.** Going over can mean charges, or Oracle disabling the instances.
- **Free Trial vs Always Free.** New accounts get a 30-day trial. If A1 usage is above the free limit when it ends, *all* A1 instances can be disabled. We stay inside the free limit from day one.
- **Idle servers can be reclaimed.** Oracle may reclaim an Always Free VM whose CPU, network **and** memory all stay very low for 7 days. Your server keeps real work running (including the private model, kept in memory), so it isn't idle.
- **"Out of host capacity"** when creating an A1 server just means Oracle's free Arm machines are busy. We retry. It's not your mistake.

## 5. Arm vs x86

CPUs come in "families". Most laptops are **x86** (Intel/AMD); Oracle's free A1 is **Arm**. Software must be built for the right family. Everything on our server (Ubuntu, Docker, Ollama, LiteLLM, n8n) supports Arm, but we always check.

Your Windows laptop is (usually) x86, and that's fine: its software is installed separately (Part 4).

## 6. Linux, SSH and keys

The server runs **Ubuntu Server**: no desktop; you type commands in a **terminal**. You reach it with **SSH (Secure Shell)** using a **key pair** instead of a password:

- **Private key**: stays on your laptop, never shared, never on GitHub.
- **Public key**: on the server, like a lock only your private key opens.

There's nothing for attackers to guess, so it's much safer than a password.

## 7. IP addresses, ports and firewalls

- An **IP address** is a machine's address on the network.
- A **port** is a numbered door on that address (SSH = 22, websites = 443).
- A **firewall** decides which doors are open.

Oracle has **two** firewall layers: the cloud **Security List** and the server's own Linux firewall. Our rule: **only SSH is public. Everything else is private.**

## 8. Containers and Docker

A **container** packages an app with everything it needs, so it runs the same everywhere and doesn't disturb the rest of the system. **Docker** runs containers; **Docker Compose** describes them in one file. You install, update or remove an app cleanly with one command.

## 9. AI models, APIs and the gateway

- An **LLM (Large Language Model)** is the "brain" behind chat AI. Some are open source and can run on your own machine; the best ones run in big data centres.
- An **API** lets a program use a service. With a free **API key**, our server can ask cloud models (Groq, NVIDIA, OpenRouter, Google Gemini...) questions. Each has a free daily limit.
- A **gateway** (we use **Bifrost**) sits in front of all of them: you add providers and models in its web page, apps ask it for a level of work (`quick`, `smart`, `code`), and it picks a working free model, switching automatically when one hits its limit.
- A **subscription** (Gemini Pro, Claude Pro) is not an API key. It powers command-line tools like Gemini CLI and Claude Code, which are separate from the free API keys this course uses.

## 10. Automation and agents

- **n8n** is an automation engine: you connect boxes ("nodes") into **workflows** in a web page. "When a Telegram message arrives → ask the AI → reply" is a workflow.
- An **agent** is an AI that can **use tools** (search, calendar, the PC) to finish a task, not just chat.
- The safety rule for every agent in this course: **it asks before acting** on anything irreversible.

## 11. Reaching everything privately: Tailscale

**Tailscale** creates a private, encrypted network between *your* devices only: server, laptop, phone. They reach each other from anywhere, while the rest of the internet can't even see them. The personal plan is free.

## 12. Git and GitHub

**Git** tracks changes to files ("save points", called **commits**); **GitHub** stores them online. This repo is the lab notebook: every lesson, script and lesson learned. **Secrets (keys, passwords, tokens) never go into it.**

---

## Check your understanding

1. Why does n8n run on your own server instead of n8n's cloud?
2. What's the difference between an API key and a subscription like Gemini Pro?
3. What does the gateway do when a free model hits its daily limit?
4. Why does every app sit behind one public door (Apache) instead of opening its own port?
5. Why must we keep A1 usage at or below 2 OCPU / 12 GB?

## Next

**Lesson 01 — Create the Oracle VM safely.**
