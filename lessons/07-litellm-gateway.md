# Lesson 07 — LiteLLM gateway: one endpoint, automatic fallback

**Goal:** put one "AI gateway" in front of all providers, so every app asks for simple names like `smart` and **never stops working** when a free tier runs out.

**Time:** about 20–30 minutes.

**Cost:** $0. LiteLLM is open source.

**Before you start:** Lesson 06 is done; you have at least a Groq key.

---

## Part A — The problem

After Lesson 06, Open WebUI talks to each provider separately. That has three weaknesses:

1. **When Groq hits its free limit, you must notice and switch by hand.**
2. **Keys are scattered.** Every new app (n8n, agents, a Telegram bot) would need its own copy of every key.
3. **Model names are long and change.** If Groq renames a model, every app breaks.

## Part B — The answer: a gateway

```
Open WebUI ─┐                       ┌─► Groq 70B          (1st choice)
n8n (L10) ──┼──► LiteLLM gateway ───┼─► NVIDIA 70B        (2nd)
Agents ─────┘   "give me: smart"    ├─► OpenRouter free   (3rd)
                                    └─► local Ollama 3B   (last resort, always works)
```

| Idea | Meaning |
|---|---|
| **Gateway / proxy** | One program that receives every AI request and forwards it to the right provider |
| **Model alias** | A short name *we* choose (`smart`, `fast`, `private`) that points to real provider models |
| **Fallback** | If the chosen provider fails (429 limit, error, timeout), automatically try the next one |
| **Cooldown** | A provider that just failed gets a 60-second rest, so we don't keep hitting a wall |
| **Master key** | The gateway's own password. Apps use *this* key; the real provider keys stay inside the gateway |

Our three aliases (in [`stacks/gateway/config.yaml`](../stacks/gateway/config.yaml)):

| Alias | Chain | Use for |
|---|---|---|
| `smart` | Groq 70B → NVIDIA 70B → OpenRouter free → local 3B | Normal chats, writing, code |
| `fast` | Groq 8B → NVIDIA 70B → local 3B | Chat titles, tags, quick chores |
| `private` | Local 3B only | Anything that must never leave the server |

### Why this matters for Jarvis

Every future lesson (n8n, the Telegram bot, agents) will just say "use `smart` at `http://litellm:4000/v1`". Swapping providers later means editing **one** file, not ten apps.

### Where the keys live now

`~/lab/gateway/.env` on the server, readable only by the `ubuntu` user, and listed in `.gitignore`. **Never on GitHub.** After this lesson we'll delete the keys from Open WebUI, so there's exactly one place to protect.

---

## Part C — Install (one command)

On the VM, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/07-install-gateway.sh -o 07-install-gateway.sh && bash 07-install-gateway.sh
```

It will:

1. Check the AI stack from Lesson 04 is running
2. Download the gateway files to `~/lab/gateway`
3. **Ask for your keys** (Groq, NVIDIA, OpenRouter). The keys you put in Open WebUI in Lesson 06 are **not** shared with the gateway, so paste them again here (copy them from each provider's website, or create new ones).
   - **Nothing appears while you paste.** That's normal for secrets. In PowerShell, **right-click** pastes. Press Enter after each one.
   - The script confirms each paste: `received 56 characters, ending in ...a1b2`. If it says `skipped`, the paste didn't work.
   - Press **Enter on an empty line** to skip a provider you don't have. It also creates a random **master key**
4. **Find models that work today.** The model picker ([`07-pick-models.py`](../scripts/07-pick-models.py)) asks each provider for its current model list, ranks the chat models (big ones for `smart`, small ones for `fast`), **tests** candidates with a tiny request, and writes `~/lab/gateway/config.yaml` from the ones that answered
5. Start LiteLLM and wait until it's healthy
6. **Test every alias**, then run a **fallback drill**: a special `drill` alias uses a deliberately broken key, so a backup **must** answer

Example result:

```
  smart             OK   answered by llama-3.3-70b-versatile
  fast              OK   answered by llama-3.1-8b-instant
  smart-nvidia      OK   answered by meta/llama-3.3-70b-instruct
  smart-openrouter  OK   answered by meta-llama/llama-3.3-70b-instruct:free
  private           OK   answered by private

  drill             OK   backup answered: meta/llama-3.3-70b-instruct
```

How to read the results:

| Result | Meaning |
|---|---|
| `OK` | The first choice answered |
| `FELL BACK -> answered by ollama_chat/llama3.2:3b` | The first choice failed and a backup answered. Fallback works, but fix the first choice: its key is missing/wrong, or the model was renamed (Part F) |
| `FAIL` | Nothing answered. Read the message |

> **Real first run in this lab:** every line answered from the local model, because no keys were entered: they had only been added in Open WebUI. Fallback saved the day, but the cloud was never used. The script now confirms each paste and warns when no keys are set.

---

## Part D — Try the fallback yourself

On the VM:

```bash
MASTER=$(grep LITELLM_MASTER_KEY ~/lab/gateway/.env | cut -d= -f2)
ask() { curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $MASTER" -H "Content-Type: application/json" \
  -d "{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}]}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("model"))'; }

ask smart     # normally answered by Groq
ask drill     # the 'drill' key is broken on purpose, so a BACKUP answers
unset MASTER
```

Watch it happen live in another window:

```bash
docker logs -f litellm      # Ctrl+C to stop following
```

You'll see the authentication error for `drill`, then the fallback to the next model. That's exactly what will happen when Groq says "429" on a busy day.

## Part E — Connect Open WebUI to the gateway

1. On the VM, show the master key (your own terminal, never paste it anywhere else):
   ```bash
   grep LITELLM_MASTER_KEY ~/lab/gateway/.env
   ```
2. In Open WebUI: **Admin Panel → Settings → Connections → OpenAI API → +**

   | Field | Value |
   |---|---|
   | URL | `http://litellm:4000/v1` |
   | Key | the master key (`sk-…`) |
   | Prefix ID | `lab` |

   `litellm` works as an address because both containers share the `ai_default` Docker network (the same trick as `http://ollama:11434` in Lesson 04).
