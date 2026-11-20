# Lesson 09 — Jarvis Live: the dashboard of your personal AI operating system

**Goal:**
- Open one screen and **talk** to Jarvis (or type).
- See an animated AI sentinel answer you, a globe with your server, live server health, and a command log.
- Connect the dashboard to the **n8n** you installed in Lesson 06, so that every **agent** you build in upcoming lessons appears here and can be used by voice.

**This lesson adds no agents.** Today Jarvis can talk and answer general questions. Actions such as your calendar, email, SAR desk or your PC come one per lesson, built in n8n.

**Time:** about 40 minutes. **Cost:** $0. **Before you start:** Lessons 06–07 are done (n8n online, Telegram bot working).

**Status:** ⚠️ Written. Tested locally in a browser with a stand-in n8n:
- sign-in, live metrics, the sentinel's three states
- the empty agent list, and agents appearing by themselves when n8n lists them
- alerts, and desktop and phone layouts

Real voice calls need your server and Google: the first call happens there.

![Jarvis dashboard, no agents yet](../docs/images/09-dashboard.png)

---

## Part A — The architecture (built for what's coming)

```
 you: voice + text ──► Jarvis dashboard (browser): sentinel · globe + agent orbit · timeline · system · log
          ▲   │ voice both ways, straight to Google                ▲ live events (metrics, agent steps, alerts)
          │   ▼                                                    │
   Gemini Live API (free) = ORCHESTRATOR                    jarvis-live (small server on your VM)
   hears you, decides, calls agents ──── tool calls ───────► • one-time Gemini tokens (key stays on the server)
                                                             • server health + alerts by itself
                                                             • asks n8n: "which agents exist?" / "do this task"
                                                                         │
                                                                         ▼
                                                   n8n (Lesson 06) — workflow "Jarvis agents"
                                                   • Agent list ............ empty today
                                                   • one branch per agent .. added lesson by lesson
                                                   • any workflow can push events back to the dashboard
```

**Why agents live in n8n, not in the dashboard:**
- **You build them in n8n's web page.** That's the rule of this course: no code changes to add a skill.
- **One brain, every door.** The same agent can serve the voice dashboard, Telegram Jarvis (Lesson 07) and scheduled routines.
- **The dashboard follows by itself.** When n8n's agent list changes, the globe, the roster and Jarvis's tools update. Click **↻** to check at once.

**Future goals this design is ready for:**

| Coming | What it adds | Where it plugs in |
|---|---|---|
| Lesson 15 · Agents and tools | First agents, with approval before any action | n8n *Agent list* + branches |
| Lesson 16 · Calendar, reminders, email | "What's on today?", "Remind me at 9" | n8n agents |
| Lesson 17 · Memory (RAG) | Jarvis remembers preferences, past talks, documents | a `memory` agent in n8n |
| Lesson 18 · Routines | Morning briefing, SAR desk alerts, spoken by Jarvis | n8n schedules + events to the dashboard |
| Lessons 10–12 · Laptop hands | "Open my QA report" on your PC | a `laptop` agent: n8n → OpenJarvis |
| Later · premium brain | Claude for hard jobs, only when you choose | a Bifrost model used inside n8n agents |

## Part B — The dashboard

| Where | Panel | What it shows |
|---|---|---|
| Top left | **System integrity** | CPU and memory rings, network in and out, a short history, load, uptime, RAM, from the real server |
| Below | **Agents** | Whether **n8n is connected**, and the agents it lists. Today: *No agents yet* |
| Center | **Multi-agent operations** | A dotted holographic globe with **your server** marked, inside an empty **agent orbit**. Each agent you add takes a place on it; a working agent glows and fires an arc to the server |
| Below | **Task timeline** | Gantt chart of the last 3 minutes of agent tasks |
| Top right | **Jarvis** | The **AI sentinel**, described below |
| Below | **Live command log** | What you said, what Jarvis said, agent steps and alerts, time-stamped |
| Bottom | **Command bar** | Mic (start/end voice), waveform, text input |

Drag the thin lines between panels to resize; the layout is remembered. On a phone, the panels stack.

### Jarvis's avatar: the AI sentinel

![The sentinel: idle, speaking, thinking](../docs/images/09-sentinel-states.png)

An original design for this course: a faceted helm floating in an orbit ring.

| State | What you see |
|---|---|
| **Idle / listening** | It hovers. The visor's eyes glance around and blink, then look at you while you speak |
| **Thinking** | A digital ripple runs across it, the visor scans, and the orbit speeds up |
| **Speaking** | The voice-grille bars move with Jarvis's real voice: louder sounds raise them, sharper sounds spread them outward. A waveform runs below |

It doesn't copy any film character: their designs belong to their studios.

