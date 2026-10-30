# Lesson 09 — n8n basics: Jarvis's nervous system

**Goal:** install **n8n**, connect it to your AI gateway, and build your first two workflows. Every Jarvis skill from now on (Telegram, voice, reminders, cloud tools, agents) will be an n8n workflow.

**Time:** about 30–40 minutes.

**Cost:** $0. n8n is free to self-host for personal use.

---

## Part A — What is n8n, and why is it the core of Jarvis?

**n8n** (say "n-eight-n") is a workflow automation tool. You build automations by connecting **nodes** on a canvas: "when *this* happens, do *that*, then *that*".

```
 [Trigger] ──► [Node] ──► [Node] ──► [Node]
 "every day     "ask the    "format     "send to
  at 7:00"       AI"         reply"      Telegram"
```

Why it's the right core for your Jarvis:

| Reason | Detail |
|---|---|
| **Low server load** | n8n only *coordinates*. The heavy thinking happens in free cloud models through our gateway |
| **Hundreds of ready connectors** | Telegram, Google (Calendar, Tasks, Gmail), Microsoft, web requests, and more. No code needed for most |
| **AI built in** | AI Agent nodes, chat models, memory and tools (Lesson 12) |
| **Visual** | You see each step and its data, which makes it easy to learn and debug |
| **Your data stays here** | Workflows and saved credentials live on your server, encrypted |

> **Licence note:** n8n is "fair-code" (Sustainable Use License), not classic open source. It's **free to self-host for personal and internal use**, which is exactly our case. You just can't resell it as a service.

### Core words

| Word | Meaning |
|---|---|
| **Workflow** | One automation: a chain of nodes |
| **Trigger** | The node that starts a workflow: a schedule, a Telegram message, a webhook, or a manual click |
| **Node** | One step: "call AI", "send message", "if/else", "HTTP request"… |
| **Credential** | A saved login/API key that nodes use. n8n **encrypts** these |
| **Execution** | One run of a workflow, with the data at every step (great for debugging) |
| **Active** | A workflow switched on, so its trigger runs automatically |
| **Expression** | `{{ ... }}`: use data from earlier steps, e.g. `{{ $json.text }}` |

## Part B — How it fits in

```
Your browser ──Tailscale HTTPS──► https://free-ai-lab.<tailnet>.ts.net:9443 ──► n8n editor (127.0.0.1:5678)
                                                                                   │
                                                          workflows call ──────────┘
                                                          http://litellm:4000/v1  (smart / fast / private)
```

Choices in [`stacks/jarvis/compose.yaml`](../stacks/jarvis/compose.yaml):

| Setting | Why |
|---|---|
| Built-in **SQLite** (no Postgres container) | One less container: lower RAM, matches your "low usage" goal. Plenty for one person |
| `127.0.0.1:5678` + Tailscale `:9443` | Editor is private, like everything else. Tailscale Funnel can't publish port 9443 at all, so the editor can never go public by mistake |
| Joins the `ai_default` network | Workflows reach the gateway as `http://litellm:4000/v1` |
| `N8N_ENCRYPTION_KEY` in `.env` | Encrypts saved credentials. **If it's lost, every saved credential is unreadable** |
| `mem_limit: 1g` | n8n can never eat the memory the rest of the lab needs |
| Executions pruned after 14 days | Run history doesn't slowly fill the disk |
| `N8N_DIAGNOSTICS_ENABLED=false` | No usage telemetry sent out |
| Healthcheck + autoheal label | A frozen n8n is restarted automatically (Lesson 04) |
| Data in `~/lab/jarvis/n8n` | Included in the nightly backup automatically |

---

## Part C — Install (one command)

On the VM, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-n8n.sh -o 09-install-n8n.sh && bash 09-install-n8n.sh
```

It will:

1. Create `~/lab/jarvis` with the right folder owner
2. Write a private `.env` with a random **encryption key** and your Tailscale name
3. Start n8n and wait until it's healthy
4. Publish the editor at **`https://free-ai-lab.<your-tailnet>.ts.net:9443`** (Tailscale only)
5. Add n8n to the nightly backup (it pauses a few seconds at 03:30)
6. **Show the encryption key once.** Save it in your password manager

Then open the address on your laptop (Tailscale on) and **create the owner account right away**: the first person to open a new n8n becomes its owner.

---

## Part D — Connect n8n to your AI gateway

n8n's AI nodes speak the same request format as our gateway, so we use n8n's **OpenAI** credential type but point it at **our gateway** instead of OpenAI. No OpenAI account is involved.

1. On the VM, show the gateway master key (only paste it into n8n):
   ```bash
   grep LITELLM_MASTER_KEY ~/lab/gateway/.env
   ```
