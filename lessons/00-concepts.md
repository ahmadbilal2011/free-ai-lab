# Lesson 00 — The plan: what Jarvis is, and the ideas it's built on

Before creating anything, here's **what we're building** and the handful of ideas the whole course rests on. Nothing in this lesson costs money or changes any account.

---

## 1. What Jarvis will do

By the end of the course you have your own assistant, **Jarvis**:

- You **talk or type** to it: on your phone (Telegram) or at your Windows PC (microphone).
- It **answers by text and voice**, in your language.
- It **does things**: reminders, calendar, web search, writing; and on your PC it opens apps, handles files and runs scripts.
- It acts **only when you ask**, and asks **"Yes / No?"** before anything that can't be undone (sending, posting, deleting).
- It costs **$0**: free and open-source software, Oracle's Always Free server, and free AI tiers. Paid subscriptions you may already have (like Gemini Pro or Claude Pro) are used only for the hardest jobs, and only if you want.

## 2. The design: one brain, two hands

```
 📱 Phone ── Telegram (text + voice notes) ──┐
                                             ▼
 ☁️  SERVER  (Oracle Always Free, on 24/7) — Jarvis's BRAIN and FRONT DOOR
      • n8n ............ reads your messages, decides what to do, runs routines
      • AI gateway ..... one door to many free AI models, with automatic fallback
      • private model .. a small AI that runs on the server itself (backup + privacy)
      • voice .......... understands voice notes, answers with a voice
                                             │
                          private network (Tailscale), with a key
                                             ▼
 💻 WINDOWS LAPTOP (on when you're at it) — Jarvis's HANDS
      • OpenJarvis ..... acts on the PC: apps, files, scripts; asks before risky steps
      • microphone ..... talk to Jarvis at your desk
```

Why split it this way:

| Choice | Reason |
|---|---|
| The brain is on the server | It's on 24/7, so Jarvis answers your phone even when the laptop is off |
| The thinking uses **free cloud AI** | Free cloud models are far smarter and faster than anything a free 2-CPU server can run |
| The laptop is only the hands | Only your PC can act on your PC. It holds **no AI keys**; it borrows the server's |
| Telegram is the front door | Free, phone + PC apps, voice notes built in, and it works without opening any port |

**Honest limits, up front:**

| You might expect | Reality |
|---|---|
| "Jarvis calls me on the phone" | Bots can't place phone calls. Jarvis sends a **voice note with a loud notification** instead. Real calls need paid services |
| Jarvis controls my phone's apps | Not in this course. A Jarvis phone app of our own may come later |
| PC jobs while the laptop is off | They can't run; Jarvis tells you, and everything server-side still works |
| Free AI forever, unchanged | Free tiers change often. The course checks them live and switches automatically |

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
| Object Storage | 20 GB (we use it for encrypted backups) |

Warnings:

- **Stay inside the limits.** Going over can mean charges, or Oracle disabling the instances.
- **Free Trial vs Always Free.** New accounts get a 30-day trial. If A1 usage is above the free limit when it ends, *all* A1 instances can be disabled. We stay inside the free limit from day one.
- **Idle servers can be reclaimed.** Oracle may reclaim an Always Free VM whose CPU, network **and** memory all stay very low for 7 days. Jarvis's server keeps real work running (including the private model, kept in memory), so it isn't idle.
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
- A **gateway** (LiteLLM) sits in front of all of them: apps ask the gateway for `smart` or `fast`, and the gateway picks a working free model, switching automatically when one hits its limit.
- **Ollama** runs a small open model **on the server itself**: slower, but private and unlimited, and the last fallback.
- A **subscription** (Gemini Pro, Claude Pro) is not an API key. It powers command-line tools like Gemini CLI and Claude Code, which Jarvis can use on the laptop for hard jobs.

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

1. Why does Jarvis's brain live on the server and not on the laptop?
2. What's the difference between an API key and a subscription like Gemini Pro?
3. What does the gateway do when a free model hits its daily limit?
4. Why does Jarvis ask "Yes / No?" before sending or deleting anything?
5. Why must we keep A1 usage at or below 2 OCPU / 12 GB?

## Next

**Lesson 01 — Create the Oracle VM safely.**
