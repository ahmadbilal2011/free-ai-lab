# Lesson 08 — Backups and monitoring

**Goal:** never lose your chats, settings or keys, and get an **email** if the server or a backup stops working.

**Time:** about 30 minutes.

**Cost:** $0. Oracle Always Free Object Storage (20 GB), restic (open source), healthchecks.io free plan.

---

## Part A — Why now?

So far everything lives on **one** VM. If it breaks, gets deleted by mistake, or Oracle reclaims it, you lose:

- your Open WebUI account, chats and settings
- your API keys and gateway config
- everything Jarvis will learn later (tasks, n8n workflows, memory)

Before we give the system more of your life, we protect it.

### The 3-2-1 idea (simplified for us)

Keep backups **off the server**, **encrypted**, and **tested**:

| Rule | How we do it |
|---|---|
| Off the server | Oracle **Object Storage**: a separate storage service, not the VM's disk |
| Encrypted | **restic** encrypts everything *before* it leaves the server. Oracle only sees scrambled data |
| Tested | `lab-restore-test` actually restores the latest backup and checks the files |
| Automatic | A timer runs it every night at 03:30 |
| Watched | **healthchecks.io** emails you if a night's backup doesn't report "OK" |

> A backup you've never restored is just a hope. We test the restore on day one.

## Part B — What gets backed up

| Included | Why |
|---|---|
| `~/lab/` (compose files, gateway config, **`.env` keys**) | Rebuild every app exactly as it was |
| Docker volume `ai_open-webui` | Users, chats, settings |
| Every **future** Docker volume (n8n, …) | Picked up automatically, nothing to remember |

| Excluded | Why |
|---|---|
| `ai_ollama` (AI models, several GB) | Can be downloaded again any time. Saves our 20 GB |

**Consistency:** Open WebUI keeps its data in a SQLite database file. Copying it *while it's being written* can give a broken copy, so the backup **pauses Open WebUI for a few seconds** at 03:30 and starts it again right after, even if the backup fails.

**Retention:** 7 daily + 4 weekly + 6 monthly snapshots. restic stores only what changed (**deduplication**), so this stays small.

### The two secrets you must keep safe

| Secret | What it is | If you lose it |
|---|---|---|
| Oracle **Secret key** | Lets the server write to the bucket | Make a new one in the Console. No data lost |
| **Backup encryption password** | Unlocks your backups | **Backups are useless forever.** Nobody can recover it, not even Oracle |

Both are stored on the server in `/etc/free-ai-lab/backup.env` (root-only). **But if the server dies, that file dies with it.** So you must also keep a copy in a **password manager** (Bitwarden is free), never on GitHub.

---

## Part C — Create the backup storage (Oracle Cloud Shell)

Open **Cloud Shell** in the Oracle Console (like in Lesson 01), then:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/08-create-backup-bucket.sh -o 08-create-backup-bucket.sh && bash 08-create-backup-bucket.sh
```

It creates a **private** bucket `free-ai-lab-backups` and an **S3-compatible key pair** ("Customer Secret Key"), then prints 5 lines:

```
  S3 endpoint : https://<namespace>.compat.objectstorage.me-riyadh-1.oci.customer-oci.com
  Bucket      : free-ai-lab-backups
  Region      : me-riyadh-1
  Access key  : ...
  Secret key  : ...   ← shown only once
```

Copy the **Secret key** into your password manager now. Then type `clear`.

> **S3-compatible** means: Oracle's storage speaks the same "language" as Amazon S3, so tools like restic work with it unchanged.

---

## Part D — Install backups on the VM

On the VM:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/08-install-backup.sh -o 08-install-backup.sh && sudo bash 08-install-backup.sh
```

1. Installs **restic**
2. Asks for the 5 values from Part C (the secret key is typed hidden)
3. Asks for two **healthchecks.io** URLs. Press Enter to skip for now and add them after Part E by running the script again
4. Creates the encrypted repository and **shows the backup encryption password once**. Save it in your password manager, then type `SAVED`
5. Installs three commands and two timers
6. Runs the **first backup** and a **restore test** right away

You should end with:

```
Backup OK
...
  OK    /home/ubuntu/lab/ai/compose.yaml
  OK    /home/ubuntu/lab/ai/.env
  OK    /home/ubuntu/lab/gateway/.env
  OK    /home/ubuntu/lab/gateway/config.yaml
  OK    /var/lib/docker/volumes/ai_open-webui/_data/webui.db
RESTORE TEST PASSED
```

### Your new commands

| Command | What it does |
|---|---|
| `sudo lab-status` | One screen: containers, health, memory, disk, Tailscale, last backup |
| `sudo lab-backup` | Back up right now (e.g. before a risky change) |
| `sudo lab-restore-test` | Prove the latest backup restores (do this once a month) |
| `systemctl list-timers 'lab-*'` | When the next backup and heartbeat run |
| `journalctl -u lab-backup -n 50` | Log of the last backup run |

---

## Part E — Monitoring: get an email when something stops

