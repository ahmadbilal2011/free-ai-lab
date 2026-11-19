# Lesson 08 — Backups and monitoring

**Goal:** never lose Jarvis's keys, settings and (soon) workflows, and get an **email** if the server or a backup stops working.

**Time:** about 30 minutes.

**Cost:** $0. Oracle Always Free Object Storage (20 GB), restic (open source), healthchecks.io free plan.

**Before you start:** Lessons 05–07 are done (`docker ps` shows `bifrost`, `n8n`, `autoheal`).

**Status:** ⚠️ Written, not installed on the current server yet. **Do this next**: the server now holds n8n workflows, credentials and Bifrost's keys.

---

## Part A — Why now?

Everything Jarvis has lives on **one** server. If it breaks, gets deleted by mistake, or Oracle reclaims it, you lose Bifrost's provider keys, every n8n workflow and credential, the Telegram bot setup, everything Jarvis learns. Before Jarvis gets more of your life, we protect it.

Backups must be:

| Rule | How |
|---|---|
| **Off the server** | Oracle **Object Storage**: a separate storage service, not the server's disk |
| **Encrypted** | **restic** encrypts everything *before* it leaves the server; Oracle only sees scrambled data |
| **Automatic** | A timer runs every night at 03:30 |
| **Tested** | `lab-restore-test` really restores the latest backup and checks the files |
| **Watched** | **healthchecks.io** emails you if a night's backup doesn't report "OK" |

> A backup you've never restored is just a hope. We test the restore on day one.

## Part B — What gets backed up

| Included | Why |
|---|---|
| `~/lab/` (compose files, **`.env` keys**, Bifrost's data, n8n's data) | Rebuild every app exactly as it was |
| Every Docker volume, including future ones | Picked up automatically, nothing to remember |

**Consistency:** n8n and Bifrost keep their data in SQLite database files, and copying one while it's being written can give a broken copy. So the backup **pauses them for a few seconds** at 03:30 and starts it again right after, even if the backup fails. (Telegram retries webhook messages, so nothing sent in those seconds is lost.)

**Retention:** 7 daily + 4 weekly + 6 monthly snapshots. restic stores only what changed (**deduplication**), so it stays small.

### The two secrets you must keep safe

| Secret | What it is | If you lose it |
|---|---|---|
| Oracle **Secret key** | Lets the server write to the bucket | Make a new one. No data lost |
| **Backup encryption password** | Unlocks your backups | **The backups are useless forever.** Nobody can recover it, not even Oracle |

Both are stored on the server in `/etc/free-ai-lab/backup.env` (root only). **But if the server dies, that file dies with it.** Keep a copy in a **password manager** (Bitwarden is free). Never on GitHub, never in a chat.

## Part C — Create the backup storage (Oracle Cloud Shell)

Open **Cloud Shell** in the Oracle Console (as in Lesson 01), then:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/08-create-backup-bucket.sh -o 08-create-backup-bucket.sh && bash 08-create-backup-bucket.sh
```

It creates a **private** bucket `free-ai-lab-backups` and an **S3-compatible key pair** ("Customer Secret Key"), then prints:

```
  S3 endpoint : https://<namespace>.compat.objectstorage.me-riyadh-1.oci.customer-oci.com
  Bucket      : free-ai-lab-backups
  Region      : me-riyadh-1
  Access key  : ...
  Secret key  : ...   ← shown only once
```

Copy the **Secret key** into your password manager now, then type `clear`.

**Coming from the first version of the course?** The script finds the old bucket and offers to **delete the old backups** in it (their password went with the old server settings, so they can't be restored any more). Answer **Y**. It also replaces the old access key: answer **N** when it asks if you still have the old secret, unless you really do.

> **S3-compatible** means Oracle's storage speaks the same "language" as Amazon S3, so tools like restic work with it unchanged.

## Part D — Install backups on the server

On the server:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/08-install-backup.sh -o 08-install-backup.sh && sudo bash 08-install-backup.sh
```

1. Installs **restic**.
2. Asks for the 5 values from Part C (the secret key is typed hidden).
3. Asks for two **healthchecks.io** URLs. Press **Enter** to skip for now; you'll add them in Part E.
4. Creates the encrypted repository and **shows the backup encryption password once**. Save it in your password manager, then type `SAVED`.
5. Installs four commands and two timers.
6. Runs the **first backup** and a **restore test**.

You should end with:

```
Backup OK
...
  OK    /home/ubuntu/lab/autoheal/compose.yaml
  OK    /home/ubuntu/lab/gateway/compose.yaml
  OK    /home/ubuntu/lab/jarvis/.env
  OK    /home/ubuntu/lab/jarvis/n8n/database.sqlite
RESTORE TEST PASSED
```

Sources: [`08-create-backup-bucket.sh`](../scripts/08-create-backup-bucket.sh), [`08-install-backup.sh`](../scripts/08-install-backup.sh)

### Your new commands

