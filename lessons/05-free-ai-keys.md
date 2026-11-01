# Lesson 05 — Free AI API keys: Jarvis's brain at $0

**Goal:** get free API keys from several AI providers, prove each one works from the server, and keep them in **one private file** that only you can read. Lesson 06 builds Jarvis's AI gateway on top of them.

**Time:** about 20 minutes.

**Cost:** $0. No credit card anywhere. If a provider asks for one, skip that provider.

**Before you start:** Lessons 01–04 are done. (Coming from the first version of the course? Run `wipe-apps.sh` first, see the [README](../README.md).)

---

## Part A — Why cloud keys, and why several

Jarvis needs a **brain**: a large language model (LLM). The server has 2 CPUs and no GPU, so a model running *on* it is small and slow. Cloud AI companies run much bigger models on fast hardware, and several give a **free tier**: a daily allowance at no cost.

```
               ┌─► Groq        (very fast)              ─┐
 Jarvis ──► gateway ─► NVIDIA      (many big models)        ├─ free daily limits, no card
 (Lesson 06)   ├─► OpenRouter  (many free models)       ─┘
               └─► private model on the server (slow, unlimited, last resort)
```

Each free tier has limits. With **several** providers, when one runs out, Jarvis switches to the next automatically (Lesson 06). That's why we collect more than one key.

## Part B — Three ideas

### 1. An API key is a password

An **API** lets programs use a service. The **API key** proves a request comes from your account.

> **Treat every key like a password.** Never paste it into GitHub, chats (including AI chats), screenshots or emails. If a key leaks, **delete it** on the provider's site and make a new one. That takes a minute and costs nothing.

### 2. "OpenAI-compatible"

Most providers accept the same request format that OpenAI made popular. So one gateway can talk to all of them; only the **address** and the **key** change. You don't need an OpenAI account.

### 3. Limits and HTTP 429

Free tiers limit requests per minute and per day. Going over returns **HTTP 429 — Too Many Requests**. Nothing breaks: you wait, or the gateway switches provider.

## Part C — Which providers (and the privacy rule)

**Privacy rule:** personal data (your messages, calendar, emails) only goes to providers that **don't train on it**.

| Provider | Free tier (roughly, late 2026) | Trains on prompts? | Jarvis uses it for |
|---|---|---|---|
| **Groq** ⭐ | Around 1,000 requests a day | No | First choice, everything |
| **NVIDIA Build** ⭐ | Around 40 requests a minute | No | Backup, big models |
| **OpenRouter** | Around 50 requests a day on `:free` models | Depends on each model's provider | Third choice |
| Google Gemini *(optional)* | Small daily caps | **Yes, in Saudi Arabia** (humans may review) | **General questions only**, never personal data |

Free tiers change often (in 2026, Cerebras started asking for a credit card and GitHub Models was retired, so both left this course). **Always check the provider's own limits page**, and expect to swap providers sometimes. Lesson 06 makes that painless.

> Your **Gemini Pro** or **Claude Pro** subscription is **not** an API key. Those subscriptions power tools like Gemini CLI and Claude Code on your laptop (Lesson 15). A Gemini API key from AI Studio is separate and free.

## Part D — Create the keys (in your laptop's browser)

Open a Notepad window to hold each key **for a few minutes only**; you'll close it without saving at the end.

**Groq**
1. <https://console.groq.com> → sign in (Google or GitHub).
2. **API Keys** → **Create API Key** → name it `jarvis` → copy it (starts with `gsk_`).

**NVIDIA Build**
1. <https://build.nvidia.com> → sign in / create a free NVIDIA account (it may verify your phone number).
2. Open any model page → **Get API Key** → copy it (starts with `nvapi-`).
3. **If it asks for a credit card, stop** and skip NVIDIA.

**OpenRouter**
1. <https://openrouter.ai> → sign in → **Keys** (<https://openrouter.ai/keys>) → **Create Key** → name `jarvis` → copy it (starts with `sk-or-`).
2. Don't add credits. Models ending in `:free` work without any.

**Gemini (optional)**
1. <https://aistudio.google.com/apikey> → **Create API key** → copy it.

Two keys (Groq + NVIDIA, or Groq + OpenRouter) are enough to start. More providers = more free capacity.

## Part E — Test and save each key on the server

SSH into the server as `ubuntu` and download the script once:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/05-add-ai-key.sh -o 05-add-ai-key.sh
```

Then run it once per provider:

```bash
bash 05-add-ai-key.sh groq
bash 05-add-ai-key.sh nvidia
bash 05-add-ai-key.sh openrouter
bash 05-add-ai-key.sh gemini      # optional
```

For each one it:

1. asks you to paste the key, **hidden** (nothing appears while you paste: that's normal; right-click or Ctrl+Shift+V pastes in most terminals, then press Enter);
2. checks the key with the provider;
3. lists the chat models you can use, and asks one a test question, showing **how fast** it answered (usually about a second);
4. asks whether to **save** it. Answer **Y**.

Saved keys go to `~/lab/brain/.env`, a file **only your user can read** (permissions `600`). The script never prints a key, only its length and last 4 characters.

Check what's saved at any time (keys are never shown):

```bash
bash 05-add-ai-key.sh status
```

```
Keys in /home/ubuntu/lab/brain/.env:
  GROQ_API_KEY         saved (56 characters, ends in ...a1b2)
  NVIDIA_API_KEY       saved (70 characters, ends in ...c3d4)
  OPENROUTER_API_KEY   saved (73 characters, ends in ...e5f6)
  GEMINI_API_KEY       not saved
```

To **replace** a key (e.g. after deleting a leaked one), just run the script again for that provider.

Finally, **close the Notepad window without saving.**

Script source: [`scripts/05-add-ai-key.sh`](../scripts/05-add-ai-key.sh)

### Why the keys live in this file

| Place | Good? |
|---|---|
| GitHub, chats, screenshots | ❌ Never |
| Typed into each app separately | ❌ v1 of this course did that: keys ended up in one app but not the gateway, and nothing used them |
| **One private file on the server**, read by the gateway | ✅ One place to add, replace or delete a key; backed up encrypted in Lesson 07 |
| The laptop | ❌ Not needed: the laptop borrows the server's gateway (Lesson 12) |

## If something goes wrong

| Problem | Fix |
|---|---|
| `rejected the key (HTTP 401/403)` | Copy the key again from the provider, the whole thing. Paste with right-click; make sure nothing else was in the clipboard |
| `No key entered.` | The paste didn't arrive. Try right-click once, then Enter |
| `HTTP 429` | That provider's free limit is used up for now. Try later, or use another provider |
| Key works but no model answered | Models were busy or retired that minute. Fine: Lesson 06 tests every model and only uses working ones |
| OpenRouter lists no models | Only `:free` models count. If there are none, skip OpenRouter for now |
| A key leaked | Delete it on the provider's site **now**, create a new one, run the script again for that provider |

## Checklist

- [ ] At least two keys created (Groq + one more), no credit card anywhere
- [ ] Each one tested: `Key works.` and a model answered
- [ ] `bash 05-add-ai-key.sh status` shows them as saved
- [ ] Notepad with the keys closed without saving

## Check your understanding

1. Why do we collect keys from several providers instead of one?
2. What does HTTP 429 mean, and what will Jarvis do when it happens?
3. Why is Gemini's free tier for general questions only?
4. Why is a Gemini Pro subscription not the same as a Gemini API key?

## Next

**Lesson 06 — The AI gateway**: one address for all providers plus a private model, with automatic fallback.
