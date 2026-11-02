# Lesson 12 — OpenJarvis on the laptop, thinking with the server's brain

**Goal:** install **OpenJarvis** on your Windows laptop and make it think with the **same free cloud models** as Telegram, through your server's gateway. The laptop gets **no AI provider keys**: it borrows the server's brain. This lesson is chat only; Lesson 13 lets Jarvis *do* things on the PC.

**Time:** about 30–40 minutes (mostly the OpenJarvis install compiling).

**Cost:** $0. OpenJarvis is open source (Apache 2.0).

**Before you start:** Lesson 11 says `RESULT: ready for Lesson 12`, including the **C++ Build Tools** line. (That check was added after my first run; if you ran the check before, run it again.)

---

## Part A — The plan

```
 💻 Laptop                                        ☁️ Server
 OpenJarvis ── Tailscale (private, HTTPS) ──► gateway :4443 ──► smart / fast / private
   (no provider keys,                         (the same brain Telegram uses)
    only the gateway's key)
```

| Choice | Why |
|---|---|
| Think through the server's gateway | One set of keys, one place to change models, the same automatic fallback |
| Reach it over **Tailscale** on port **4443** | Private to your devices. Tailscale Funnel can't publish port 4443 at all, so it can never go public by mistake |
| Laptop holds only the **gateway key** | If the laptop is lost, you change one key on the server; your Groq/NVIDIA/... keys never left it |
| Ollama stays on the laptop | Offline fallback when the server is unreachable |

## Part B — Server: open the gateway to your tailnet (one command)

The gateway listens only on the server itself (`127.0.0.1:4000`). Publish it **inside your tailnet** on HTTPS port 4443. On the server:

```bash
sudo tailscale serve --bg --https=4443 http://127.0.0.1:4000 && tailscale serve status
```

You should see your n8n editor on `:9443` and now the gateway on `:4443`, both "tailnet only". Nothing is public.

## Part C — Laptop: install OpenJarvis

Open a **normal** PowerShell (not as administrator). This installs OpenJarvis without registering a background service (we add that in Lesson 13, when we need it):

```powershell
$env:OPENJARVIS_SKIP_SERVICE = '1'; irm https://open-jarvis.github.io/OpenJarvis/install.ps1 | iex
```