3. **Verify connection** → **Save**. New models appear: `lab.smart`, `lab.fast`, `lab.private`, …
4. **Admin Panel → Settings → Models**: set **`lab.smart`** as the default model.
5. **Admin Panel → Settings → Interface → Task Model → External**: choose **`lab.fast`**.
6. **Clean up the old direct connections:** in **Connections**, delete the Groq, NVIDIA and OpenRouter connections from Lesson 06. Their keys now live only in the gateway's `.env`. One place to protect is safer than two.
7. Start a **New Chat** with `lab.smart` and test it. For anything private, choose `lab.private`.

---

## Part F — Day-to-day care

### A provider renamed or removed a model

This **will** happen. Our very first config used model names that had all been retired or renamed (Groq removed them, NVIDIA's reached "end of life", OpenRouter's stopped being free). So we never hard-code names any more. To refresh:

```bash
python3 ~/lab/gateway/pick-models.py && cd ~/lab/gateway && docker compose restart litellm
```

The picker finds and tests today's models and rewrites the config. Apps keep using `smart` / `fast` / `private`, so nothing else changes.

### Find out why something falls back

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/07-diagnose-gateway.sh -o 07-diagnose-gateway.sh && bash 07-diagnose-gateway.sh
```

It checks (without printing keys): do the keys reach the container, can it reach each provider, does each key + model work directly, and LiteLLM's own health check with the real error messages.

### Change or add a key

Run the install script again and type only the key you want to change (Enter keeps the others). If a key leaked: **delete it on the provider's site first**, then run the script with the new one.

### Useful commands

| Command | What it does |
|---|---|
| `docker logs -f litellm` | Live requests, fallbacks and errors |
| `docker stats --no-stream` | RAM used by each container (LiteLLM: a few hundred MB) |
| `cd ~/lab/gateway && docker compose pull && docker compose up -d` | Update LiteLLM |

---

## Part G — Do we still need Open WebUI? And cleaning up

**Yes, keep Open WebUI.** Each piece has a different job:

| Piece | Job | Has a chat screen? |
|---|---|---|
| **LiteLLM** | The engine room: routes requests, holds keys, falls back | ❌ No. It's for programs, not people |
| **Open WebUI** | Your chat app on phone and PC: accounts, chat history, files | ✅ Yes |
| **Telegram bot** (Lesson 11) | A second way to talk to Jarvis | ✅ Yes, inside Telegram |
| **Ollama** | Runs the private local model | ❌ No |

What *was* messy is the **duplication**: the same keys stored twice, and practice leftovers. Clean that up:

1. **In Open WebUI** (once `lab.smart` works): **Admin Panel → Settings → Connections** → delete the direct **Groq / NVIDIA / OpenRouter** connections from Lesson 06. Only these should remain: **Ollama** and **`http://litellm:4000/v1`**.
2. **On the server**, remove practice leftovers and unused images:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/cleanup-lab.sh -o cleanup-lab.sh && bash cleanup-lab.sh
   ```

   It removes the Lesson 03 `hello` stack, the `web-test` container, downloaded script copies in your home folder, and Docker images nothing uses. It **never** deletes volumes (chats, users, models), your `.env` keys, or Tailscale.

Your tidy server afterwards:

```
~/lab/
├── ai/          Ollama + Open WebUI
├── autoheal/    restarts frozen containers
└── gateway/     LiteLLM + your keys (.env)
```

---

## If something goes wrong

| Problem | Fix |
|---|---|
| `The AI stack isn't running` | `cd ~/lab/ai && docker compose up -d`, then run the script again |
| LiteLLM never becomes healthy | `docker logs --tail 50 litellm`. A typo in `config.yaml` is the usual cause; download it again from the repo |
| `exec format error` | The image has no Arm build. Send the error; we'll pick another tag |
| Every line says `FAIL ... AuthenticationError` | A key is wrong or was revoked. Run the script again and paste it carefully |
| `FELL BACK` / `model not found` / `410 Gone` / `unavailable for free` | The provider renamed, retired or stopped offering the model for free. Re-run the picker (Part F) |
| Open WebUI can't verify `http://litellm:4000/v1` | Check `docker network inspect ai_default` lists both `open-webui` and `litellm`. Check the key is the **master** key |

---

## Checklist

- [ ] Ran `07-install-gateway.sh`; `smart`, `fast` and `private` say **OK**
- [ ] The fallback drill was answered by a backup model
- [ ] Added `http://litellm:4000/v1` to Open WebUI with prefix `lab`
- [ ] Default model = `lab.smart`, Task Model = `lab.fast`
- [ ] Deleted the old direct provider connections from Open WebUI
- [ ] Ran `cleanup-lab.sh`
- [ ] Wrote which providers answered and how fast in `PROGRESS.md`

## Check your understanding

1. What is a model alias, and why does it protect your apps from provider changes?
2. Describe what happens, step by step, when Groq answers "429" to a `smart` request.
3. Why do apps get the *master key* instead of the real provider keys?
4. Why is `private` never allowed to fall back to a cloud provider?

## Next

**Lesson 08 — Backups and monitoring**: protect chats, settings and keys before Jarvis gets more of your data.