A monitor running *on* the server can't tell you the server is down. So we use a **dead man's switch**: the server regularly says "I'm alive" to an outside service. If the messages **stop**, that service emails you.

[healthchecks.io](https://healthchecks.io) (open source, with a free hosted plan; check its pricing page for current limits) does exactly this.

1. Sign up at <https://healthchecks.io> (free, email only).
2. Create check **`free-ai-lab heartbeat`**: **Period 5 minutes**, **Grace 10 minutes**. Copy its **ping URL** (`https://hc-ping.com/…`).
3. Create check **`free-ai-lab backup`**: **Period 1 day**, **Grace 2 hours**. Copy its ping URL.
4. On the VM, run `sudo bash 08-install-backup.sh` again. Press **Enter** to keep everything, and paste the two URLs when asked.

Now:

| Event | What you get |
|---|---|
| Server off / crashed / reclaimed / no network | Email ~15 minutes later ("heartbeat is DOWN") |
| Nightly backup failed or didn't run | Email (the backup reports `/fail`, or never reports) |
| Everything fine | Silence, plus a green dashboard on healthchecks.io |

> The ping URL works like a password for that check: anyone with it could send fake "I'm alive" messages. Keep it off GitHub, like the other secrets.

In **Lesson 11** these alerts will also go to your **Telegram**.

---

## Part F — Staying clear of Oracle's idle rule

Oracle may **reclaim** (take back) an Always Free VM it considers idle. Per [Oracle's Always Free docs](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm), an A1 VM counts as idle if, over **7 days**, all of these are true:

- CPU usage (95th percentile) is below 20%
- network usage is below 20%
- **memory usage is below 20%** (A1 shapes only)

All three must hold for the VM to count as idle, so keeping **memory above 20%** with real work protects us. We do that honestly by keeping the **private model loaded in RAM all the time**, which also makes `lab.private` answer instantly.

Apply it on the VM:

```bash
cd ~/lab/ai
sed -i 's/OLLAMA_KEEP_ALIVE: "30m"/OLLAMA_KEEP_ALIVE: "-1"/' compose.yaml
docker compose up -d
```

The heartbeat timer also reloads the model after a reboot. Check the result:

```bash
sudo lab-status      # "Memory used" should be above 20%, with no yellow warning
```

> We don't run fake "busy" programs to trick Oracle. Real services and a loaded model are honest usage, and the lab will only get busier as we add n8n and Jarvis.

---

## Part G — Restoring for real (if disaster happens)

If the VM is ever lost:

1. Create a new VM (Lesson 01) and run Lessons 02, 03 and 05.
2. **First** put your saved encryption password on the new server, so the installer reuses the existing backups instead of creating a new, empty repository:
   ```bash
   sudo install -d -m 700 /etc/free-ai-lab
   sudo sh -c 'umask 077; echo RESTIC_PASSWORD=\"YOUR-SAVED-PASSWORD\" >> /etc/free-ai-lab/backup.env'
   ```
   Then run `sudo bash 08-install-backup.sh` and enter the **same** endpoint, bucket and keys. It should say *"Repository already exists and the password matches."*
3. Restore everything to its original place:
   ```bash
   sudo sh -c 'set -a; . /etc/free-ai-lab/backup.env; restic -o s3.region=$S3_REGION restore latest --target /'
   ```
4. Start the stacks: `cd ~/lab/ai && docker compose up -d`, then the same for `~/lab/autoheal` and `~/lab/gateway`.
5. Download the model again: `docker exec ollama ollama pull llama3.2:3b`.

Your chats, settings and keys are back.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| `Could not create the repository` | Re-check endpoint, bucket, region and both keys. The region must be your **home region** |
| `wrong password or no key found` | The encryption password in `backup.env` doesn't match the repository. Use the saved one |
| `403 Forbidden` from Object Storage | The Customer Secret Key is wrong or was deleted. Make a new one (Part C) |
| Open WebUI is down after a backup | Should never stay down (the script restarts it). Run `docker start open-webui` and check `journalctl -u lab-backup` |
| healthchecks.io shows "late" | Check `systemctl list-timers 'lab-*'` and `journalctl -u lab-heartbeat -n 20` |

---

## Checklist

- [ ] Created the bucket and key in Cloud Shell; secret key saved in a password manager
- [ ] Ran `08-install-backup.sh`; saw **Backup OK** and **RESTORE TEST PASSED**
- [ ] Backup encryption password saved in a password manager
- [ ] Two healthchecks.io checks created and their URLs added
- [ ] Set `OLLAMA_KEEP_ALIVE` to `-1`; `sudo lab-status` shows memory above 20%
- [ ] Wrote today's notes in `PROGRESS.md` (no keys, passwords or ping URLs)

## Check your understanding

1. Why must backups live *off* the VM?
2. Why does the backup pause Open WebUI for a few seconds?
3. What happens if you lose the backup encryption password?
4. How does a "dead man's switch" tell you the server is down, when the server itself can't?
5. Which three conditions make Oracle treat an A1 VM as idle, and which one do we keep above 20%?

## Next

**Lesson 09 — n8n basics**: the automation engine that becomes Jarvis's nervous system.
