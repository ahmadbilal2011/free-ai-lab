# Lesson 10 — First agent: Reminders

**Goal:** Jarvis gets its first real skill. Say *"Remind me tomorrow at 9 to call Usman"* on the dashboard or on Telegram. At 9:00 the reminder arrives **on Telegram** and Jarvis **says it aloud** on the dashboard.

You learn the pattern every later agent uses:
- an agent is a **branch in one n8n workflow** (*Jarvis agents*);
- it tells Jarvis **what it can do** and **in what format** (the *Agent list*);
- it can say which actions need a **yes first**;
- it can **push** news to Telegram and the dashboard by itself.

**Time:** about 30 minutes. **Cost:** $0, no new accounts or keys.
**Before you start:** Lesson 07 (Telegram bot) and Lesson 09 (Jarvis Live, Part D) are done.

**Status:** ⚠️ Written. The agent's code is tested (add, list, cancel, wrong input, past times, delivery). The workflow import and the Telegram tool are first tried on your server.

---

## Part A — How it works

```
 You (dashboard or Telegram): "Remind me tomorrow at 9 to call Usman"
        │
        ▼
 Jarvis's brain reads the Agent list, works out the exact time from "Now",
 and calls the agent with:  {"action":"add","text":"call Usman","at":"2026-11-21T09:00:00+03:00"}
        │  POST /webhook/jarvis-live-tool  (with the Jarvis secret)
        ▼
 n8n "Jarvis agents" ── Run the agent ──► saves it ──► "Reminder #4 set for Sat 21 Nov, 09:00"
        │
 Every minute ── Due reminders ──┬──► Telegram: "⏰ Reminder: call Usman"
                                 └──► Jarvis Live: shown in the log and read aloud
```

| Idea | Why |
|---|---|
| **The brain turns words into exact data** | "tomorrow at 9" becomes a full date and time. The agent stays simple and never guesses |
| **Agents check everything** | Wrong format, a past time or an unknown number → a clear error the brain can fix and retry |
| **Ask first** | Cancelling is listed as *ask first*: Jarvis says which reminder it will cancel and waits for your yes. Adding a reminder is harmless, so it doesn't ask |
| **Reminders stay inside n8n** | Kept in the workflow's own storage. No database to install, and they're in the nightly backup (Lesson 08) |

> **Honest limit:** the *ask first* rule is followed by the AI model. For agents that send email or touch money, later lessons add a real **Yes / No button** on Telegram that the model can't skip.

## Part B — Replace the "Jarvis agents" workflow

The new version contains everything from Lesson 09 plus the Reminders agent.

1. n8n → **Overview** → open **Jarvis agents** → **⋯ (top right) → Unpublish**, then **⋯ → Archive**. Two workflows can't use the same webhook address, so the old one must go first.
2. Download [`stacks/jarvis/workflows/jarvis-agents.json`](../stacks/jarvis/workflows/jarvis-agents.json) to your laptop.
3. **Create workflow → ⋯ → Import from File** → choose it.
4. Set the credentials (all of them already exist):

| Node | Set |
|---|---|
| **Jarvis asks: which agents?** | Credential `Jarvis Live secret` |
| **Jarvis asks: do this task** | Credential `Jarvis Live secret` |
| **Remind me on Telegram** | Credential `Jarvis bot` · **Chat ID**: replace `YOUR_TELEGRAM_ID` with your own Telegram ID (the number in the *Only me* node, Lesson 07) |
| **Tell Jarvis Live** | Authentication is already *Header Auth* → choose `Jarvis Live secret` |

5. **Save**, then **Publish**.
6. On the dashboard, click **↻** next to *Agents*. You should see **Reminders** (amber) in the roster and on the globe's orbit.

> ⚠️ **Don't test with the editor's "Execute workflow" button.** n8n only keeps reminders after **real** runs (from Jarvis, Telegram or the schedule). Editor test runs forget them.

## Part C — Update Jarvis Live

