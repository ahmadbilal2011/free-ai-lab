# Lesson 04 — Tailscale: one private network for the server, laptop and phone

**Goal:** your server, your Windows laptop and your phone join **one private network** that only your devices can see. Every later lesson uses it: the laptop reaches the server's AI, the server sends PC jobs to the laptop, and you open n8n's editor from anywhere. **Nothing gets a public port.**

**Time:** about 20 minutes.

**Cost:** $0. Tailscale's Personal plan is free.

**Before you start:** Lessons 01–03 are done (server created, secured, Docker installed).

---

## Part A — Why Tailscale

Jarvis lives on two machines plus your phone. They need to talk to each other, from anywhere (home Wi-Fi, office, mobile data). Two ways to do that:

| | Open ports to the internet | **Tailscale** ✅ |
|---|---|---|
| Who can knock on the door | Anyone on the internet | Only devices logged in to **your** Tailscale account |
| Encryption | You must set up HTTPS yourself | Always encrypted (WireGuard) |
| Works on mobile data / behind home routers | Often needs router changes | Yes, nothing to configure |
| Mistakes | One wrong setting exposes an app | Apps stay invisible to the internet |

```
            Your private tailnet (only your devices)
   ┌──────────────────────────────────────────────────────────┐
   │  Phone  ◄────►  Server (free-ai-lab)  ◄────►  Laptop     │
   └──────────────────────────────────────────────────────────┘
        The rest of the internet sees only the server's SSH port.
```

Two Tailscale words you'll meet later:

| Word | Meaning | Do we use it? |
|---|---|---|
| **serve** | Publish one app with HTTPS **inside your tailnet only** | ✅ Yes, from Lesson 08 (n8n editor) |
| **funnel** | Publish an app **to the whole internet** | ❌ Never. Jarvis reaches out; nothing reaches in |

## Part B — Put the server on the tailnet

On the server (SSH in as in Lesson 01):

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/04-install-tailscale.sh -o 04-install-tailscale.sh && sudo bash 04-install-tailscale.sh
```

It shows a **login link**. Open it in your laptop's browser, sign in (Google, Microsoft, GitHub or Apple: pick the account you'll use on all your devices), approve the machine. The script then prints the server's private name (`free-ai-lab.<your-tailnet>.ts.net`) and private IP (`100.x.y.z`).

Script source: [`scripts/04-install-tailscale.sh`](../scripts/04-install-tailscale.sh)

## Part C — Add your laptop and phone

| Device | Install | Then |
|---|---|---|
| Windows laptop | [tailscale.com/download/windows](https://tailscale.com/download/windows) | Log in with the **same** account |
| Phone | Tailscale app from the Play Store / App Store | Log in with the **same** account |

You don't need Tailscale on the phone for Telegram (Lesson 09), but you will for opening n8n's editor and other private pages from the phone.

## Part D — Two settings in the admin console

Open [login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines):

1. **Key expiry:** click **⋯** next to `free-ai-lab` → **Disable key expiry**. Without this, the server logs itself out after about 6 months, and Jarvis goes deaf.
2. **HTTPS:** on the **DNS** page, make sure **MagicDNS** is on and enable **HTTPS Certificates**. Later lessons use this for private `https://…ts.net` pages.

## Part E — Test it

From the **laptop** (PowerShell), log in to the server through the private network instead of its public IP:

```powershell
ssh -i $HOME\.ssh\free-ai-lab ubuntu@free-ai-lab
```

That's the key you saved in Lesson 01. If it logs in, the private network works. On the **phone**, the Tailscale app should list `free-ai-lab` as connected.

## What this lesson did NOT do

- It didn't publish any app (there's nothing to publish yet).
- It didn't close public SSH. That's an optional hardening step once you're sure you can always reach the server through Tailscale (or Oracle's Cloud Shell as a backup).

## Troubleshooting

| Problem | Fix |
|---|---|
| The script waits forever | The login link wasn't approved. Open it again (scroll up), approve, and the script continues |
| `ssh: Could not resolve hostname free-ai-lab` | MagicDNS is off, or the laptop isn't logged in. Use the `100.x.y.z` IP instead, and check the Tailscale icon on the laptop |
| SSH asks for a password | Wrong key file. Use the same `-i` key that works from Lesson 01 |
| Server shows "expired" in the admin console | Key expiry wasn't disabled. Run `sudo tailscale up` on the server, re-approve, then disable expiry |

## Checklist

- [ ] Server shows connected in the Tailscale admin console
- [ ] Laptop and phone logged in with the same account
- [ ] Key expiry disabled for `free-ai-lab`; MagicDNS and HTTPS certificates on
- [ ] SSH from the laptop to `ubuntu@free-ai-lab` works

## Check your understanding

1. What's the difference between `tailscale serve` and `tailscale funnel`, and why do we never use funnel?
2. Why disable key expiry on the server but not on your phone?
3. Why can Telegram reach Jarvis even when your phone isn't on Tailscale?

## Next

**Lesson 05 — Free AI API keys: Jarvis's brain at $0.**
