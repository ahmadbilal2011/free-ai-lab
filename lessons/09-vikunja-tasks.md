# Lesson 09 — Vikunja: my private task manager

**Goal:** a private to-do app on your phone and laptop, for daily tasks, projects, due dates and reminders. Later, Jarvis will read and add tasks here for you.

**Time:** about 15 minutes.

**Cost:** $0. Vikunja is open source; it runs on our server and stays private behind Tailscale.

---

## Part A — Why a task manager, and why Vikunja?

Jarvis needs a place to **keep track of your life**: what to do today, what's overdue, what's planned. Google Tasks or Todoist would work, but then your plans live on someone else's servers. Vikunja is a self-hosted alternative:

| Feature | What it gives you |
|---|---|
| Projects and sub-projects | e.g. *Work*, *Home*, *Learning DevOps* |
| Due dates, reminders, priorities, labels | Plan the day, see what's urgent |
| List, Kanban, Gantt and Table views | Different ways to look at the same tasks |
| Recurring tasks | "Pay rent every month", "Weekly backup check" |
| **API + API tokens** | How n8n and Jarvis will add and read tasks (Lessons 10–12) |
| Single small container with SQLite | Light on RAM, nothing like the AI (check with `docker stats`) |

## Part B — How it fits in

```
Phone / laptop ──Tailscale HTTPS──► https://free-ai-lab.<tailnet>.ts.net:8443  ──► Vikunja (127.0.0.1:3456)
                                    https://free-ai-lab.<tailnet>.ts.net        ──► Open WebUI (port 3000)
```

**New idea: one name, several apps, different ports.** Tailscale Serve can publish more than one app on the same private name. Open WebUI keeps the normal HTTPS port (443), and Vikunja gets **8443**. Both stay invisible to the internet.

### Choices in the stack file

[`stacks/tasks/compose.yaml`](../stacks/tasks/compose.yaml):

| Setting | Why |
|---|---|
| `127.0.0.1:3456` | Server-only, like every app in this lab |
| Data in `./files` and `./db` inside `~/lab/tasks` | The nightly backup already copies `~/lab`, so tasks are backed up with **no extra work** |
| Folders owned by user `1000` | The Vikunja container runs as user 1000 and must be able to write there |
| `VIKUNJA_SERVICE_PUBLICURL` | Vikunja must know its own address (our `…ts.net:8443`) for the web app to talk to its API |
| `VIKUNJA_SERVICE_SECRET` in `.env` | Signs your logins. Random, private, never on GitHub |
| `ALLOW_SIGNUP` | **Open** only while you create your account, then **closed** (`--lock`) |
| No healthcheck | The official image has no shell or curl inside to run one. Crashes are still restarted by `restart: unless-stopped` |

### Why close sign-up?

Only your Tailscale devices can reach Vikunja, so strangers can't sign up anyway. But "only one door, and it's locked" is a good habit: if you ever share access with someone, they can't quietly create extra accounts. This is **defence in depth**: more than one layer of protection.

---

## Part C — Install (one command)

On the VM, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-tasks.sh -o 09-install-tasks.sh && bash 09-install-tasks.sh
```

It will:

1. Create `~/lab/tasks` with the right folder owner
2. Write a private `.env` with a random secret and your Tailscale address
3. Start Vikunja and wait until its API answers
4. Publish it on **`https://free-ai-lab.<your-tailnet>.ts.net:8443`** (Tailscale only)
5. Add Vikunja to the nightly backup (it pauses a few seconds at 03:30 for a clean copy, like Open WebUI)

## Part D — Create your account, then lock the door

1. On your laptop or phone (Tailscale **on**), open the address the script printed.
2. Click **Register** and create your account.
3. Back on the VM, close sign-up:

   ```bash
   bash 09-install-tasks.sh --lock
   ```

4. Reload the page: the **Register** link is gone. Log in with your account.

## Part E — Set it up for daily life

1. **Projects:** create a few, e.g. `Inbox`, `Work`, `Home`, `Learning`.
2. **Default project:** **Settings → General → Default project → `Inbox`**. New quick tasks land there, and later Jarvis will drop tasks there too.
3. **Time zone and week start:** **Settings → General**. Check the time zone is `Asia/Riyadh`.
4. **Quick add magic:** in the "Add a task" box, try:

   ```
   Pay electricity bill *home !4 tomorrow at 10:00
   Review backups every week *learning
   ```

   Vikunja turns words into fields: `*label`, `!priority` (1–5), dates like `tomorrow`, `next monday`, `in 3 days`, and `every week` for recurring tasks.
5. **Phone:** open the same `:8443` address, then **Add to Home Screen** (like Open WebUI in Lesson 05). Now you have two app icons: your AI and your tasks.

> There is also an official Vikunja mobile app, but its own docs say it only supports the most basic features. The web app on your home screen is the better choice.

## Part F — Prepare for Jarvis: an API token

In Lessons 10–12, n8n and Jarvis will read and add tasks through Vikunja's **API**. They need a **token**: a password just for programs, with only the permissions you choose.

You'll create it in that lesson, under **Settings → API Tokens**, with the smallest set of permissions it needs. For now, just know where it lives.

---

## Useful commands

| Command | What it does |
|---|---|
| `bash 09-install-tasks.sh` | Update Vikunja to the newest version (re-opens sign-up, so run `--lock` again after) |
| `bash 09-install-tasks.sh --lock` | Close sign-up |
| `docker logs --tail 50 vikunja` | See errors |
| `tailscale serve status` | Which apps are published on which ports |
| `sudo lab-status` | Whole lab health, now including `vikunja` |

## If something goes wrong

| Problem | Fix |
|---|---|
| Page doesn't load | Tailscale on? Note the **`:8443`** at the end of the address. Run `docker ps` to check `vikunja` is up |
| "Could not connect to the API" / CORS error | The `PUBLIC_URL` in `~/lab/tasks/.env` must match the address in your browser exactly. Run the install script again |
| `permission denied` in `docker logs vikunja` | Folder owner is wrong: `sudo chown -R 1000:1000 ~/lab/tasks/files ~/lab/tasks/db` and `docker restart vikunja` |
| Register link still visible after `--lock` | Reload with Ctrl+F5. Check `grep ALLOW_SIGNUP ~/lab/tasks/.env` says `false` |

---

## Checklist

- [ ] Ran `09-install-tasks.sh`, opened `https://…ts.net:8443`
- [ ] Created my account, then ran `--lock`; the Register link is gone
- [ ] Created projects and set `Inbox` as default
- [ ] Added a recurring task with quick-add magic
- [ ] Added Vikunja to my phone's home screen
- [ ] Ran `sudo lab-backup` once and saw **Backup OK** (now including tasks)

## Check your understanding

1. Why do Open WebUI and Vikunja use different ports on the same Tailscale name?
2. Why are Vikunja's folders inside `~/lab/tasks` instead of Docker named volumes?
3. If only my devices can reach Vikunja, why still close sign-up?
4. What is an API token, and how is it different from your password?

## Next

**Lesson 10 — n8n basics**: the automation engine that will connect your AI, tasks and messages.
