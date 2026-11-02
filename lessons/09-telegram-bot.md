# Lesson 09 — Telegram: talk to Jarvis from your phone, anywhere

**Goal:** message your own Jarvis bot on Telegram (phone or PC, home or away). It answers with the free cloud models through the gateway, remembers the conversation, and ignores everyone except you. **Nothing on the server becomes public.**

**Time:** about 20 minutes.

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
 You ──► Telegram ◄── n8n: "anything new?" (every 30 s, waits up to 20 s)
                        │
                        ├──► brain (smart) ──► answer
                        ▼
 You ◄── Telegram ◄── n8n: "here's Jarvis's reply"
```

**Long polling** keeps it fast: n8n asks *"anything new? I'll wait up to 20 seconds"*. If you write during those seconds, Telegram answers **at once**. So replies usually take a few seconds, sometimes up to ~10, and the server is idle almost all the time.

## Part C — How the workflow works

The installer imports a ready-made workflow, **Jarvis — Telegram chat**, into n8n. Open it after installing and click each node to see what it does:

| Node | Job |
|---|---|
| **Every 30 seconds** | Starts a check |
| **Ask Telegram for new messages** | Long-polls Telegram |
| **Keep only my messages** | Drops anything not from **your** user ID (strangers, groups). Stops quietly when there's nothing new |
| **Confirm received** | Tells Telegram "got them" **before** the AI answers, so a slow or failed answer can never cause a double reply |
| **Prepare each message** | `/start` and `/new` get a direct reply and reset memory; voice notes get "coming in Lesson 10"; text gets the conversation history |
| **Direct reply?** | Commands go straight to Telegram; questions go to the brain |
| **Ask Jarvis's brain** | The gateway's `smart` alias, using the **Jarvis brain** credential (no key written in the workflow) |
| **Remember the answer** | Keeps the last 10 exchanges per chat, inside n8n |
| **Send reply on Telegram** | Sends the answer |

> **One honest trade-off:** n8n's built-in Telegram nodes can't do polling, so the two Telegram requests use plain HTTP nodes, and the **bot token is part of their address**. It sits inside n8n's database (backed up encrypted), not in any file. But it means: **never share or export this workflow** without removing the token, and never paste screenshots of those nodes' URLs.

## Part D — Get your bot token

You need a bot. In Telegram, open **@BotFather** (blue tick):

- **New bot:** send `/newbot`, choose a name (e.g. `Jarvis`) and a username ending in `bot` (e.g. `ahmad_jarvis_bot`). BotFather replies with the **token**: `123456789:AAF…`.
- **Bot from the first version of the course:** send `/mybots` → choose it → **API Token**. If that token was ever pasted anywhere (a chat, a screenshot), choose **Revoke current token** and use the new one.

Keep the token in Notepad for a few minutes; you'll close it without saving.

> The token **is** the bot. Anyone with it can read the bot's messages and send as it. Never put it on GitHub or in a chat, including AI chats.

## Part E — Install (one command)

On the server, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-telegram.sh -o 09-install-telegram.sh && bash 09-install-telegram.sh
```

1. It checks n8n and finds your **Jarvis brain** credential.
2. You paste the token (hidden). It checks it with Telegram and shows the bot's name.
3. It removes any old webhook, so the bot is in polling mode.
4. **It finds your user ID:** open the link it shows on your phone and send `/start`. It shows your name and ID; confirm with **Enter**. (Saved in `~/lab/jarvis/.env`: an ID isn't secret.)
5. It imports the workflow into n8n, **publishes** it and restarts n8n.

Then close Notepad **without saving**.

Sources: [`scripts/09-install-telegram.sh`](../scripts/09-install-telegram.sh), [`stacks/jarvis/workflows/telegram-chat.json`](../stacks/jarvis/workflows/telegram-chat.json) (the template has placeholders instead of the token)

## Part F — Talk to Jarvis

In Telegram, write to your bot:

- `Assalam o alaikum Jarvis, what can you do?`
- a follow-up question about its answer (it remembers the conversation)
- `/new` to start fresh

It replies in the language you write in. Ask it to set a reminder and it will say honestly that it can't *do* things yet: that comes in Parts 4 and 5.

Ask a friend to message your bot: they get **no answer**. Only your user ID is allowed.

### Look inside

In n8n → **Workflows → Jarvis — Telegram chat**: the canvas shows the flow. **Executions** lists **failed** runs only (successful ones aren't stored, because this runs about 2,900 times a day). To watch one live: unpublish it, click **Execute workflow**, write to the bot within 20 seconds, and click through each node's data. **Publish** it again afterwards.

## Useful commands

| Task | How |
|---|---|
| Change the token (e.g. after revoking) | Run `bash 09-install-telegram.sh` again |
| Pause Jarvis on Telegram | n8n → the workflow → **Unpublish** |
| Send your messages to a new account | `OWNER_ID= bash 09-install-telegram.sh` and send `/start` from the new account |

## If something goes wrong

| Problem | Fix |
|---|---|
| `No OpenAI-type credential named exactly 'Jarvis brain'` | Create it (Lesson 08, Part D), named exactly `Jarvis brain` |
| `Telegram rejected the token` | Copy it again from @BotFather → `/mybots` → API Token. If revoked, use the newest one |
| `No message arrived` | Send `/start` to the bot (open the link the script shows), then run again |
| No reply at all | n8n → the workflow: is it **Published**? Then **Executions** for red runs. `docker logs --tail 50 n8n` |
| Executions show `409 Conflict` | Two programs are polling the same bot (e.g. an old setup somewhere). Only n8n may poll. Revoke the token in @BotFather and run the script with the new one |
| Reply: "my brain didn't answer" | The gateway failed: `docker ps` should show `litellm (healthy)`; try `ask "hi"` on the server |
| Replies arrive twice | Shouldn't happen (messages are confirmed first). If it does, check that only one copy of the workflow is published |
| It forgot the conversation | Memory lives in the published workflow; re-importing or `/new` resets it |

## Checklist

- [ ] Bot token from @BotFather (revoked and replaced if it was ever pasted somewhere)
- [ ] `09-install-telegram.sh` finished; the workflow is **Published** in n8n
- [ ] Jarvis answered on my phone, remembered a follow-up, and `/new` reset it
- [ ] A message from someone else got no answer
- [ ] Notepad with the token closed without saving

## Check your understanding

1. Why does polling need no public door on the server, while a webhook does?
2. Why are messages confirmed **before** the AI answers?
3. Where is the bot token stored, and why must this workflow never be shared as-is?
4. What stops a stranger from using your Jarvis?

## Next

**Lesson 10 — Voice**: send a voice note, get a spoken answer back.
