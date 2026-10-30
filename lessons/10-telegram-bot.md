# Lesson 10 — Telegram bot: text Jarvis from anywhere

**Goal:** message your own Jarvis bot on Telegram, from your phone or PC, anywhere. It answers with your free cloud models and remembers the conversation. **Everything is built in the n8n web UI, and nothing on the server is public.**

**Time:** about 30–40 minutes.

**Cost:** $0. Telegram bots and the Bot API are free.

**Before you start:** Lesson 09 is done: n8n is healthy and the `Lab gateway` credential works.

---

## Part A — Why Telegram?

| Reason | Detail |
|---|---|
| Free | Bots and the Bot API cost nothing |
| Phone **and** PC apps | Same chat everywhere, with notifications |
| **Voice notes** built in | Lesson 11 turns them into voice commands |
| Works without Tailscale on your phone | You talk to Telegram; n8n fetches your messages from Telegram |

## Part B — Push or pull? Our rule: n8n reaches out, nothing reaches in

There are two ways a bot can get your messages:

| | **Push (webhook)** | **Pull (getUpdates)** ✅ our choice |
|---|---|---|
| How | Telegram's servers **call your server** | **n8n asks Telegram**: "anything new for me?" |
| Needs a public address on your server | **Yes** | **No** |
| Configured in | Server networking + n8n | **n8n UI only** |
| Speed | Instant | Near-instant (see "long polling" below) |

The pull design fits the whole lab: **n8n talks *out* to everything it needs** (Telegram, the AI gateway, and later Google and other cloud tools), and **nothing on the internet can talk *in***.

```
                 ┌──────────── your server (private, no public ports) ────────────┐
 You ──► Telegram ◄── n8n: "any new messages?" ──► AI gateway (smart) ──┐          │
            ▲                                                           │          │
            └──────────── n8n: "here is Jarvis's reply" ◄───────────────┘          │
                 └────────────────────────────────────────────────────────────────┘
```

### Long polling: why it's still fast

n8n doesn't just ask once and hang up. It asks: *"anything new? I'll wait up to 20 seconds."* If you send a message during those 20 seconds, Telegram answers **immediately**. Every 30 seconds n8n starts a new wait. So replies feel near-instant, and the server is idle almost all the time: it's mostly just waiting.

### Honest trade-offs

| Trade-off | How we handle it |
|---|---|
| ~3,000 small "anything new?" runs a day | Mostly waiting; tiny CPU. We tell n8n **not to save** successful runs, so the disk doesn't fill |
| A message must be **confirmed** to Telegram, or it comes back again | The workflow confirms each batch *before* asking the AI, so you never get double replies |
| n8n's built-in Telegram **trigger** only supports push | We build the pull loop from standard nodes: Schedule, HTTP Request, If, Code. Good practice for later lessons |
| The bot token sits in the URL of two HTTP nodes (not in an encrypted credential) | It stays on your server and in your encrypted backups. **Never export or share this workflow without removing the token** |

### Security: who can command Jarvis?

Anyone can find a Telegram bot by name and message it. Our workflow **ignores every message that isn't from your Telegram user ID**, so strangers simply get no reply.

---

## Part C — Make sure nothing is public (one command)

An earlier version of this lesson opened a public "webhook door" with Tailscale Funnel. We withdrew that design. This script removes any public door, moves the n8n editor to its final private address `:9443`, and restarts n8n. It's safe to run even if you never ran the old script:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/10-close-public-door.sh -o 10-close-public-door.sh && bash 10-close-public-door.sh
```

It should say **"No Funnel: nothing on this server is reachable from the internet."** Your n8n editor is now at **`https://…ts.net:9443`** (Tailscale only). Your credentials and workflows are kept.

---

## Part D — Create your bot (phone, 2 minutes)

