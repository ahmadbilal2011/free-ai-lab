# Lesson 10 — Telegram bot: text Jarvis from anywhere

**Goal:** message your own Jarvis bot on Telegram, from your phone or PC, anywhere in the world. It answers with your free cloud models and remembers the conversation.

**Time:** about 30–40 minutes.

**Cost:** $0. Telegram bots and the Bot API are free.

**Before you start:** Lesson 09 is done: n8n is healthy and the `Lab gateway` credential works.

---

## Part A — Why Telegram?

| Reason | Detail |
|---|---|
| Free, no limits that matter for one person | Bots and the Bot API cost nothing |
| Phone **and** PC apps | Same chat everywhere, with notifications |
| **Voice notes** built in | Lesson 11 turns them into Jarvis voice commands |
| Official n8n nodes | Telegram Trigger + Telegram actions, no code |
| Works without Tailscale on your phone | The bot is reached through Telegram's servers |

## Part B — The one hard problem: Telegram must reach your server

So far **nothing** on the server is public. But Telegram delivers messages with a **webhook**: Telegram's servers make an HTTPS request to a URL on *your* server. If they can't reach it, your bot never hears you.

The options:

| Option | Verdict |
|---|---|
| Open n8n to the internet | ❌ The editor (which holds all your keys and workflows) becomes a public login page |
| Ask Telegram for messages every few seconds ("polling") | ⚠️ n8n's Telegram Trigger only supports webhooks; polling by hand wastes resources and adds delay |
| **Tailscale Funnel, for the webhook paths only** | ✅ One narrow, public door. Everything else stays private |

### How the narrow door works

**Tailscale Funnel** is the public sibling of `tailscale serve` (Lesson 05). We use it on **one extra port (10000)**, and only for the paths `/webhook/…` and `/webhook-test/…`:

```
INTERNET (Telegram) ──► https://free-ai-lab.<tailnet>.ts.net:10000/webhook/…  ──► n8n webhook  ✅ public
                        https://free-ai-lab.<tailnet>.ts.net:10000/            ──► 404          ✅ nothing there

TAILSCALE ONLY      ──► https://free-ai-lab.<tailnet>.ts.net:8443   ──► n8n editor   🔒 private (unchanged)
                        https://free-ai-lab.<tailnet>.ts.net        ──► Open WebUI   🔒 private (unchanged)
```

### Four layers of protection on that door

| Layer | What it stops |
|---|---|
| 1. **Only `/webhook…` paths** are public | Nobody can reach the editor, Open WebUI, the gateway or SSH through it |
| 2. **Random webhook IDs** | Each n8n webhook URL contains a long random ID; unknown paths just get 404 |
| 3. **Telegram secret token** | n8n's Telegram Trigger gives Telegram a secret when it registers the webhook, and **rejects any request without it** (HTTP 403) |
| 4. **Restrict to *your* user ID** | Even if someone finds your bot in Telegram and messages it, the trigger **drops** their messages |

Also: Oracle's firewall is unchanged. Funnel traffic arrives through the same outbound Tailscale connection, so **no Oracle port is opened**.

> **Defence in depth** again: any single layer could fail, but all four would have to fail together.

---

## Part C — Create your bot and open the door

### 1. Create the bot (on your phone, 2 minutes)

1. In Telegram, open **@BotFather** (blue checkmark: it's Telegram's official bot).
2. Send `/newbot`.
3. Name: e.g. `My Jarvis`. Username: must end in `bot`, e.g. `ahmad_jarvis_bot`.
4. BotFather replies with a **token** like `123456789:AA…`. **It's a password**: whoever has it controls your bot. Don't paste it in chats, screenshots or GitHub. You'll paste it only into n8n.
5. Optional: `/setdescription` and `/setuserpic` to make it look nice.

### 2. Open the webhook door (on the VM)

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/10-telegram-webhook.sh -o 10-telegram-webhook.sh && bash 10-telegram-webhook.sh
```

- First time only: Tailscale may print a link saying **Funnel isn't enabled** for your tailnet. Open it, click **Enable**, and run the script again.
- It publishes **only** the webhook paths on port 10000, tells n8n its public webhook address, restarts n8n, and checks both doors:

```
  https://…ts.net:10000/webhook/...   HTTP 404  (404 from n8n = the door works; no such workflow)
  https://…ts.net:10000/              HTTP 404  (404 = good: the editor is NOT exposed here)
```

---

## Part D — Build the "Jarvis chat" workflow in n8n

Open the n8n editor (`https://…ts.net:8443`) → **Create workflow** → name it **`Jarvis chat`**.

```
[Telegram Trigger] ──► [AI Agent] ──► [Telegram: Send message]
                          ├─ Chat Model: OpenAI Chat Model (Lab gateway, smart)
                          └─ Memory: Simple Memory (per chat)
```

### 1. Telegram Trigger

1. **Add first step** → search **Telegram** → **On message**.
2. **Credential** → **Create new** → paste the **BotFather token** → **Save**. Name it `Jarvis bot`.
3. **Trigger On:** `Message`.

