# Lesson 09 — Telegram: talk to Jarvis from your phone, anywhere

**Goal:** message your own Jarvis bot on Telegram (phone or PC, home or away). It answers with the free cloud models through the gateway, remembers the conversation, and ignores everyone except you. **Nothing on the server becomes public.**

**Time:** about 20 minutes, all in the n8n web UI (no terminal).

**Cost:** $0. Telegram bots and the Bot API are free.

**Before you start:** Lesson 08 is done: n8n is healthy and the **`Jarvis brain`** credential works.

---

## Part A — Why Telegram, and why a bot

| Reason | Detail |
|---|---|
| Free | Bots and the Bot API cost nothing |
| Phone **and** PC apps | Same chat everywhere, with notifications |
| **Voice notes** built in | Lesson 10 turns them into voice commands |
| No Tailscale needed on the phone | You talk to Telegram; n8n fetches your messages from Telegram |

A **bot** is a special Telegram account made for programs; its **token** is the key n8n uses. We don't connect your *personal* account:

| | Bot ✅ | Your personal account |
|---|---|---|
| What Jarvis can see | Only messages sent **to Jarvis** | **All** your chats, contacts and groups |
| If the key leaks | Someone controls the bot; revoke the token in seconds | Someone controls **your whole account** |
| Telegram's rules | Made for this | Automating a personal account can get it limited or banned |

## Part B — Pull, not push: nothing reaches in

A bot can get messages two ways:

| | Push (webhook) | **Pull (polling)** ✅ |
|---|---|---|
| How | Telegram's servers **call your server** | **n8n asks Telegram**: "anything new for me?" |
| Needs a public door on the server | **Yes** | **No** |

```
 You ──► Telegram ◄── n8n: "anything new?" (every 10 s, waits up to 8 s)
                        │
                        ├──► brain (smart) ──► answer
                        ▼
 You ◄── Telegram ◄── n8n: "here's Jarvis's reply"
```

**Long polling** keeps it fast: every 10 seconds n8n asks *"anything new? I'll wait up to 8 seconds"*. So someone is listening 80% of the time, and if you write then, Telegram hands the message over **at once**. Typical reply: **1–4 seconds** (mostly the AI thinking); worst case about 10. The server is idle almost all the time.

> **Why not truly instant?** That needs Telegram to *push* messages to the server (a webhook), which means a public door on the server. We chose no public doors, and 1–4 seconds is close enough. A first version checked every 30 s with a 20 s wait: it left gaps of up to 10 s with nobody listening, which felt slow.

## Part C — How the workflow works

Everything happens **in the n8n UI**. You import a ready-made workflow, **Jarvis — Telegram chat**, then click each node to see what it does:

| Node | Job |
|---|---|
| **Every 10 seconds** | Starts a check |
| **Settings** | The **only node you edit**: your bot token and your Telegram user ID |
| **Ask Telegram for new messages** | Long-polls Telegram |
| **If polling failed: remove old webhook** | Polling can't work while a bot has a webhook (e.g. from an earlier setup). This removes it, so the next check works |
| **Keep only my messages** | Drops anything not from **you**. Stops quietly when there's nothing new |
| **Confirm received** | Tells Telegram "got them" **before** the AI answers, so a slow or failed answer can never cause a double reply |
| **Prepare each message** | `/start` and `/new` get a direct reply and reset memory; text gets the conversation history |
| *(voice steps)* | The template also contains the voice steps from Lesson 10. Until then, voice notes may get a text answer only; Lesson 10 explains them |
| **Direct reply?** | Commands go straight to Telegram; questions go to the brain |
| **Ask Jarvis's brain** | The gateway's `smart` alias, using your OpenAI-type credential from Lesson 08 (no key written in the workflow) |
| **Remember the answer** | Keeps the last 10 exchanges per chat, inside n8n |
| **Send reply on Telegram** | Sends the answer |

> **One honest trade-off:** n8n's built-in Telegram nodes can't do polling, so the Telegram requests are plain HTTP nodes, and they need the **bot token** in their address. It's kept in **one** place, the **Settings** node, inside n8n's database (backed up encrypted), not in any file. But: **never share, export or screenshot this workflow** while the token is in it.

## Part D — Get your bot token

You need a bot. In Telegram, open **@BotFather** (blue tick):

- **New bot:** send `/newbot`, choose a name (e.g. `Jarvis`) and a username ending in `bot`. BotFather replies with the **token**: `123456789:AAF…`.
- **Existing bot:** `/mybots` → choose it → **API Token**. If that token was ever pasted anywhere (a chat, a screenshot), choose **Revoke current token** and use the new one.

> The token **is** the bot. Anyone with it can read the bot's messages and send as it. It goes in exactly one place: the **Settings** node in n8n.

## Part E — Set it up in the n8n UI

Open n8n (`https://free-ai-lab.<your-tailnet>.ts.net:9443`).

