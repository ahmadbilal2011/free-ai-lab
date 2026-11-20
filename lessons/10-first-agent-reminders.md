# Lesson 10 — First agent: Reminders

**Goal:** Jarvis gets its first real skill. Say *"Remind me tomorrow at 9 to call Usman"* on the dashboard or on Telegram. At 9:00 the reminder arrives **on Telegram** and Jarvis **says it aloud** on the dashboard.

You learn the pattern every later agent uses:
- an agent is a **branch in one n8n workflow** (*Jarvis agents*);
- it tells Jarvis **what it can do** and **in what format** (the *Agent list*);
- it can say which actions need a **yes first**;
- it can **push** news to Telegram and the dashboard by itself.

**Time:** about 30 minutes. **Cost:** $0, no new accounts or keys.
**Before you start:** Lesson 07 (Telegram bot) and Lesson 09 (Jarvis Live, Part D) are done.

**Status:** ⚠️ Written. Tested locally with stand-ins: the agent's code (add, list, cancel, wrong input, past times, delivery), dashboard → n8n → reply → alert, the check script, and the install script against a simulated n8n container (credentials, Telegram ID, unpublish old, import, publish, keeping reminders). Real n8n first runs on your server. Part C (Telegram tool) is still done by hand.

---

## How it works

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

## Part A — Install it (one command)

On the server (Cloud Shell → VM):

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/10-install-agents.sh
bash 10-install-agents.sh
```

It does every step for you, using n8n's own command line inside the n8n container:

| Step | What happens |
|---|---|
| 1/6 | Updates Jarvis Live to the Lesson 10 version if needed (it now tells its AI the **time** and each agent's **task format**). Password, keys and AI providers are kept |
| 2/6 | Creates or corrects the n8n credential **Jarvis Live secret**, so it always matches Jarvis Live. Finds your Telegram credential (**Jarvis bot**) |
| 3/6 | Finds your **Telegram ID** in Lesson 07's *Only me* node and asks you to confirm it (press Enter) |
| 4/6 | **Unpublishes** the old Lesson 09 *Jarvis agents* (two workflows can't share a webhook address) |
| 5/6 | Imports the new *Jarvis agents*, connects its credentials, **publishes** it |
| 6/6 | Restarts n8n (about 20 seconds; the SAR site isn't touched), then runs **all the checks** below |

It ends with the checks. Each one stops at the first broken link and prints the fix:

| Check | ✓ means | Most common ✗ and fix |
|---|---|---|
| 1/5 Jarvis Live version | up to date | run the script again |
| 2/5 n8n agent list | n8n lists `reminders` | the old workflow is still published: in n8n, unpublish it, run the script again |
| 3/5 Reminders agent answers | *No reminders set.* | open n8n → Executions → the red node says why |
| 4/5 Jarvis Live sees the agent | Jarvis knows Reminders | `docker restart jarvis-live` |
| 5/5 Your models can call agents | at least one ✓ | *answers, but does NOT call agents* → that model can't use tools: move a model that can to the top under **AI providers** |

Continue only when it says **All links work**. Then **reload** the dashboard: the roster shows **Reminders** (amber), and the log says *Agent list updated … Conversation restarted*. You can run the script again any time: it updates the same workflow and keeps your reminders. Later, archive the old unpublished *Jarvis agents* in n8n to keep the list tidy (optional).

You can re-run only the checks with `bash 10-check-agents.sh`:

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/10-check-agents.sh
bash 10-check-agents.sh
```

> ⚠️ **Don't test with the editor's "Execute workflow" button.** n8n only keeps reminders after **real** runs (from Jarvis, Telegram or the schedule). Editor test runs forget them.

<details><summary>Manual way (only if the script can't run)</summary>

1. Run `bash 09-install-live.sh` (updates Jarvis Live).
2. n8n → open the old **Jarvis agents** → **Unpublish**, then **Archive**.
3. Open [`stacks/jarvis/workflows/jarvis-agents.json`](../stacks/jarvis/workflows/jarvis-agents.json) on GitHub → **Download raw file**. n8n → **Create workflow → ⋯ → Import from File**.
4. Credentials: both webhook nodes and **Tell Jarvis Live** → `Jarvis Live secret`; **Remind me on Telegram** → `Jarvis bot`, and replace `YOUR_TELEGRAM_ID` with your Telegram ID.
5. **Save**, **Publish**, then run `bash 10-check-agents.sh`.

</details>

## Part B — Try it on the dashboard

| Say or type | Expected |
|---|---|
| *Remind me in 2 minutes to drink water* | The Reminders lane lights up on the timeline; Jarvis: *"Reminder #1 set for … 22:14"* |
| (wait 2 minutes) | Telegram: **⏰ Reminder: drink water**. Dashboard: amber alert in the log, read aloud (🔊 on) |
| *Kal subah 9 baje Usman ko call karne ka yaad dilana* | Set for tomorrow 09:00, answer in Urdu |
| *What reminders do I have?* | The list with numbers |
| *Cancel the Usman reminder* | Jarvis asks first: *"Cancel #2, Sat 09:00, call Usman?"* → say **yes** → cancelled |
| *Remind me yesterday at 5* | Jarvis says that time is past |

Hover over Jarvis's answer to see which model replied and whether it called the agent.

## Part C — Give the Telegram bot the same skill

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

## Final checks

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
| Jarvis replies without calling the agent | Check 5/5: some models (e.g. some NVIDIA ones through Bifrost) don't use tools. Put Groq `openai/gpt-oss-120b` or a Gemini Flash model first |
| Jarvis says *"I can't set reminders yet… arrives in an upcoming lesson"* | Jarvis sees **no agents**. Run `bash 10-install-agents.sh` again; its checks name the broken link |
| Reminder set for the wrong hour | Jarvis Live not updated (run the script), or the Telegram System Message is missing the *Now* line |
| *"Send the task as JSON…"* in the log | The model sent plain words. It usually retries by itself; if not, put a model that passed check 5/5 first |
| Reminder never arrives | Is the workflow published? Is the Chat ID your number? n8n → Executions shows failed runs with the reason |
| Telegram works, dashboard silent | 🔊 must be on and the page open; the alert still appears in the log |
| Telegram tool: *Authorization failed* | The HTTP Request Tool must use **Header Auth** `Jarvis Live secret` |
| Reminders vanished | They were set during an editor test run. Set them again through Jarvis or Telegram |

## Next

**Lesson 11 — Calendar, email and web search**: free cloud tools as agents, using the same pattern. Sending anything gets a real Yes / No button first.
