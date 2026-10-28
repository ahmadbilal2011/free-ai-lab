# Lesson 06 — Free cloud AI via API keys

**Goal:** add fast, powerful **free** cloud models (70B+ parameters) to your Open WebUI, next to the local model, from both laptop and phone.

**Time:** about 20–30 minutes.

**Cost:** $0. No credit card needed for the providers we use.

---

## Part A — What changes, and why

Our local `llama3.2:3b` runs on 2 CPU cores: private, unlimited, but slow and small. Cloud AI companies run much bigger models on fast hardware, and several give a **free tier**: a daily allowance of requests at no cost.

```
Open WebUI ──► Groq        (cloud, very fast, free daily limit)
           ├─► Cerebras    (cloud, very fast, free daily limit)
           ├─► (optional) GitHub Models / OpenRouter / Gemini
           └─► Ollama 3B   (local, private, unlimited, slow)
```

You pick the model per chat, from the same dropdown.

## Part B — Three new ideas

### 1. API and API key

An **API** is a way for programs to talk to a service. An **API key** is a long secret string that proves the request comes from *your* account.

> **An API key is a password.** Anyone who has it can use your quota, and on paid plans, your money. **Never** paste it into GitHub, chats (including AI chats like this one), screenshots, or emails. If a key leaks, **delete it** on the provider's site and create a new one.

### 2. "OpenAI-compatible"

Most providers copy the same request format that OpenAI made popular. That's why Open WebUI (and later LiteLLM and n8n) can talk to all of them the same way: you just change the **base URL** and the **key**.

### 3. Rate limits and HTTP 429

Free tiers have limits like *requests per minute* and *requests per day*. When you go over, the provider answers **HTTP 429 — Too Many Requests**. Nothing breaks; you wait, or switch provider. Lesson 07 (LiteLLM) will switch **automatically**.

## Part C — Which providers, and the privacy rule

Our privacy rule from the [roadmap](../docs/roadmap.md): **personal data only goes to providers that don't train on it.**

| Provider | Free tier (roughly, Sept 2026) | Trains on your prompts? | Use for |
|---|---|---|---|
| **Groq** ⭐ | ~1,000 requests/day | No | Default for everything |
| **Cerebras** ⭐ | ~1M tokens/day | No | Second choice / backup |
| GitHub Models (optional) | 150–1,000 requests/day | No | Trying well-known big models |
| OpenRouter (optional) | ~50 requests/day on free models | No* | Trying many different models |
| Google Gemini (optional) | Small daily caps on Flash models | **Yes, in Saudi Arabia** (and humans may review) | **General questions only**, nothing personal |

\*OpenRouter forwards to other companies; each free model's own provider policy applies. Check the model's page.

