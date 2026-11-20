# Lesson 08 — Backups: nightly .zip files on the server

**Goal:** never lose Jarvis's workflows, credentials and keys to a mistake, a bad update or a `--fresh` by accident.

**Time:** about 10 minutes. **Cost:** $0. Nothing outside the server is used.

**Before you start:** Lessons 05–07 are done (`docker ps` shows `bifrost` and `n8n`).

**Status:** ✅ Written. Run it next.

---

## Part A — What gets backed up, and how

Every night at **03:30** the server writes one zip file: `/data/backups/lab-YYYYMMDD-HHMM.zip`.

| In the zip | Why |
|---|---|
| `~/lab/` (compose files, **`.env` keys**, n8n's data, Bifrost's data) | Rebuild every app exactly as it was |
| Apache sites and fail2ban rules for n8n and Bifrost | The public doors and their locks |

| Left out | Why |
|---|---|
| Moved-aside folders (`n8n.old-*`, `brain.retired-*`, `.env.old-*`) | Old copies, not needed |
| The SAR calculator site | A separate project, untouched by this course |

- **Consistency:** n8n and Bifrost keep their data in SQLite database files, and copying one while it's being written
  can give a broken copy. So the backup **stops them for a few seconds** and starts them again right after, even if the
  backup fails. Telegram retries webhook messages, so nothing sent in those seconds is lost.
- **Retention:** the newest **14** zips are kept, so two weeks to go back to. Each is small (a few MB).
- **Privacy:** the zips contain your API keys, so `/data/backups` is readable by **root only**.

## Part B — The honest limit

| Protects against | Doesn't protect against |
|---|---|
| A deleted or broken workflow, a bad update, a wrong setting, `--fresh` by mistake | Losing the VM itself (Oracle reclaims it, the disk fails, the VM is deleted) |

The zips sit **on the same disk** as the data. So now and then (say monthly, and before big changes) **copy one to
your laptop** (Part D). That copy is what saves you if the server is ever lost.

## Part C — Install (one command)

On the server:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/08-install-backup.sh -o 08-install-backup.sh && sudo bash 08-install-backup.sh
```

It installs `zip`, creates `/data/backups` (root only), adds four commands and a nightly timer, then runs the
**first backup** and a **restore test**. You should end with:

```
Backup OK: /data/backups/lab-20261120-1405.zip (3.1M), 1 kept
Testing /data/backups/lab-20261120-1405.zip ...
  OK      /home/ubuntu/lab/gateway/compose.yaml
  OK      /home/ubuntu/lab/jarvis/compose.yaml
  OK      /home/ubuntu/lab/jarvis/.env
  OK      /home/ubuntu/lab/jarvis/n8n/database.sqlite
  ...
RESTORE TEST PASSED
```

Source: [`08-install-backup.sh`](../scripts/08-install-backup.sh)

### Your new commands

| Command | What it does |
|---|---|
| `sudo lab-status` | One screen: containers, memory, disk, last backup and its age |
| `sudo lab-backup` | Back up right now. Do it **before** any risky change |
| `sudo lab-restore-test` | Prove the newest zip opens and holds the key files (changes nothing) |
| `sudo lab-restore <zip>` | Put a backup back (Part E) |
| `sudo ls -lt /data/backups` | List the backups, newest first |

## Part D — Copy a backup to your laptop

On the **laptop**, in PowerShell (use your own key file and IP, as in Lesson 01):

```powershell
mkdir $HOME\jarvis-backups -Force
ssh -i $HOME\.ssh\oracle_key ubuntu@<server-ip> "sudo cat `$(sudo ls -1t /data/backups/lab-*.zip | head -1)" > $HOME\jarvis-backups\lab-latest.zip
```

- Open it in File Explorer to check it's a real zip.
- ⚠️ It contains your API keys. Keep it in a private folder, never on a USB stick you lend out, never in a shared drive.
  Rename it with the date if you keep several.

## Part E — Restoring

**Undo a mistake** (a workflow deleted, an update went wrong):

```bash
sudo ls -lt /data/backups              # pick the zip from before the mistake
sudo lab-restore /data/backups/lab-20261119-0330.zip
```

It asks you to type `RESTORE`. Then it:
1. Takes a safety backup of the current state.
2. Stops n8n and Bifrost.
3. Moves the current `~/lab` aside to `~/lab.before-restore-<date>`.
4. Unzips the backup with the original file owners.
5. Starts everything again.

Delete the `before-restore` folder once all is fine.

**New server** (the old one was lost):
1. Lessons 01–03 on a new server.
2. Copy your laptop's zip to it:
   ```powershell
   scp -i $HOME\.ssh\oracle_key $HOME\jarvis-backups\lab-latest.zip ubuntu@<new-ip>:
   ```
3. Run `sudo bash 08-install-backup.sh` (its first backup fails because nothing is installed yet, which is fine),
   then `sudo lab-restore ~/lab-latest.zip`.
4. Run `bash 05-install-gateway.sh` and `bash 06-install-n8n.sh` (**without** `--fresh`). They reuse the restored
   keys and data and set up Apache, HTTPS and fail2ban for the **new IP**: the `sslip.io` names change with the IP,
   so update Telegram (Lesson 07) by publishing the workflow again.

## Part F — Staying clear of Oracle's idle rule

Oracle may **reclaim** an Always Free VM it considers idle. An A1 VM counts as idle if, over **7 days**, CPU
(95th percentile), network **and** memory all stay below 20%
([Oracle's Always Free docs](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm)).

```bash
sudo lab-status      # "Memory used": a yellow note appears below 20%
```

Real services (the SAR site, n8n, Bifrost, Telegram traffic, scheduled workflows) are the honest way to stay above
the line. We don't run fake "busy" programs to trick Oracle. And this is exactly why **Part D matters**: if the VM
is ever reclaimed, only the copy on your laptop survives.

## If something goes wrong

| Problem | Fix |
|---|---|
| `No .../lab/jarvis found` | Do Lessons 05–06 first |
| `Less than 1 GB free` | `df -h /`, then `docker image prune -a` to remove old images |
| n8n is down after a backup | It shouldn't stay down (the job always restarts it): `docker start n8n bifrost` and check `journalctl -u lab-backup -n 30` |
| `Zip check FAILED` | Disk problem or full disk: `df -h /` and `sudo dmesg | tail` |
| After a restore, n8n says `EACCES` | `sudo chown -R 1000:1000 ~/lab/jarvis/n8n && docker restart n8n` |
| The laptop copy is 0 bytes | Wrong key or IP in the `ssh` command; test `ssh -i … ubuntu@<ip>` first |

## Checklist

- [ ] `08-install-backup.sh` finished with **Backup OK** and **RESTORE TEST PASSED**
- [ ] `sudo lab-status` shows the last backup
- [ ] One zip copied to the laptop (Part D) and kept private
- [ ] Reminder set: copy a fresh zip to the laptop monthly and before big changes

## Check your understanding

1. Why does the backup stop n8n and Bifrost for a few seconds?
2. Which problems do the zips on the server protect against, and which don't they?
3. Why must the zips (and the laptop copy) be kept private?
4. What does `lab-restore` do with your current data before restoring?

## Next

**Lesson 09 — Jarvis Live** (planned), or the next automation: SAR→PKR rate alert, new SAR request alert, morning summary.