What it does (from its source): checks Python 3.10–3.13 and git, installs **uv**, downloads OpenJarvis to `%LOCALAPPDATA%\OpenJarvis\src`, **compiles** its Rust part (that's why it needs the C++ Build Tools, and why it takes a while), checks Ollama, pulls a small starter model (`qwen3.5:2b`) and adds a `jarvis` command.

When it finishes, **close PowerShell and open a new one**, then:

```powershell
jarvis --version
```

### If Windows Security says "Threats found" during the install

This happened on my laptop: **`Trojan:Win32/Suschil!rfn`** on a file in `C:\Users\<you>\.rustup\downloads\`, every time the installer fetched Rust. `!rfn` means a guess by Windows' machine-learning scanner, not a known virus. **Never click "Allow" on a guess: prove the file is genuine first.**

1. **See what was blocked** (PowerShell **as administrator**, read-only):
   ```powershell
   Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending | Select-Object -First 3 InitialDetectionTime, Resources | Format-List; Get-MpThreat | Select-Object ThreatName
   ```
2. **Check it against Rust's official release list.** rustup names each download after its SHA-256 fingerprint, so the file name *is* the fingerprint. Put it in `$h` (normal PowerShell):
   ```powershell
   $h = '<the long file name from step 1>'
   foreach ($c in '1.89.0', 'stable') {
     $f = "$env:TEMP\rust-$c.toml"
     Invoke-WebRequest -UseBasicParsing "https://static.rust-lang.org/dist/channel-rust-$c.toml" -OutFile $f
     $hit = Select-String -Path $f -Pattern $h -SimpleMatch
     if ($hit) { "FOUND in Rust $c list:"; (Get-Content $f)[($hit.LineNumber - 4)..($hit.LineNumber - 1)] } else { "not in Rust $c list" }
   }
   ```
   Mine said: **FOUND** → `rustfmt-1.89.0-x86_64-pc-windows-msvc.tar.xz`, Rust's official code-formatting tool. (Use a file and `Select-String` as above: my first try read the list with `.Content`, which Windows PowerShell 5.1 returns as raw bytes, and wrongly said "not found".)
3. **Only if FOUND:** Windows Security → **Protection history** → that entry → **Actions → Allow on device**. Then:
   ```powershell
   Remove-Item -Recurse -Force "$HOME\.rustup\downloads" -ErrorAction SilentlyContinue
   powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\OpenJarvis\src\deploy\windows\install.ps1" -SkipService
   ```
   **If NOT found: allow nothing**, and ask for help.
4. Optional: report the false alarm at [microsoft.com/wdsi/filesubmission](https://www.microsoft.com/wdsi/filesubmission).

Don't turn Windows Security off, and don't exclude whole folders: allow only the one detection you verified.

## Part D — Laptop: connect it to the server's brain

1. On the **server**, show the gateway key (paste it **only** into the next step, never into a chat):
   ```bash
   grep LITELLM_MASTER_KEY ~/lab/brain/.env
   ```
2. On the **laptop** (normal PowerShell):
   ```powershell
   irm https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/12-connect-laptop.ps1 | iex
   ```
   It finds your server on Tailscale, checks the gateway answers, asks for the key (**hidden**: paste the part after `=` and press Enter), tests it, saves it for your Windows user only, sets OpenJarvis to use `smart`, and asks a test question.
3. Type `clear` on the server.

Source: [`scripts/12-connect-laptop.ps1`](../scripts/12-connect-laptop.ps1)

### What it changed (so you can understand it)

| Setting | Value | Meaning |
|---|---|---|
| `engine.default` | `vllm` | OpenJarvis's generic "OpenAI-compatible server" connector is registered under the name `vllm`. Our gateway speaks that language. (Nothing to do with the vLLM software) |
| `engine.vllm.host` | `https://free-ai-lab.<tailnet>.ts.net:4443` | Where the gateway is |
| `intelligence.default_model` | `smart` | Use the gateway's best free model, with automatic fallback |
| Windows user variable `VLLM_API_KEY` | the gateway key | How OpenJarvis proves it's allowed to use the gateway |

See them any time: `jarvis config show` (the file lives at `C:\Users\<you>\.openjarvis\config.toml`).

## Part E — Talk to Jarvis on the PC

In a **new** PowerShell:

```powershell
jarvis
```

Ask anything. It answers with the same free models as on Telegram. Then:

```powershell
jarvis ask "Give me three tips to save battery on a Windows laptop"
jarvis chat -m fast                     # quicker, smaller model
jarvis chat -m private                  # the server's own private model (slower; never leaves the server)
jarvis chat -e ollama -m qwen3.5:4b     # offline: the laptop's own model, no server needed
```

> Jarvis can't **do** anything on the PC yet: this chat has no tools. That's on purpose. Lesson 13 adds PC actions, with a **Yes / No** before anything risky.

## Useful commands

| Task | How |
|---|---|
| Update OpenJarvis | `$env:OPENJARVIS_SKIP_SERVICE='1'; & ([scriptblock]::Create((irm https://open-jarvis.github.io/OpenJarvis/install.ps1))) -Force` |
| Gateway key changed on the server | Run `12-connect-laptop.ps1` again |
| Check everything | `jarvis doctor` |
| See settings | `jarvis config show` |

## If something goes wrong

| Problem | Fix |
|---|---|
| Installer: `MSVC build tools not found` | Install the C++ Build Tools (Lesson 11, row 5), restart, run the installer again |
| Installer: `Python 3.10 - 3.13 not found` | Lesson 11: Python 3.13 on PATH (`-Fix`), new PowerShell window |
| Installer: `Rust not found, installing into a temporary directory` … `could not read downloaded file` | Windows Security blocked the temporary Rust download. Don't turn protection off: delete `%LOCALAPPDATA%\puccinialin`, install Rust from [rustup.rs](https://rustup.rs) (Lesson 11, row 6), open a new PowerShell, run the installer again. Check **Windows Security → Protection history** to see what was blocked |
| Installer: `uv sync failed` | Scroll up for the first red error. Often a network hiccup: run the installer again. Send me the error if it repeats |
| `jarvis` not recognized | Open a **new** PowerShell window (the installer added it to PATH) |
| `No answer from https://…:4443` | Did you run Part B on the server? Is Tailscale connected on the laptop (tray icon)? |
| `The gateway rejected the key` | Copy only the part after `LITELLM_MASTER_KEY=`, nothing else |
| Answers come from the small laptop model | `jarvis config show`: `engine.default` must be `vllm`. Run the connect script again |
| Server unreachable (travelling, server down) | `jarvis chat -e ollama -m qwen3.5:4b` |

## Checklist

- [ ] Server: gateway published on `:4443`, tailnet only (`tailscale serve status`)
- [ ] Laptop: OpenJarvis installed, `jarvis --version` works in a new window
- [ ] `12-connect-laptop.ps1` passed all 4 steps; the test question was answered
- [ ] `jarvis` chat works with `smart`; offline chat works with Ollama

## Check your understanding

1. Why does the laptop hold only the gateway key, not the provider keys?
2. Why port 4443, and why does `tailscale serve` (not `funnel`) matter here?
3. What happens to laptop chats when the server is off, and what do you do then?

## Next

**Lesson 13 — PC jobs from your phone:** n8n sends a job to the laptop, Jarvis asks "Yes / No?" on Telegram, then does it.