Limits come from [OpenRouter's comparison](https://openrouter.ai/blog/tutorials/free-llm-apis-compared/) (updated September 2026) and change often. **Always check the provider's own limits page.**

---

## Part D — Create the keys (on your laptop)

### Groq

1. Go to <https://console.groq.com> → sign in (Google or GitHub works).
2. **API Keys** → **Create API Key** → name it `free-ai-lab` → copy it.
3. Keep it somewhere safe *for the next 10 minutes only*, e.g. a password manager or a Notepad window you'll close without saving.

### Cerebras

1. Go to <https://cloud.cerebras.ai> → sign in.
2. **API Keys** → create a key named `free-ai-lab` → copy it.

## Part E — Test a key from the server (optional, recommended)

This proves the key works *before* you add it to Open WebUI, and shows the exact model names you're allowed to use. The key is typed **hidden**, used once, and **not saved**.

On the VM:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/06-test-api-key.sh -o 06-test-api-key.sh
bash 06-test-api-key.sh groq
```

You'll see `Key works.` and a list of models. Pick a big chat model from the list (on Groq, names like `llama-3.3-70b-versatile`; names change over time, so use what *your* list shows) and ask it a question:

```bash
MODEL=llama-3.3-70b-versatile bash 06-test-api-key.sh groq
```

Notice the time: usually **about a second**, compared with many seconds locally. Repeat with `cerebras`.

---

## Part F — Add the providers to Open WebUI

In Open WebUI (on `https://free-ai-lab....ts.net`), as admin:

1. **Admin Panel → Settings → Connections**.
2. Under **OpenAI API**, click **+** (Add Connection). Fill in:

   | Field | Groq | Cerebras |
   |---|---|---|
   | URL | `https://api.groq.com/openai/v1` | `https://api.cerebras.ai/v1` |
   | Key | your Groq key | your Cerebras key |
   | Prefix ID | `groq` | `cerebras` |

   **Prefix ID** puts `groq.` / `cerebras.` in front of model names, so you always know which provider answers.
3. Click **Verify connection** (the 🔄 icon) → it should succeed → **Save**.
4. Open a **New Chat** → the model dropdown now lists `groq.…` and `cerebras.…` models next to `llama3.2:3b`.
5. **Close** the Notepad window with the keys, **without saving**.

> Where is the key now? Inside Open WebUI's database, in the `open-webui` Docker volume on your server. Not on GitHub, not on your laptop. In Lesson 07 we'll move keys into a `.env` file for the LiteLLM gateway.

### Optional providers

| Provider | URL | Key from | Notes |
|---|---|---|---|
| OpenRouter | `https://openrouter.ai/api/v1` | <https://openrouter.ai/keys> | Free models end in `:free` |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | <https://aistudio.google.com/apikey> | ⚠️ **General questions only**: free-tier data is used by Google in KSA |
| GitHub Models | `https://models.github.ai/inference` | A GitHub personal access token with **Models: read** | The model list may not load automatically; add model IDs from the GitHub Models catalog in the connection's **Model IDs** field |

---

## Part G — Make it feel fast everywhere

### 1. Set a cloud model as the default

**Admin Panel → Settings → Models** → choose your favourite `groq.…` model as default (or pick per chat).

### 2. Turn the background tasks back on, using a small fast cloud model

In Lesson 04 we turned off titles, tags and follow-ups, because the local model was too slow for them. Now a small cloud model can do them quickly:

1. **Admin Panel → Settings → Interface → Task Model** → **External**: pick a *small* fast Groq model (e.g. an `8b` / `instant` model from your list).
2. Turn **Title generation** back on (tags/follow-ups too if you like) → **Save**.

Using a *small* model for these chores saves your daily free limit for real conversations.

### 3. When to use which model

| Situation | Use |
|---|---|
| Everyday questions, writing, learning, code | `groq.` / `cerebras.` big model |
| Something private or personal | Local `llama3.2:3b`, or Groq / Cerebras (they don't train on prompts) |
| Groq says "rate limit" | Switch to `cerebras.` (Lesson 07 makes this automatic) |
| No internet on the server / provider down | Local `llama3.2:3b` |

Tools (like the calendar tool from Lesson 04) stay **off** for now. Big cloud models handle tools much better, and we'll switch them on properly in the Agents lessons.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| **Verify connection** fails | Check the URL has no extra spaces and ends exactly as shown. Re-copy the key. Test it with the script in Part E. |
| Cloud models don't appear in the dropdown | Save the connection, then reload the page. Check the connection's toggle is **on**. |
| `429 Too Many Requests` | Free limit reached. Switch provider, or wait (per-minute limits reset quickly; daily limits reset once a day). |
| Answer says the model doesn't exist | Model names change. Run the Part E script to see current names. |
| You think a key leaked | Delete it on the provider's website **now**, create a new one, and update the connection. |

---

## Checklist

- [ ] Created Groq and Cerebras API keys
- [ ] Tested at least one key with `06-test-api-key.sh`
- [ ] Added both as connections with prefixes `groq` and `cerebras`
- [ ] Chatted with a cloud model from the laptop **and** the phone
- [ ] Set a small cloud **Task Model** and turned title generation back on
- [ ] Closed and discarded any copy of the keys outside the providers' sites
- [ ] Noted local vs. cloud speed in `PROGRESS.md`

## Check your understanding

1. Why is an API key treated like a password?
2. What does "OpenAI-compatible" mean, and why is it useful?
3. What does HTTP 429 mean, and what should you do when you see it?
4. Why do we avoid sending personal data to the free Gemini tier from Saudi Arabia?

## Next

**Lesson 07 — LiteLLM gateway**: one endpoint for every provider, with automatic fallback.
