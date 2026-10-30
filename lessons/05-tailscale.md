# Lesson 05 — Access from anywhere with Tailscale (PC + mobile)

**Goal:** open your AI from your Windows laptop and your phone, from anywhere, over **HTTPS**, without opening any port to the public internet.

**Time:** about 15–20 minutes.

**Cost:** $0 (Tailscale's free Personal plan).

**Before you start:** Lesson 04 is installed: `docker ps` shows `open-webui` as **(healthy)**.

---

## Part A — The problem and the safe answer

Open WebUI listens on `127.0.0.1:3000`, which only the server itself can reach. To use it from your laptop or phone there are three options:

| Option | How | Verdict |
|---|---|---|
| Make port 3000 public | Open it in Oracle's Security List and iptables | ❌ The whole internet can find your AI login page and attack it. Plain HTTP, no encryption. |
| SSH tunnel | `ssh -L 3000:...` from the laptop | ⚠️ Works, but only on a PC, only while a window stays open. Not practical on a phone. |
| **Tailscale** | A private network between *your* devices | ✅ Invisible to the internet, encrypted, works on phone and PC, gives real HTTPS. |

## Part B — How Tailscale works

Tailscale builds a **private network (a "tailnet")** made only of devices signed in to **your** account. Every device gets a private address (`100.x.y.z`) and a name like `free-ai-lab.your-tailnet.ts.net`.

```
  Your phone ─┐
              ├── encrypted WireGuard tunnels ──► free-ai-lab (Oracle VM)
  Your laptop ┘          (your tailnet only)        https://free-ai-lab.<tailnet>.ts.net
                                                         │
  Anyone else on the internet ──────────────────────✖   (can't see or reach it)
```

Key ideas:

- **Outbound only.** The server connects *out* to Tailscale. We don't open any new inbound port on Oracle.
- **WireGuard** is the modern encryption protocol underneath.
- **MagicDNS** gives each device a readable name instead of an IP.
- **`tailscale serve`** puts an app (our Open WebUI on port 3000) behind **HTTPS** with a real certificate, reachable **only inside your tailnet**.
- **`tailscale funnel`** would publish an app to the *public internet*. **We do not use Funnel.**

Why HTTPS matters: it encrypts the traffic *and* lets you **install Open WebUI on your phone like an app** (browsers only allow that on HTTPS sites).

> Small privacy note: HTTPS certificates are recorded in public logs, so your tailnet's `*.ts.net` *name* can be seen there. That doesn't give anyone access; only your signed-in devices can connect.

---

## Part C — Install on the server (one command)

On the VM:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/05-install-tailscale.sh -o 05-install-tailscale.sh && sudo bash 05-install-tailscale.sh
```

What happens:

1. **Installs Tailscale** from its official package.
2. **Prints a login link** and waits. Open it in your laptop's browser, sign in with Google, Microsoft, GitHub or Apple (this creates your free Tailscale account), and approve the machine `free-ai-lab`. The script continues by itself.
3. Runs **`tailscale serve`** to publish Open WebUI over HTTPS, inside your tailnet only.
   - The first time, Tailscale may print a **link to enable HTTPS / Serve** for your tailnet. Open it, click **Enable**, and the script continues.
4. Prints your private address, like `https://free-ai-lab.tail1234.ts.net`.

`--operator=ubuntu` is also set, so you can run `tailscale status` later without `sudo`.

### Turn off key expiry for the server (important)

By default every device must re-authenticate about every 6 months. For a server nobody is watching, that means it silently drops off your network one day.

1. Go to <https://login.tailscale.com/admin/machines>
2. Find **free-ai-lab** → click the **⋯** menu → **Disable key expiry**

Keep key expiry **on** for your laptop and phone. If one is lost or stolen, its access ends by itself; you can also remove it immediately from this page.

---

## Part D — Connect your laptop and phone

### Windows laptop

1. Download from <https://tailscale.com/download/windows> and install.
2. Click the Tailscale icon near the clock → **Log in** → use the **same account** as the server.
3. Open the address the script printed, e.g. **https://free-ai-lab.tail1234.ts.net**
4. Log in to Open WebUI. **If you haven't created an account yet, do it now. The first account becomes the admin.**

### Phone (Android or iPhone)

1. Install **Tailscale** from the Play Store / App Store.
2. Log in with the **same account** and turn the connection **on** (the phone will ask to add a VPN; allow it).
3. Open the same `https://free-ai-lab....ts.net` address in Chrome (Android) or Safari (iPhone).
4. **Install it as an app:**
   - Android, Chrome: **⋮ → Add to Home screen / Install app**
   - iPhone, Safari: **Share → Add to Home Screen**

You now have your own AI app icon on your phone 🎉. It works on Wi-Fi or mobile data, anywhere, as long as Tailscale is connected.

---

## Part E — Check that it's private

From your laptop **with Tailscale on**: the `https://...ts.net` address opens. ✅

Now **turn Tailscale off** on your phone (or laptop) and reload the page: it should **fail to load**. ✅ That proves only your tailnet can reach it.

Port 3000 is still **not public**, and Oracle's Security List still only allows SSH (22). Nothing was opened.

### Handy commands (on the VM)

| Command | What it does |
|---|---|
| `tailscale status` | Devices in your tailnet and whether they're online |
| `tailscale serve status` | What is being served over HTTPS |
| `tailscale ip -4` | The server's private `100.x` address |
| `tailscale ping <device-name>` | Test the connection to one of your devices; shows if it's direct or relayed |
| `tailscale serve reset` | Stop serving Open WebUI over HTTPS |

> "Relayed" connections (via Tailscale's DERP servers) are still end-to-end encrypted, just a little slower. That's normal on cloud servers.

### Bonus: SSH over Tailscale

With Tailscale on your laptop, you can also SSH to the server through the private network:

```powershell
ssh -i $HOME\.ssh\free-ai-lab ubuntu@free-ai-lab
```

Later (Lesson 07) we can even **close public SSH** in Oracle's Security List, so the server has **zero** public open ports. We'll do it carefully, once you've used Tailscale SSH for a while.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| The login link expired | Run the script again; it prints a new link. |
| Page doesn't open on the laptop/phone | Is Tailscale connected on that device, with the **same account**? Run `tailscale status` on the VM; your devices should appear. |
| Certificate / privacy warning in the browser | Wait a minute and reload (first certificate). Make sure HTTPS is enabled: admin console → **DNS** → **HTTPS Certificates**. |
| `502 Bad Gateway` | Open WebUI is down. Check `docker ps` on the VM and `docker logs open-webui`. |
| Works on laptop, not on phone | Check the phone's VPN toggle in the Tailscale app is on. Some office or school Wi-Fi blocks VPNs; try mobile data. |

---

## Checklist

- [ ] Ran `05-install-tailscale.sh` and approved the server in the browser
- [ ] Disabled **key expiry** for `free-ai-lab` in the admin console
- [ ] Opened `https://free-ai-lab.<tailnet>.ts.net` on the laptop and logged in as admin
- [ ] Installed Open WebUI on the phone's home screen and chatted from mobile data
- [ ] Proved it's private: Tailscale off → page doesn't load
- [ ] Wrote today's notes in `PROGRESS.md` (no IPs, no tailnet name)

## Check your understanding

1. Why is Tailscale safer than opening port 3000 to the internet?
2. What's the difference between `tailscale serve` and `tailscale funnel`?
3. Why did we disable key expiry only for the server, and not for the phone?
4. Why does HTTPS let you install Open WebUI as a phone app?

## Next

**[Lesson 06 — Free cloud AI via API keys](06-free-cloud-ai.md)**.