Jarvis Live now tells the brain the current time and each agent's task format, and reads reminders aloud. On the server (Cloud Shell → VM):

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-live.sh
bash 09-install-live.sh
```

Your password, keys and AI providers are kept. The test line **jarvis-live → n8n agents** should say **200**.

## Part D — Try it on the dashboard

| Say or type | Expected |
|---|---|
| *Remind me in 2 minutes to drink water* | The Reminders lane lights up on the timeline; Jarvis: *"Reminder #1 set for … 22:14"* |
| (wait 2 minutes) | Telegram: **⏰ Reminder: drink water**. Dashboard: amber alert in the log, read aloud (🔊 on) |
| *Kal subah 9 baje Usman ko call karne ka yaad dilana* | Set for tomorrow 09:00, answer in Urdu |
| *What reminders do I have?* | The list with numbers |
| *Cancel the Usman reminder* | Jarvis asks first: *"Cancel #2, Sat 09:00, call Usman?"* → say **yes** → cancelled |
| *Remind me yesterday at 5* | Jarvis says that time is past |

Hover over Jarvis's answer to see which model replied and whether it called the agent.

## Part E — Give the Telegram bot the same skill

The Telegram AI Agent (Lesson 07) gets the Reminders agent as a **tool**. Open the Telegram workflow:

**1. Tell it the time.** In **AI Agent → System Message**, add at the end:

```
Now: {{ $now.setZone('Asia/Riyadh').toFormat("cccc d LLLL yyyy, HH:mm") }} (Asia/Riyadh, offset +03:00).
For reminders use the Reminders tool. Before cancelling one, say which and wait for "yes".
```

**2. Add the tool.** Under the AI Agent click **Tool +** → **HTTP Request Tool**:

| Field | Value |
|---|---|
| Description | `Reminders: add, list or cancel the owner's reminders. task is a JSON text: {"action":"add","text":"what to remember","at":"2026-11-21T09:00:00+03:00"} or {"action":"list"} or {"action":"cancel","id":3}` |
| Method | POST |
| URL | `http://localhost:5678/webhook/jarvis-live-tool` |
| Authentication | Generic Credential Type → **Header Auth** → `Jarvis Live secret` |
| Send Body | on · Body Content Type **JSON** · Specify Body **Using Fields Below** |
| Field 1 | Name `agent` · Value `reminders` |
| Field 2 | Name `task` · Value: click the ✨ button (**Let the model define this parameter**) |

Name the tool node `Reminders`. **Save** and keep the workflow published.

**3. Try it:** send the bot *"Remind me in 3 minutes to check the SAR rate"*. It answers with the reminder number, and 3 minutes later the reminder arrives in the same chat.

`localhost:5678` is n8n calling itself inside the server: nothing new is opened to the internet.

## Part F — Check

| Check | Expected |
|---|---|
| Dashboard roster | **Reminders** listed, n8n *connected · 1 agent* |
| `curl -s -o /dev/null -w "%{http_code}\n" -X POST https://n8n-<your-ip-with-dashes>.sslip.io/webhook/jarvis-live-tool` (from your laptop) | **403** (no secret, no entry) |
| n8n → **Executions** of *Jarvis agents* | Only **failed** runs are listed. Successful runs aren't saved, otherwise the every-minute check would fill the list |
| Backup | Tonight's zip includes n8n's data, so your reminders are in it |

## How to add the next agent (the pattern)

1. Add an entry to **Agent list**: `id`, `name`, `role` (one line), `color`, `howTo` (the task format), `confirm` (actions that need a yes).
2. In **Run the agent** (or a Switch before it), handle `body.agent === '<id>'` and return `{ ok, result }` or `{ ok: false, error }`.
3. Need to speak up by itself? POST to `http://jarvis-live:8080/api/event` like **Tell Jarvis Live**, and send to Telegram like **Remind me on Telegram**.
4. Publish → **↻** on the dashboard. Jarvis knows the new agent at once.

## If something goes wrong

| Problem | Fix |
|---|---|
| Publishing says the webhook path is already used | The old *Jarvis agents* is still published: unpublish and archive it (Part B, step 1) |
| Roster still empty after ↻ | The new workflow isn't published, or the webhook credentials aren't set |
| Jarvis says it can't set reminders | Click ↻; still no luck → re-run the installer (Part C), then reload the page |
| Reminder set for the wrong hour | Part C not done yet (the brain didn't know the time), or the Telegram System Message is missing the *Now* line |
| *"Send the task as JSON…"* in the log | The model sent plain words. It usually retries by itself; if not, put a stronger model first under **AI providers** |
| Reminder never arrives | Is the workflow published? Is the Chat ID your number? n8n → Executions shows failed runs with the reason |
| Telegram works, dashboard silent | 🔊 must be on and the page open; the alert still appears in the log |
| Telegram tool: *Authorization failed* | The HTTP Request Tool must use **Header Auth** `Jarvis Live secret` |
| Reminders vanished | They were set during an editor test run. Set them again through Jarvis or Telegram |

## Next

**Lesson 11 — Calendar, email and web search**: free cloud tools as agents, using the same pattern. Sending anything gets a real Yes / No button first.
