# Lesson 11 — Prepare the Windows laptop

**Goal:** get the Windows laptop clean and ready to become Jarvis's **hands**: Python 3.13, git, Ollama and Tailscale in place, old experiments removed, and one script that tells you "ready" or exactly what's wrong.

**Time:** about 30 minutes (most of it is downloads).

**Cost:** $0. Everything here is free and open source.

**Before you start:** Parts 1–3 are done: the server answers you on Telegram. This lesson only touches the laptop.

---

## Part A — Why the laptop joins Jarvis

Until now, Jarvis lived only on the Oracle server: you talk to it on Telegram, it thinks with free cloud models and answers. But the server can't open an app on **your** PC. So the laptop becomes Jarvis's **hands**:

```
 Phone / PC ──► Telegram ◄── n8n (server, always on) ──► AI gateway (free models)
                                  │
                                  │  Tailscale only, with a key   (Lesson 13)
                                  ▼
                 Windows laptop: OpenJarvis (acts on the PC, asks first)
```

| Machine | Job |
|---|---|
| **Server** | Front door (Telegram), reminders, cloud tools, AI keys. Answers even when the laptop is off |
| **Laptop** | Opens apps, handles files, runs scripts, desktop voice. Acts **only when you ask**, and asks again before anything risky |

Why this split, and what's honestly not possible (like real phone calls): [decisions.md](../docs/decisions.md).

## Part B — What went wrong the first time (so you can skip it)

My first OpenJarvis install on the laptop failed several times. Each failure taught something:

