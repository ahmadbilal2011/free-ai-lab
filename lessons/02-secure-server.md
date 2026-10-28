# Lesson 02 — Secure SSH access, updates and firewall

**Goal:** make the server safe before we install anything on it.

**Time:** about 10–15 minutes.

**Cost:** $0.

---

## Part A — Why this matters

The moment a server gets a public IP, automated bots start knocking. They try common usernames and passwords on SSH all day, every day. You can see it yourself:

```bash
sudo journalctl -u ssh --since "1 hour ago" | grep -c "Invalid user"
```

That number is strangers trying to get in. Our job is to make sure they never can.

## Part B — What we'll do, and why

| # | Step | What it means | Why |
|---|---|---|---|
| 1 | **Updates** | Install the latest fixes for Ubuntu and its packages | Most break-ins use bugs that are already fixed. Updating closes them. |
| 2 | **Automatic security updates** | `unattended-upgrades` installs security fixes every day by itself | You won't always remember to update. |
| 3 | **SSH hardening** | Keys only, no passwords; no direct `root` login; max 3 attempts per connection | Bots guess passwords; they can't guess a 4096-bit key. Root is the account every bot targets. |
| 4 | **fail2ban** | Watches SSH logins; an IP that fails 5 times in 10 minutes is blocked for 1 hour | Slows attackers down and keeps the logs quiet. |
| 5 | **Swap (4 GB)** | Disk space the system can use as emergency memory | AI models are memory-hungry. Without swap, running out of RAM kills programs. With it, things just slow down. |
| 6 | **Timezone** | Set to `Asia/Riyadh` | Logs and schedules show your local time. |
| 7 | **Firewall check** | Confirm only SSH (port 22) is open | Fewer open doors = fewer ways in. |

### About the firewall on Oracle

Remember from Lesson 00: Oracle has **two** firewall layers.

1. **Security List** (in the cloud, outside the VM): the script in Lesson 01 left only SSH (22) open.
2. **iptables** (inside the VM): Oracle's Ubuntu images come with rules that allow SSH and **reject everything else**.

Many Ubuntu guides tell you to use **UFW** (a simpler firewall tool). **Don't use UFW on Oracle images.** Oracle warns that it can conflict with their built-in iptables rules and can even stop the instance from booting properly. We keep Oracle's rules and only check them.

Later, we'll use **Tailscale** (Lesson 05) so the AI apps never need a public port at all.

### Swap: a closer look

Swap is like a spare room: slower than RAM, but it stops a crash when RAM is full. We also set **swappiness = 10**, which tells Linux "use real RAM first; only touch swap when you really have to." The 4 GB comes from your 100 GB disk.

---

## Part C — Run the script

1. Log in to your VM (from Cloud Shell or Windows), as in Lesson 01.
2. Paste this one line:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/02-secure-server.sh -o 02-secure-server.sh && sudo bash 02-secure-server.sh
   ```

   - `sudo` → run as administrator (needed to change system settings)
   - The `ubuntu` user can use `sudo` without a password on Oracle images

3. It runs through 7 steps and ends with a **Summary**.

### Safety built into the script

- It **checks your SSH key exists** before turning off passwords. If no key is found, it stops so you can't lock yourself out.
- It **tests the SSH config** (`sshd -t`) before applying it. If the test fails, it undoes the change.
- Your current SSH session **stays connected** while SSH settings change.

---

## Part D — Test before you close anything ⚠️

This is the most important habit in server work: **after changing SSH, always test a new login before closing the old one.** If something went wrong, the open window is your way back in to fix it.

1. **Keep your current SSH window open.**
2. Open a **new** PowerShell window (or a new Cloud Shell tab) and log in again:
   ```powershell
   ssh -i $HOME\.ssh\free-ai-lab ubuntu@<SERVER_IP>
   ```
3. Works? 🎉 You can close the old window.

### Reboot if the summary asked for it

Some updates (like a new Linux kernel) only take effect after a restart:

```bash
sudo reboot
```

Your SSH window disconnects. Wait about 1 minute, then log in again.

---

## Part E — Check that it worked

Run these on the VM:

```bash
# 1. SSH settings in force (should show: passwordauthentication no, permitrootlogin no, maxauthtries 3)
sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin|maxauthtries) "

# 2. fail2ban is watching SSH
sudo fail2ban-client status sshd

# 3. Automatic updates are on (should print: active)
systemctl is-active unattended-upgrades

# 4. Swap is there (~4G)
free -h

# 5. Time is in Riyadh time
timedatectl | grep "Time zone"

# 6. Firewall: SSH allowed, everything else rejected
sudo iptables -L INPUT -n --line-numbers
```

### Useful commands for later

| Command | What it does |
|---|---|
| `sudo fail2ban-client status sshd` | How many IPs are banned right now |
| `sudo fail2ban-client set sshd unbanip <IP>` | Unban an IP (e.g. if you locked out yourself) |
| `sudo apt update && sudo apt upgrade` | Update manually anytime |
| `ls /var/run/reboot-required` | If the file exists, a reboot is needed |

---

## If something goes wrong

| Problem | Fix |
|---|---|
| New SSH window says `Permission denied (publickey)` | You still have the old window open: check the key path in your `ssh -i` command. Password login is now off on purpose. |
| Need to undo the SSH change (from the still-open window) | `sudo rm /etc/ssh/sshd_config.d/99-free-ai-lab.conf && sudo systemctl reload ssh` |
| Locked out completely | Unlikely: key login is never turned off, and your Cloud Shell key still works. If it happens anyway, nothing important is on the server yet: terminate the instance in the Console (**Instance → More actions → Terminate**, tick *permanently delete the boot volume*) and run the Lesson 01 script again. |
| You banned your own IP with fail2ban | Wait 1 hour, or log in from Cloud Shell (different IP) and run the `unbanip` command above |
| Script stopped with an error | Read the red `[x]` line. Running the script again is safe. |

---

## Checklist

- [ ] Ran `02-secure-server.sh` and saw the Summary
- [ ] Tested a **new** SSH login before closing the old one
- [ ] Rebooted if asked, and logged in again
- [ ] All 6 checks in Part E look right
- [ ] Wrote today's notes in `PROGRESS.md` (no IPs, no keys)

## Check your understanding

1. Why must you test a new SSH login before closing the old one?
2. Why don't we use UFW on Oracle's Ubuntu image?
3. What does fail2ban do when someone fails to log in 5 times?
4. What is swap, and why does it matter for running AI?

## Next

**Lesson 03 — Install and understand Docker.**