1. In Telegram, open **@BotFather** (blue checkmark).
2. Send `/newbot`, choose a name (e.g. `My Jarvis`) and a username ending in `bot`.
3. BotFather gives you a **token** like `123456789:AA…`. **It's a password**: whoever has it controls your bot. Paste it only into n8n.
4. Send your new bot one message: `hello`. (We'll use it to find your user ID.)

---

## Part E — Build the "Jarvis chat" workflow in n8n

Open the editor at `https://…ts.net:9443` → **Create workflow** → name it **`Jarvis chat`**.

```
[Every 30s] → [Ask Telegram] → [Got messages?] → [Confirm] → [Keep my messages] → [AI Agent] → [Send reply]
                                                                                       ├ OpenAI Chat Model (Lab gateway, smart)
                                                                                       └ Simple Memory
```

### 0. A Telegram credential (for sending replies)

**Credentials → Create → Telegram API** → paste the BotFather token → **Save** as `Jarvis bot`. The green "Connection tested successfully" proves the token works.

### 1. Trigger: Every 30 seconds

**Add first step → On a schedule** → **Trigger Interval:** Seconds → **Seconds Between Triggers:** `30`.

### 2. HTTP Request: "Ask Telegram"

Add **HTTP Request**, rename it **`Ask Telegram`**:

| Field | Value |
|---|---|
| Method | `GET` |
| URL | `https://api.telegram.org/bot<YOUR-TOKEN>/getUpdates` (replace `<YOUR-TOKEN>`; keep the word `bot` in front) |
| Send Query Parameters | on |
| → `timeout` | `20` (the long-poll wait, in seconds) |
| → `allowed_updates` | `["message"]` |
| Options → Timeout | `30000` (ms; a little longer than the long poll) |
| Settings (⚙ tab) → On Error | **Continue** (a rare network hiccup shouldn't stop Jarvis) |

**Find your user ID now:** click **Execute step**. In the output, open `result` → `0` → `message` → `from` → **`id`**. That number is your Telegram user ID. Write it down.

> If the output says `Conflict: can't use getUpdates method while webhook is active`, the bot still has a webhook from the old design. Change the URL's last word from `getUpdates` to `deleteWebhook`, execute once, then change it back.

### 3. If: "Got messages?"

Add **If**, rename it **`Got messages?`**. Condition (switch the value to *expression*):

- **Value 1:** `{{ ($json.result ?? []).length }}` → **Number** → **is greater than** → **Value 2:** `0`

Continue from the **true** output only.

### 4. HTTP Request: "Confirm"

Add **HTTP Request** on the *true* branch, rename it **`Confirm`**. This tells Telegram "I've got these", so they're never delivered twice:

| Field | Value |
|---|---|
| Method | `GET` |
| URL | the same `https://api.telegram.org/bot<YOUR-TOKEN>/getUpdates` |
| → `offset` | `{{ $json.result.at(-1).update_id + 1 }}` |
| → `timeout` | `0` |
| → `limit` | `1` |
| Settings → On Error | **Continue** |

### 5. Code: "Keep my messages"

Add **Code** (JavaScript), rename it **`Keep my messages`**, mode **Run Once for All Items**, and paste:

```js
// Only messages from ME, and only text (voice comes in Lesson 11).
const MY_ID = 123456789;   // ← replace with YOUR Telegram user ID from step 2

const updates = $('Ask Telegram').first().json.result ?? [];
return updates
  .filter(u => u.message && u.message.from && u.message.from.id === MY_ID && u.message.text)
  .map(u => ({ json: { chatId: u.message.chat.id, text: u.message.text } }));
```

Messages from anyone else are dropped right here.

### 6. AI Agent (the brain)

Add **AI Agent**:

- **Source for Prompt:** *Define below* → `{{ $json.text }}`
- **Options → System Message:**

  ```
  You are Jarvis, Ahmad's personal assistant.
  Be helpful, concise and friendly. Reply in the same language the user writes in
  (English, Urdu or Arabic). Keep answers short enough to read on a phone,
  unless asked for detail. Never invent facts; say when you're not sure.
  ```

- **Chat Model** connector → **OpenAI Chat Model** → credential **`Lab gateway`** → model **`smart`**
- **Memory** connector → **Simple Memory** → **Session ID:** *Define below* → `{{ $('Keep my messages').item.json.chatId }}` → **Context Window Length:** `10`

### 7. Telegram: "Send reply"

Add **Telegram → Send a text message**:

- **Credential:** `Jarvis bot`
- **Chat ID:** `{{ $('Keep my messages').item.json.chatId }}`
- **Text:** `{{ $json.output }}`
- **Additional Fields → Append n8n Attribution:** off

### 8. Settings, test, activate

1. **Workflow settings** (⋯ menu → **Settings**): **Save successful production executions:** *Do not save*. Keep saving **failed** ones so you can debug.
2. Send your bot a message, then click **Execute workflow**. The reply should arrive in Telegram 🎉
3. **Save** and switch the workflow to **Active**.

From now on Jarvis checks Telegram every 30 seconds, 24/7, even when the editor is closed. Try:

```
My name is Ahmad and I work in DevOps.
What's my name and job?                 ← memory test
Explain Docker volumes in 3 lines.
مجھے لینکس سیکھنے کے تین مشورے دو         ← language test
```

---

## Part F — Prove it's private

On your phone with **Tailscale OFF** (mobile data):

| Try | Expected |
|---|---|
| Message your bot on Telegram | ✅ Jarvis answers |
| Open `https://…ts.net:9443` (n8n editor) | ❌ doesn't load |
| Open `https://…ts.net` (Open WebUI) | ❌ doesn't load |

On the VM, `tailscale funnel status` should show **no Funnel**. Ask a friend to message your bot: **no reply**.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| `Unauthorized` / 401 in **Ask Telegram** | The token in the URL is wrong. Check the word `bot` is directly in front of the token, with no space |
| `Conflict: can't use getUpdates method while webhook is active` | Call `deleteWebhook` once (step 2 note) |
| `Conflict: terminated by other getUpdates request` once in a while | Two runs overlapped (a slow AI reply). Harmless: *On Error → Continue* handles it |
| Same message answered twice | The **Confirm** step must run *before* the AI Agent, and its `offset` must be `update_id + 1` |
| No reply, and the If goes to *false* | No new messages, or the token belongs to a different bot |
| Reply never comes, but **Keep my messages** outputs nothing | `MY_ID` doesn't match your `message.from.id` (a number, no quotes) |
| Voice notes or stickers are ignored | Expected for now. Voice is Lesson 11 |
| Slow answers | Check the gateway: `bash 07-diagnose-gateway.sh` |

---

## Checklist

- [ ] Ran `10-close-public-door.sh`: **no Funnel**; editor on `:9443`
- [ ] Created the bot; token only in n8n
- [ ] Built `Jarvis chat`: Schedule → Ask → If → Confirm → Keep my messages → AI Agent → Send reply
- [ ] `MY_ID` set to my own user ID
- [ ] Successful runs not saved; workflow **Active**
- [ ] Memory and language tests passed
- [ ] With Tailscale off: bot answers, editor and Open WebUI don't load
- [ ] Wrote today's notes in `PROGRESS.md` (no token, no user ID)

## Check your understanding

1. What's the difference between push (webhook) and pull (getUpdates), and why does pull need no public address?
2. How does long polling make replies near-instant while keeping the server idle?
3. Why must the **Confirm** step run before the AI Agent?
4. What stops a stranger from using your Jarvis?

## Next

**Lesson 11 — Voice in, voice out**: send Jarvis a voice note and get a spoken answer back.