| Command | What it does |
|---|---|
| `sudo lab-status` | One screen: containers and health, memory, disk, Tailscale, last backup, alerts |
| `sudo lab-backup` | Back up right now (e.g. before a risky change) |
| `sudo lab-restore-test` | Prove the latest backup restores (do it once a month) |
| `systemctl list-timers 'lab-*'` | When the next backup and heartbeat run |
| `journalctl -u lab-backup -n 50` | Log of the last backup |

## Part E — Monitoring: an email when something stops

A monitor running *on* the server can't tell you the server is down. So we use a **dead man's switch**: the server says "I'm alive" to an outside service every 5 minutes. If the messages **stop**, that service emails you.

[healthchecks.io](https://healthchecks.io) (open source, free hosted plan) does exactly this.

1. Sign up at <https://healthchecks.io> (email only). Coming from v1? Reuse your account and the two old checks: just **resume** them.
2. Check **`jarvis heartbeat`**: **Period 5 minutes**, **Grace 10 minutes**. Copy its ping URL (`https://hc-ping.com/…`).
3. Check **`jarvis backup`**: **Period 1 day**, **Grace 2 hours**. Copy its ping URL.
4. On the server, run `sudo bash 08-install-backup.sh` again. Press **Enter** to keep everything else and paste the two URLs.

| Event | What you get |
|---|---|
| Server off / crashed / reclaimed / no network | Email about 15 minutes later ("heartbeat is DOWN") |
| Nightly backup failed or didn't run | Email |
| Everything fine | Silence, and a green dashboard |

> A ping URL works like a password for that check (anyone with it could send fake "I'm alive" pings). Keep it off GitHub.

Later (Lesson 18) these alerts also reach you on **Telegram**.

## Part F — Staying clear of Oracle's idle rule

Oracle may **reclaim** an Always Free VM it considers idle. An A1 VM counts as idle if, over **7 days**, CPU (95th percentile), network **and** memory all stay below 20% ([Oracle's Always Free docs](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm)). All three must be true, so keeping **memory above 20%** with real work protects us.

Check where you stand:

```bash
sudo lab-status      # "Memory used": a yellow warning appears below 20%
```

Real services (the SAR site, n8n, Bifrost, Telegram traffic, scheduled workflows) are the honest way to stay above
the line. As of 2026-11 memory use was around 11%, so network and CPU activity from real work matter too, and the
server should keep doing useful, scheduled jobs. We don't run fake "busy" programs to trick Oracle.

## Part G — Restoring for real (if disaster happens)

If the server is ever lost:

1. Create a new server (Lesson 01) and run Lessons 02 and 03.
2. **First** put your saved encryption password on the new server, so the installer reuses the existing backups instead of creating a new, empty repository:
   ```bash
   sudo install -d -m 700 /etc/free-ai-lab
   sudo sh -c 'umask 077; echo RESTIC_PASSWORD=\"YOUR-SAVED-PASSWORD\" >> /etc/free-ai-lab/backup.env'
   ```
   Then `sudo bash 08-install-backup.sh` with the **same** endpoint, bucket and keys. It should say *"Repository already exists and the password matches."*
3. Restore everything to its original place:
   ```bash
   sudo sh -c 'set -a; . /etc/free-ai-lab/backup.env; restic -o s3.region=$S3_REGION restore latest --target /'
   ```
4. Start the apps again: `bash 05-install-gateway.sh`, then `bash 06-install-n8n.sh` (without `--fresh`: the restored data and keys are reused).

## If something goes wrong

| Problem | Fix |
|---|---|
| `No .../lab/jarvis found` | Do Lessons 05–06 first |
| `Could not create the repository` | Re-check endpoint, bucket, region and both keys. The region must be your **home region** |
| `wrong password or no key found` | The password in `backup.env` doesn't match the repository. Use the saved one (Part G) |
| `403 Forbidden` from Object Storage | The secret key is wrong or deleted. Run Part C again for a new one |
| Cloud Shell: `Could not create the key (each user can have at most 2)` | Delete an unused one: Console → your profile → **Customer secret keys** |
| n8n is down after a backup | It shouldn't stay down (the job always restarts it): `docker start n8n` and check `journalctl -u lab-backup` |
| healthchecks.io shows "late" | `systemctl list-timers 'lab-*'` and `journalctl -u lab-heartbeat -n 20` |

## Checklist

- [ ] Bucket and key created in Cloud Shell; secret key in a password manager
- [ ] `08-install-backup.sh` finished with **Backup OK** and **RESTORE TEST PASSED**
- [ ] Backup encryption password in a password manager
- [ ] Two healthchecks.io checks created, URLs added; `sudo lab-status` shows alerts **on**
- [ ] Checked memory in `sudo lab-status` (see Part F)

## Check your understanding

1. Why must backups live *off* the server?
2. Why does the backup pause n8n for a few seconds?
3. What happens if you lose the backup encryption password?
4. How does a dead man's switch tell you the server is down, when the server itself can't?
5. Which three conditions make Oracle treat an A1 VM as idle?

## Next

**Lesson 09 — Jarvis Live** (planned), or the next automation: SAR→PKR rate alert, new SAR request alert, morning summary.