2. In n8n: **Overview → Credentials → Create credential** (or the **+** menu) → search **OpenAI** → fill in:

   | Field | Value |
   |---|---|
   | API Key | the `sk-…` master key |
   | Base URL | `http://litellm:4000/v1` |
   | Organization ID | leave empty |

3. Name it **`Lab gateway`** → **Save**. A green "Connection tested successfully" means n8n can reach the gateway.

From now on, every AI node in every workflow uses `Lab gateway`, and picks `smart`, `fast` or `private`.

---

## Part E — Workflow 1: "Hello Jarvis" (manual)

1. **Workflows → Create workflow** → name it `Hello Jarvis`.
2. Click **Add first step** → **Trigger manually**.
3. Click **+** after it → search **Basic LLM Chain** → add it.
   - **Source for Prompt:** *Define below*
   - **Prompt:** `You are Jarvis, my personal assistant. Greet me in one short sentence and tell me one useful DevOps tip.`
4. On the chain's **Model** connector (bottom), click **+** → **OpenAI Chat Model**:
   - **Credential:** `Lab gateway`
   - **Model:** choose **`smart`** from the list (or *By ID* → type `smart`)
5. Click **Execute workflow**.

Click the chain node to see its **input**, **output** and the model's answer. That's your first Jarvis response from n8n. 🎉

Try changing the model to `fast` and `private`, and compare speed and quality. This is the same gateway as Open WebUI, with the same fallback when a free tier runs out.

## Part F — Workflow 2: a scheduled job

Now a workflow that runs **by itself**.

1. Create workflow `Hourly tip (practice)`.
2. Trigger: **On a schedule** → **Every hour**.
3. Add **Basic LLM Chain** with model `fast` and the prompt:
   `Give one short, practical Linux command tip with an example. Max 2 sentences.`
4. Save, then switch the workflow to **Active** (top right).
5. After an hour, open **Executions** (left menu): each run is listed with its result.
6. When you've seen it work, switch it **off**. We don't want to spend free-tier requests on practice. In Lesson 10, a scheduled workflow like this will message you on Telegram instead.

### What you just learned

| Idea | Where you saw it |
|---|---|
| Triggers (manual vs. schedule) | Workflows 1 and 2 |
| Credentials, saved once and reused, encrypted | `Lab gateway` |
| Using the gateway aliases from any workflow | `smart` / `fast` / `private` |
| Executions as a debugging history | The Executions page |
| Active vs. inactive | Workflow 2 |

---

## Part G — Looking ahead: how Jarvis will hear you

In Lesson 10, Jarvis gets a Telegram bot. Our server stays **completely private**: instead of Telegram calling *in* to our server, **n8n will ask Telegram** for new messages every few seconds ("pull" instead of "push"). n8n only ever reaches *out*: to Telegram, to the AI gateway, and later to your cloud tools.

---

## Useful commands

| Command | What it does |
|---|---|
| `bash 09-install-n8n.sh` | Update n8n to the newest version (data and key kept) |
| `docker logs --tail 50 n8n` | See errors |
| `docker stats --no-stream` | RAM/CPU of each container (check n8n stays light) |
| `sudo lab-status` | Whole lab health, now including `n8n` |
| `tailscale serve status` | Which apps are published on which ports |

## If something goes wrong

| Problem | Fix |
|---|---|
| Editor doesn't load | Tailscale on? Note the **`:9443`**. `docker ps` should show `n8n (healthy)` |
| `permission denied` / `EACCES` in `docker logs n8n` | `sudo chown -R 1000:1000 ~/lab/jarvis/n8n && docker restart n8n` |
| Credential test fails | Base URL must be exactly `http://litellm:4000/v1`; the key must be the **master** key; `docker ps` must show `litellm (healthy)` |
| Model list is empty | Choose **By ID** and type `smart` |
| `Mismatching encryption keys` | The key in `~/lab/jarvis/.env` changed. Restore the original from your password manager |
| n8n restarts often | `docker logs n8n` and `docker logs autoheal`. If it says out of memory, raise `mem_limit` to `1536m` |

---

## Checklist

- [ ] Ran `09-install-n8n.sh`; n8n is **healthy**
- [ ] Saved the n8n encryption key in my password manager
- [ ] Created the owner account at `https://…ts.net:9443`
- [ ] Created the **`Lab gateway`** credential and its test passed
- [ ] `Hello Jarvis` answered with `smart`, `fast` and `private`
- [ ] Saw scheduled runs under **Executions**, then switched the practice workflow off
- [ ] Checked `docker stats --no-stream`; noted n8n's RAM in `PROGRESS.md`

## Check your understanding

1. What's the difference between a trigger and a node?
2. Why does n8n use the "OpenAI" credential type even though we don't use OpenAI?
3. What happens to your saved credentials if the encryption key is lost?
4. Why will n8n *ask* Telegram for messages instead of letting Telegram call in?

## Next

**Lesson 10 — Telegram bot: text Jarvis from anywhere.**