## Part C — Install (one command, on the server over SSH)

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-live.sh
bash 09-install-live.sh
```

It asks for three things:
1. Your **Gemini API key**: free from aistudio.google.com/apikey, from a project without billing. It's typed hidden and checked with Google.
2. A **page password** (12+ characters, hidden). It's stored only as a hash.
3. Your first name, which is how Jarvis addresses you.

**Expected tests at the end:**

| Test | Expected |
|---|---|
| `https://live-…sslip.io/` | **200** (sign-in page) |
| token without sign-in | **401** |
| `http://<ip>:8090` | **000** (not public) |
| `/api/event` from the internet | **403** (only n8n inside the server may push events) |
| n8n → jarvis-live | **yes** |
| jarvis-live → n8n agents | **404** before Part D, **200** after it |

It also prints the **Jarvis secret** for Part D. Keep the terminal open.

## Part D — Connect n8n (import one workflow)

1. n8n → **Credentials → Create → Header Auth**. Name `X-Jarvis-Secret`, Value = the Jarvis secret from the installer. Save it as `Jarvis Live secret`.
2. Download [`stacks/jarvis/workflows/jarvis-agents.json`](../stacks/jarvis/workflows/jarvis-agents.json) to your laptop.
3. n8n → **Create workflow → ⋯ (top right) → Import from File** → choose it.
4. In both webhook nodes (*Jarvis asks: which agents?* and *Jarvis asks: do this task*), set the Credential to `Jarvis Live secret`.
5. **Publish** the workflow.
6. On the dashboard, click **↻** next to *Agents*. It should say **n8n connected · no agents yet**.

What's inside:
- **Agent list** answers `{ "agents": [] }`, which is empty for now.
- **Do this task** answers "no agent set up yet".

Each upcoming lesson adds one entry to the list, for example `{ "id": "calendar", "name": "Calendar", "role": "meetings and reminders", "color": "#b388ff" }`, plus that agent's branch.

## Part E — First talk

1. Open `https://live-<your-ip-with-dashes>.sslip.io` on your phone or PC and sign in.
2. Tap the mic and allow the microphone.
3. Say *"Assalam o alaikum Jarvis, what can you do for me today?"*. The sentinel speaks, and both sides appear in the log.
4. Interrupt it mid-sentence: it stops and listens.
5. Ask for an action, such as *"What's on my calendar?"*. Jarvis should say that skill arrives when its agent is added. It must **not** make up an answer.
6. Type a question in the bottom bar: the answer comes in the same conversation.

## Part F — Events: n8n can make Jarvis speak up

Any n8n workflow (now or later) can add an **HTTP Request** node:

| Field | Value |
|---|---|
| Method / URL | POST `http://jarvis-live:8080/api/event` (private network) |
| Authentication | Generic → Header Auth → `Jarvis Live secret` |
| Body (JSON) | `{ "type": "alert", "text": "Backup finished", "speak": true }` |

- **Alerts** show in amber in the log. During a call, Jarvis mentions them out loud.
- **Agent work on the timeline:** `{ "agent": "<id>", "status": "start" or "done", "task": "…" }` shows that agent's work.
- **Agent list changed:** `{ "refresh": true }` makes the dashboard ask n8n for the list again.

The server also watches itself: memory above 85% or CPU above 90% for a minute → an alert.

## Part G — Security

| Lock | What it stops |
|---|---|
| HTTPS + page password (scrypt hash) + fail2ban (5 tries / 10 min → 1 h ban) | Strangers using your Jarvis |
| Gemini key stays on the server; browsers get one-time tokens (1 minute to start) | Key theft from a phone or browser |
| Jarvis can only call agents that n8n lists; every call carries the secret | Jarvis being tricked into random actions |
| `/api/event` blocked from the internet | Fake alerts from outside |
| Container read-only, no extra rights, 128 MB, server stats read-only | A bug harming the server |

## Commands

| Command | What it does |
|---|---|
| `bash 09-install-live.sh` | Update (asks only for what's missing) |
| `bash 09-install-live.sh --password` | Change the page password |
| `bash 09-install-live.sh --off` | Stop it and take the page offline |
| `LIVE_MODEL=<name> bash 09-install-live.sh` | Force another Gemini Live model |
| `docker logs --tail 30 jarvis-live` | Errors and agent calls |

## If something goes wrong

| Problem | Fix |
|---|---|
| Agents says *n8n not reachable* | `docker ps` should show `n8n` healthy; both containers must be on the `jarvis` network (the installers do this) |
| Agents says *workflow isn't published yet* | Part D: import and **Publish** "Jarvis agents" |
| Agents says *n8n refused the Jarvis secret* | The Header Auth value in n8n differs from `N8N_TOOL_SECRET` in `~/lab/live/.env` |
| "Couldn't start voice: Google answered 4xx" | Key or model not allowed. Re-run the installer and send me its *Token test* line |
| Voice link closes at once (code 1007/1008) | `docker logs jarvis-live`, then `LIVE_MODEL=<another> bash 09-install-live.sh` |
| Header shows *reconnecting…* | It retries by itself; if it stays, check `docker ps` shows `jarvis-live` healthy |
| No microphone prompt | Open over **https**; browser site settings → Microphone → Allow |
| Jarvis hears itself | Use earphones or lower the volume |

## Next

Agents, one lesson at a time, all in n8n. Each one appears on this dashboard by itself the moment you publish it.
