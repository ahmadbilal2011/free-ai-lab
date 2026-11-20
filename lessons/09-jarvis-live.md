# Lesson 09 — Jarvis Live: talk to Jarvis in real time, like a call

**Goal:** open a page on your phone, tap once, and **talk** to Jarvis back and forth, interrupting it like a person.
Jarvis can also **do things** while you talk, through n8n (first skill: send a note to your Telegram).

**Time:** about 30 minutes. **Cost:** $0 (Gemini Live API free tier). **Before you start:** Lessons 06–07 are done.

**Status:** ⚠️ Written and tested locally (login, tokens route, tools). The first real call happens on your server.

---

## Part A — How it works

```
📱 Phone browser ── https://live-<ip>.sslip.io (password) ──► jarvis-live (small container on the server)
       │                                                         │ 1. gives the phone a ONE-TIME Gemini token
       │                                                         │    (the real key never leaves the server)
       └──── voice, both ways, straight to Google ─────────► Gemini Live API (free tier)
                                                                 │ 2. "send this to Telegram"
       phone ── /api/tool ──► jarvis-live ── secret ──► n8n webhook ──► Telegram / any skill
```

| Piece | Why |
|---|---|
| **Gemini Live API** | Real-time speech in and out (many languages, Urdu included); you can interrupt it |
| **One-time tokens** | Valid for 1 minute to start one call. Even if someone copied one, it's useless right after |
| **Voice goes straight to Google** | Lowest delay, and almost no load on the server |
| **Tools through n8n** | Jarvis's skills live in n8n, so Telegram Jarvis and Live Jarvis share them |

**Honest limits**
- Live models are **preview** models: Google can change or rename them. The installer picks one your key can use.
- Free tier: limited minutes and parallel calls, enough for one person. Google ends a call after a while; just tap again.
- On the free tier Google may use conversations to improve its products: **no customer (SAR) data** in Live calls.
- The phone screen should stay on during a call (the page asks the browser to keep it awake).

## Part B — Install (one command, on the server over SSH)

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-live.sh
bash 09-install-live.sh
```

It asks for:
1. Your **Gemini API key**: free from aistudio.google.com/apikey, from a project **without billing**. It's typed hidden and checked with Google.
2. A **page password** (12+ characters, hidden). It's stored only as a hash.
3. Your first name, which is how Jarvis addresses you.

Then it picks the Live model, checks one-time tokens work, builds the container, gets the certificate, and adds the
Apache site and fail2ban jail.

**Expected tests at the end:**
- `https://live-…sslip.io/` → **200** (the sign-in page)
- token without sign-in → **401**
- `http://<ip>:8090` → **000** (not public)

It also prints a **tool secret** for Part D. Keep the terminal open.

## Part C — First call

1. On the phone, open `https://live-<your-ip-with-dashes>.sslip.io` and sign in.
2. Tap the circle. Allow the **microphone**.
3. Say *"Assalam o alaikum Jarvis, aaj mujhe kya kya karna chahiye?"*. Jarvis answers by voice, and both sides
   appear as text below the circle.
4. Interrupt it mid-sentence: it stops and listens.
5. Tap the circle again to end the call.

Tip: in the browser menu, choose **Add to Home screen** for an app icon.

## Part D — Give Jarvis hands: the n8n tools workflow

Jarvis knows two tools: `send_to_telegram` and `run_skill`. Both go to **one n8n workflow**.

**1. Credential:** n8n → **Credentials → Create → Header Auth**. Name `X-Jarvis-Secret`, Value = the tool secret
the installer printed. Save it as `Jarvis Live secret`.

**2. New workflow** `Jarvis Live tools`:

| # | Node | Settings |
|---|---|---|
| 1 | **Webhook** | HTTP Method **POST** · Path `jarvis-live-tool` · Authentication **Header Auth** → `Jarvis Live secret` · Respond: **Using 'Respond to Webhook' Node** |
| 2 | **Switch** (name it `Which tool`) | Rule 1: `{{ $json.body.tool }}` *is equal to* `send_to_telegram` · Rule 2: `{{ $json.body.tool }}` *is equal to* `run_skill` · Options → Fallback Output: *Extra Output* |
| 3 | **Telegram → Send a text message** (output 1) | Credential `Jarvis bot` · Chat ID: your Telegram ID (the number from Lesson 07) · Text `{{ $json.body.args.text }}` · Append n8n Attribution off |
| 4 | **Respond to Webhook** (after 3) | Respond With **JSON** · `{ "ok": true, "result": "sent to Telegram" }` |
| 5 | **Respond to Webhook** (output 2, run_skill) | Respond With **JSON** · Expression: `{{ JSON.stringify({ ok: true, result: $json.body.args.skill === 'server_status' ? 'n8n is running. Server time: ' + $now.toFormat('yyyy-LL-dd HH:mm') : 'Skill "' + $json.body.args.skill + '" is not built yet' }) }}` |
| 6 | **Respond to Webhook** (fallback) | JSON `{ "ok": false, "error": "unknown tool" }` |

**3. Publish** the workflow. Only the published version answers.

**Test by voice:**
- *"Jarvis, send me on Telegram: buy milk tomorrow."* The message should arrive in Telegram.
- *"Jarvis, server ka status kya hai?"* Jarvis should tell you the server time from n8n.

Every new skill later (the SAR rate, pending SAR requests, reminders) is just one more branch in this workflow.

## Part E — Security, in short

| Lock | What it stops |
|---|---|
| HTTPS + page password (hashed) + fail2ban (5 tries / 10 min → 1 h ban) | Strangers using your Jarvis |
| The Gemini key stays on the server; phones get one-time tokens | Key theft from the phone or browser |
| Tools only via n8n, with a secret header; only 2 named tools allowed | Jarvis being tricked into random actions |
| Container read-only, no extra rights, 128 MB limit, port 8090 server-only | A bug in the page harming the server |

## Commands

| Command | What it does |
|---|---|
| `bash 09-install-live.sh` | Update (asks only for what's missing) |
| `bash 09-install-live.sh --password` | Change the page password (signs everyone out) |
| `bash 09-install-live.sh --off` | Stop it and take the page offline |
| `LIVE_MODEL=<name> bash 09-install-live.sh` | Force another Live model |
| `docker logs --tail 30 jarvis-live` | See errors and tool calls |

## If something goes wrong

| Problem | Fix |
|---|---|
| "Couldn't start: Google answered 4xx" | The key or the model isn't allowed. Re-run the installer and send me its *Token test* line |
| Call ends at once with a code (e.g. 1007/1008) | Model name or setup refused: `docker logs jarvis-live`, then try `LIVE_MODEL=<another> bash 09-install-live.sh` |
| No microphone prompt | The page must be opened over **https**; check the browser's site settings → Microphone → Allow |
| Jarvis hears itself / echoes | Use earphones, or lower the speaker volume |
| Tool says "n8n answered HTTP 404" | The `Jarvis Live tools` workflow isn't **published**, or its path isn't `jarvis-live-tool` |
| Tool says "HTTP 403" | The Header Auth value in n8n differs from `N8N_TOOL_SECRET` in `~/lab/live/.env` |

## Next

More skills for both Jarvis (Telegram and Live): SAR→PKR rate, new SAR request alerts, morning summary (Lesson 18).