| What happened | Why | The fix |
|---|---|---|
| Installer: `Python 3.10 - 3.13 not found` | I had **Python 3.15**. Newer isn't better here: OpenJarvis's libraries (numpy) have no Windows builds for 3.14+ yet | Install **3.13** next to it, then remove 3.15 |
| `winget : The term 'winget' is not recognized` | winget (Windows' package manager) isn't on every PC | Download installers from the official websites instead |
| Prompt showed `C:\WINDOWS\system32>` | PowerShell was **Run as administrator**. Things installed there can end up in the wrong user profile | Open PowerShell from the Start menu **normally**: prompt shows `C:\Users\<you>>` |
| Desktop app: `Could not start Ollama` | The desktop app needs **Ollama** already installed and running | Install Ollama first |
| `python` not recognized after installing 3.13 | Python wasn't on the **PATH** (the list of folders Windows searches for commands), and PATH changes only apply to **new** windows | The check script's `-Fix` puts it on PATH; then open a new window |
| A messy laptop | Half-finished tries of the desktop app, the command-line version, OpenClaw and Hermes, each with its own copy of config and API keys | Part C: one clean slate |

> **Rule from this lesson:** read the tool's supported versions **before** installing. "Latest" Python is often too new for AI libraries.

## Part C — Clean slate (only if you tried things before)

Skip this part on a fresh laptop.

**1. Quit** OpenJarvis, OpenClaw or Hermes if their icons are in the system tray (right-click → **Quit**).

**2. Uninstall** them in **Settings → Apps → Installed apps** (search the name → **⋯ → Uninstall**). Uninstall any Python **3.14 or newer** the same way. Keep Python 3.13 and "Python Launcher".

**3. Remove what uninstallers leave behind.** Paste in a normal PowerShell. It stops leftover processes, removes their scheduled tasks and deletes their folders. It does **not** touch Ollama, its models, Python 3.13 or anything else:

```powershell
Get-Process | Where-Object { $_.Path -match 'jarvis|hermes|OpenClaw' } | Stop-Process -Force -ErrorAction SilentlyContinue
Get-ScheduledTask | Where-Object { $_.TaskName -match 'jarvis' } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
$paths = @("$HOME\.openjarvis", "$HOME\OpenJarvis", "$env:LOCALAPPDATA\OpenJarvis", "$env:LOCALAPPDATA\com.openjarvis.desktop",
           "$env:LOCALAPPDATA\OpenClawTray", "$env:APPDATA\OpenClawTray", "$env:LOCALAPPDATA\hermes")
foreach ($p in $paths) { if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue; "Removed: $p" } }
```

**4. Revoke old keys.** Old tools keep API keys in files like `cloud-keys.env`, `.env` or `auth.json`. If you ever pasted a key into them, **revoke it in that provider's dashboard** and create a new one only when a lesson asks. From Lesson 12 on, the laptop holds **no provider keys at all**: it borrows the server's gateway.

## Part D — Install the four prerequisites

Do these in order. After each install, **close PowerShell and open a new (normal) one**.

| # | What | Why | Where |
|---|---|---|---|
| 1 | **Python 3.13 (64-bit)** | OpenJarvis is written in Python; 3.10–3.13 only | [python.org/downloads/windows](https://www.python.org/downloads/windows/) → latest **3.13.x** → *Windows installer (64-bit)*. On the first screen, tick **Add python.exe to PATH** |
| 2 | **Git for Windows** | The installer downloads OpenJarvis's code with git | [git-scm.com/download/win](https://git-scm.com/download/win), default options |
| 3 | **Ollama** | Runs small AI models on the laptop: the offline fallback | [ollama.com/download/windows](https://ollama.com/download/windows). After install, a llama icon sits in the tray |
| 4 | **Tailscale** | The private link the server uses to reach the laptop (Lesson 13). Same app you put on your phone in Lesson 04 | [tailscale.com/download/windows](https://tailscale.com/download/windows), log in with the **same account** as the server |

Quick self-checks (each in a new window):

```powershell
py -0p            # lists installed Pythons: 3.13 should be there, nothing 3.14+
git --version
ollama list       # a table (even empty) means Ollama is running
```

## Part E — One check that says "ready" or what's wrong

This script only **looks**: Windows build, admin window, Python versions and PATH, git, Ollama (and which models you have), leftovers from old installs, disk space, RAM/GPU, and Tailscale. It never deletes anything and never asks for keys.

```powershell
irm https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/11-check-laptop.ps1 | iex
```

If it says `'python' is missing or not a supported version`, run it **with `-Fix`**. That puts your Python 3.13 first on **your user's** PATH (no admin needed, nothing else changed):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/11-check-laptop.ps1))) -Fix
```

Then open a **new** window and run the plain check again. You want:

```
RESULT: ready for Lesson 12
```

Script source: [`scripts/11-check-laptop.ps1`](../scripts/11-check-laptop.ps1)

### How to read the hardware line

| Laptop | What it means for Jarvis |
|---|---|
| 16 GB+ RAM | Small local models (~2–4B, e.g. `qwen3.5:4b`) work as an offline fallback |
| 8 GB RAM | Keep local models tiny (`qwen3.5:0.8b`–`2b`); the server's free cloud models do the thinking |
| NVIDIA GPU | Local models get faster, but we still don't need them for daily use |

Either way, the **thinking** normally happens on the server's free cloud models (Lesson 06). The laptop only needs to **act**.

## Troubleshooting

| Problem | Fix |
|---|---|
| `py` is not recognized | Python wasn't installed with the launcher. Re-run the Python 3.13 installer → **Modify** → tick **py launcher** |
| `python` opens the Microsoft Store | That's Windows' placeholder. Run the check with `-Fix`, or turn off **Settings → Apps → Advanced app settings → App execution aliases → python.exe** |
| The check still says 3.15 / 3.14 is installed | Uninstall it in **Settings → Apps**. If it isn't listed, run `py uninstall 3.15` (newer Python Install Manager) |
| `Remove-Item` says a file is in use | Something is still running. Restart the laptop, then run Part C step 3 again |
| Ollama "not running" | Open **Ollama** from the Start menu (or run `ollama serve` in a window you leave open) |
| Tailscale "not connected" | Open Tailscale from the tray and log in with the same account you used on the server |

## Checklist

- [ ] Old OpenJarvis / OpenClaw / Hermes tries removed, old keys revoked
- [ ] Only supported Python left (`py -0p` shows 3.13, nothing 3.14+)
- [ ] `python --version` shows 3.13 in a new, normal window
- [ ] `git --version` works
- [ ] `ollama list` shows a table
- [ ] Tailscale connected with the same account as the server
- [ ] `11-check-laptop.ps1` says **ready for Lesson 12**

## Next

[Lesson 12](../README.md#lessons) — install OpenJarvis on the laptop and make it think through the **server's** gateway, so the laptop needs no API keys of its own.