**1. Import the workflow**

- **Overview → Create workflow**.
- Top right **⋯** menu → **Import from URL…** → paste:
  ```
  https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/stacks/jarvis/workflows/telegram-chat.json
  ```
  → **Import**. (No "Import from URL"? Open that link in your browser, select all, copy, click on the empty n8n canvas and press **Ctrl+V**.)
- **Save** (Ctrl+S).

**2. Settings node: paste your token**

- Double-click **Settings** → replace `PASTE_YOUR_BOT_TOKEN_HERE` with your token (keep the quotes `'…'`). Leave `OWNER_ID = 0` for now.

**3. Ask Jarvis's brain: pick the credential**

- Double-click **Ask Jarvis's brain** → **Credential for OpenAI** → choose your OpenAI-type credential from Lesson 08 (Base URL `http://litellm:4000/v1`). Its name doesn't matter here; `Jarvis brain` is just tidy.
- Do the same in **Listen (speech to text)** (used from Lesson 10).

**4. Publish, and find your user ID**

- **Save** → **Publish**.
- On your phone, open your bot and send `/start`. Within a few seconds Jarvis answers: *"Setup: your Telegram user ID is …"*.
- Back in n8n: **Settings** → `OWNER_ID = <that number>` (no quotes) → **Save** → **Publish** again.

From now on Jarvis answers **only you**.

**5. Tidy up**

- Close any note where you pasted the token, without saving.
- Created a **Telegram** credential in n8n earlier? It isn't used by this workflow; you can delete it (**Overview → Credentials**) so the token lives in one place only.

The template on GitHub has a placeholder, never a real token: [`stacks/jarvis/workflows/telegram-chat.json`](../stacks/jarvis/workflows/telegram-chat.json)

## Part F — Talk to Jarvis

In Telegram, write to your bot:

- `Assalam o alaikum Jarvis, what can you do?`
- a follow-up question about its answer (it remembers the conversation)
- `/new` to start fresh

It replies in the language you write in. Ask it to set a reminder and it says honestly that it can't *do* things yet: that comes in Parts 4 and 5.

Ask a friend to message your bot: they get **no answer**.

### Look inside

**Executions** lists **failed** runs only (successful ones aren't stored: this runs about 8,600 times a day). To watch one live: **Unpublish**, click **Execute workflow**, write to the bot within 8 seconds, and click through each node's data. **Publish** again afterwards.

## Useful actions (all in the n8n UI)

| Task | How |
|---|---|
| Change the token (e.g. after revoking) | **Settings** node → new token → Save → Publish |
| Pause Jarvis on Telegram | **Unpublish** |
| Talk from a different Telegram account | **Settings** → `OWNER_ID = 0` → Publish → `/start` from the new account → put its ID in → Publish |
| Change how Jarvis speaks | **Prepare each message** → edit the `system` text |
| Imported the first version (every 30 s)? | **Every 30 seconds** node → *Seconds Between Triggers* = `10`; **Ask Telegram for new messages** → query `timeout` = `8` → Save → Publish |

## If something goes wrong

| Problem | Fix |
|---|---|
| Executions: `Settings: paste your bot token…` | The token is still the placeholder, or the quotes were removed |
| No reply at all | Is the workflow **Published**? Check **Executions** for red runs, and `docker ps` on the server shows `n8n (healthy)` |
| Executions: `401 Unauthorized` from api.telegram.org | Wrong or revoked token. Copy the newest one from @BotFather into **Settings** |
| Executions: `409 Conflict` | A webhook (removed automatically on the next run) or **another program polling the same bot**. Only n8n may poll it; if it keeps happening, revoke the token and use the new one |
| Reply: "my brain didn't answer" | The gateway failed: on the server `docker ps` shows `litellm (healthy)`? Try `ask "hi"`. In n8n, is a credential selected in **Ask Jarvis's brain**? |
| "Setup: your Telegram user ID is…" keeps coming | `OWNER_ID` is still 0, or you saved without **Publish** |
| Replies arrive twice | Only one copy of this workflow may be published (check **Overview**) |
| It forgot the conversation | Memory lives in the published workflow; `/new` or re-importing resets it |

## Checklist

- [ ] Workflow imported from the URL; token in **Settings**; credential chosen in **Ask Jarvis's brain**
- [ ] Published; `/start` told me my ID; `OWNER_ID` set; published again
- [ ] Jarvis answered on my phone, remembered a follow-up, and `/new` reset it
- [ ] A message from someone else got no answer
- [ ] No note with the token left lying around

## Check your understanding

1. Why does polling need no public door on the server, while a webhook does?
2. Why are messages confirmed **before** the AI answers?
3. Where is the bot token stored, and why must this workflow never be shared or screenshotted as-is?
4. What stops a stranger from using your Jarvis?

## Next

**Lesson 10 — Voice**: send a voice note, get a spoken answer back.