### 2. Find your own Telegram user ID

1. Click **Listen for test event** on the trigger.
2. On your phone, send your bot: `hello`.
3. In n8n, the trigger output shows the message. Find **`message.from.id`** (a number like `123456789`). That's **your user ID**. Note it.
4. Back in the trigger: **Add field** (Additional Fields) → **Restrict to User IDs** → paste your ID.

From now on, messages from anyone else are silently dropped.

### 3. AI Agent (the brain)

1. Click **+** after the trigger → **AI Agent**.
2. **Source for Prompt:** *Define below* → **Prompt:** `{{ $json.message.text }}`
3. **Options → Add option → System Message:**

   ```
   You are Jarvis, Ahmad's personal assistant.
   Be helpful, concise and friendly. Reply in the same language the user writes in
   (English, Urdu or Arabic). Keep answers short enough to read on a phone,
   unless asked for detail. Never invent facts; say when you're not sure.
   ```

4. **Chat Model** connector → **OpenAI Chat Model** → Credential **`Lab gateway`** → Model **`smart`**.
5. **Memory** connector → **Simple Memory**:
   - **Session ID:** *Define below* → `{{ $('Telegram Trigger').item.json.message.chat.id }}`
   - **Context Window Length:** `10` (remembers the last 10 messages; more costs more free-tier tokens)

### 4. Send the reply

1. Click **+** after the AI Agent → **Telegram** → **Send a text message**.
2. **Credential:** `Jarvis bot`.
3. **Chat ID:** `{{ $('Telegram Trigger').item.json.message.chat.id }}`
4. **Text:** `{{ $json.output }}`
5. **Additional Fields → Append n8n Attribution:** off.

### 5. Test, then switch it on

1. Click **Execute workflow** (test mode), then message your bot: `What can you do?`
2. If the reply arrives in Telegram 🎉, **Save** and switch the workflow to **Active** (top right).

**Active** registers the *production* webhook with Telegram. From now on Jarvis answers 24/7, even when the n8n editor is closed.

Try:

```
My name is Ahmad and I work in DevOps.
What's my name and job?          ← memory test
Explain Docker volumes in 3 lines.
مجھے لینکس سیکھنے کے تین مشورے دو    ← language test
```

---

## Part E — Check the door is narrow (do this once)

On your phone, **turn Tailscale OFF** and use mobile data:

| Open this | Expected |
|---|---|
| Telegram → message your bot | ✅ Jarvis answers (Telegram reaches the public webhook) |
| `https://…ts.net:8443` (n8n editor) | ❌ doesn't load: private |
| `https://…ts.net` (Open WebUI) | ❌ doesn't load: private |
| `https://…ts.net:10000/` | ❌ 404: nothing there |

Then ask a friend to message your bot: **no reply**, because of the user ID restriction.

---

## Useful commands

| Command | What it does |
|---|---|
| `tailscale funnel status` | Shows exactly what is public |
| `bash 10-telegram-webhook.sh --off` | Close the door (bot stops receiving) |
| `bash 10-telegram-webhook.sh` | Open it again |
| n8n → **Executions** | Every message Jarvis handled, step by step |

## If something goes wrong

| Problem | Fix |
|---|---|
| "Funnel is not enabled" | Open the link the script prints, click **Enable**, run the script again |
| Test listen never receives the message | Did you run the script **after** n8n was installed? Check `grep WEBHOOK_URL ~/lab/jarvis/.env` shows `:10000` and `tailscale funnel status` lists `/webhook-test` |
| Works in test, not when Active | Save, switch **Active** off and on again (this re-registers the webhook with Telegram) |
| `Provided secret is not valid` in executions | Another tool or an old workflow registered the same bot. Use one active Telegram trigger per bot; toggle the workflow off and on |
| Bot ignores you | Check **Restrict to User IDs** contains *your* `message.from.id`, not the chat ID of a group |
| Reply says "Bad Request: message text is empty" | You sent a voice note or a sticker. Voice comes in Lesson 11 |
| Slow or no answer | Check the gateway: `bash 07-diagnose-gateway.sh` |

---

## Checklist

- [ ] Created the bot with @BotFather; token only in n8n
- [ ] Ran `10-telegram-webhook.sh`; both checks show 404
- [ ] Built `Jarvis chat`: Telegram Trigger → AI Agent (smart + memory) → Send message
- [ ] Restricted the trigger to my user ID
- [ ] Workflow is **Active**; Jarvis answers with Tailscale off
- [ ] Memory test passed; language test passed
- [ ] Editor and Open WebUI do **not** load with Tailscale off
- [ ] Wrote today's notes in `PROGRESS.md` (no token, no user ID)

## Check your understanding

1. Why can't Telegram reach n8n without Funnel, and why not just open n8n to the internet?
2. Name the four protection layers on the webhook door.
3. What does the Simple Memory **Session ID** do, and why use the chat ID?
4. What's the difference between *test* mode and *Active* in n8n?

## Next

**Lesson 11 — Voice in, voice out**: send Jarvis a voice note and get a spoken answer back.
