# Lesson 06 — The AI gateway: one address, free models, automatic fallback

**Goal:** give Jarvis one **brain address** on the server. Every part of Jarvis (n8n, the voice service, the laptop) asks it for simple names like `smart`, and it keeps answering even when a free provider runs out, by falling back to the next one and finally to a **private model** running on the server itself.

**Time:** about 20 minutes (mostly downloads).

**Cost:** $0. LiteLLM and Ollama are open source.

**Before you start:** Lesson 05 is done: `bash 05-add-ai-key.sh status` shows at least one saved key.

---

## Part A — Why a gateway

Without one, every app would need every key and the exact model names, and when Groq hit its daily limit, Jarvis would just stop. With a gateway:

```
 n8n (L08) ──┐                          ┌─► Groq          (1st choice, fastest)
 voice (L10) ┼──► gateway (LiteLLM) ────┼─► NVIDIA        (2nd)
 laptop (L12)┘    "give me: smart"      ├─► OpenRouter    (3rd)
                                        └─► private model (last resort, on the server)
```

| Idea | Meaning |
|---|---|
| **Alias** | A short name *we* choose (`smart`, `fast`, `private`) that points to real provider models |
| **Fallback** | If the chosen provider fails (limit reached, error, timeout), the next one answers automatically |
| **Cooldown** | A provider that just failed rests for 60 seconds instead of being hammered |
| **Master key** | The gateway's own password. Apps use *this* key; the real provider keys never leave the server |

## Part B — Jarvis's aliases

| Alias | Chain | Jarvis uses it for |
|---|---|---|
| `smart` | best free cloud model → backups → private | Conversations, writing, planning |
| `fast` | small fast cloud model → backups → private | Quick chores (titles, yes/no decisions, routing) |
| `private` | the server's own model **only** | Anything that must never leave the server |
| `general` *(if you saved a Gemini key)* | Gemini → smart chain | General questions with nothing personal in them |

> **Why `private` never falls back to the cloud:** it's the promise "this stays on my server". Slower, but kept.

## Part C — Why the model names are chosen by a script

In the first version of this course, **every** model name written by hand stopped working within weeks: Groq removed some, NVIDIA's reached end-of-life, OpenRouter's stopped being free. So the installer runs a **model picker**: it asks each provider for today's models, tests the best candidates with a tiny request, and writes the gateway's config with names that really answered. Apps only ever see `smart` / `fast` / `private`, so provider changes never reach them.

## Part D — The private model on the server

**Ollama** runs one small open model (default `llama3.2:3b`) on the server's 2 CPUs: slow (seconds per answer), but private and unlimited. It's kept loaded in memory all the time, which also keeps the server clear of Oracle's idle-reclaim rule (memory stays above 20%).

## Part E — Install (one command)

On the server, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/06-install-brain.sh -o 06-install-brain.sh && bash 06-install-brain.sh
```

It takes 5–15 minutes the first time. What you'll see:

1. Your saved keys (only their last 4 characters).
2. autoheal starting.
3. Ollama starting, the private model downloading (~2 GB) and answering a first question (slow the first time: it loads into memory).
4. The **model picker** testing each provider's models: `test … OK` / `no`.
5. The gateway starting, then a test of each alias and the **fallback drill**:

```
  smart     OK   answered by openai/gpt-oss-120b
  fast      OK   answered by openai/gpt-oss-20b
  private   OK   answered by llama3.2:3b
  drill     OK   the broken first choice was skipped; a backup answered: ...
```

The **drill** alias uses a deliberately broken key, so its first choice always fails. A backup answering proves fallback works.

Sources: [`scripts/06-install-brain.sh`](../scripts/06-install-brain.sh), [`scripts/06-pick-models.py`](../scripts/06-pick-models.py), [`stacks/brain/compose.yaml`](../stacks/brain/compose.yaml)

## Part F — Talk to Jarvis's brain

The installer adds an `ask` command. Open a **new** SSH session (so it's found), then:

```bash
ask "Plan a 30-minute evening walk routine for me"
ask -m fast "Is this a question about my calendar? Answer yes or no: what's on tomorrow?"
ask -m private "Summarise: my salary is due on the 27th"
```

Each answer ends with **which model** answered and how long it took. Try the same question with `smart` and `private` and compare speed and quality: that's why Jarvis thinks with free cloud models and keeps the private one as a backup.

## Part G — Where things are now

```
~/lab/
├── autoheal/        restarts frozen containers
└── brain/
    ├── .env         your provider keys + gateway master key + private model name (only you can read it)
    ├── compose.yaml Ollama + LiteLLM
    ├── config.yaml  generated by the picker: which real models sit behind each alias
    └── pick-models.py
```

| Address | Who uses it |
|---|---|
| `http://127.0.0.1:4000/v1` | Commands on the server (`ask`, tests) |
| `http://litellm:4000/v1` | Other containers on the `jarvis` network (n8n, voice) |
| Through Tailscale | The laptop, from Lesson 12 (not published yet) |

## Maintenance

| Task | Command |
|---|---|
| A provider renamed or retired models (`FELL BACK` / `FAIL` everywhere) | `python3 ~/lab/brain/pick-models.py && cd ~/lab/brain && docker compose restart litellm` |
| Added or replaced a key (Lesson 05 script) | `bash 06-install-brain.sh` again |
| See live requests and fallbacks | `docker logs -f litellm` |
| Memory used by each app | `docker stats --no-stream` |
| Update the apps | `cd ~/lab/brain && docker compose pull && docker compose up -d` |

## If something goes wrong

| Problem | Fix |
|---|---|
| `No saved keys found` | Do Lesson 05 first: `bash 05-add-ai-key.sh groq` |
| `Docker isn't usable without sudo` | Log out and back in (Lesson 03) |
| The gateway never becomes healthy | `docker logs --tail 50 litellm`. Usually a broken `config.yaml`: re-run the picker (Maintenance) |
| Every line says `FAIL ... AuthenticationError` | A key is wrong or was deleted. Replace it with Lesson 05's script, then re-run this one |
| One alias says `FELL BACK` | That provider failed right now (limit, busy). Fine if rare; if it repeats, re-run the picker |
| `private` is very slow or times out | Normal on the first question (loading into memory). If always slow, try a smaller model: `PRIVATE_MODEL=llama3.2:1b bash 06-install-brain.sh` |
| `ask: command not found` | Open a new SSH session, or run `~/.local/bin/ask "…"` |
| `exec format error` | An image has no Arm build. Send the error |

## Checklist

- [ ] `06-install-brain.sh` finished; `smart`, `fast` and `private` say **OK**
- [ ] The fallback drill was answered by a backup
- [ ] `ask` works, and I compared `smart` with `-m private`
- [ ] `docker ps` shows `ollama`, `litellm` and `autoheal` healthy / running

## Check your understanding

1. What is an alias, and why does it protect Jarvis from provider changes?
2. Step by step: what happens when Groq answers "429" to a `smart` request?
3. Why do apps get the gateway's master key instead of the provider keys?
4. Why does the private model stay loaded in memory all the time?

## Next

**Lesson 07 — Backups and monitoring**: protect the keys and, soon, Jarvis's workflows, before Jarvis gets your data.
