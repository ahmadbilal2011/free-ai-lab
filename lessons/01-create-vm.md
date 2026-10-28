# Lesson 01 — Create the Oracle VM safely

**Goal:** have one Ubuntu server running on Oracle Always Free, and log into it from Windows using an SSH key.

**Time:** about 30–45 minutes (longer if Oracle says "out of capacity").

**Cost:** $0. The account is Always Free (not upgraded to Pay As You Go), so Oracle cannot charge for resources outside the free limits; it simply refuses to create them.

---

## Part A — Understand what we're creating

| Setting | Our choice | Why |
|---|---|---|
| Image (OS) | Canonical Ubuntu 24.04 (aarch64 / Arm build) | Long-term-support Ubuntu, works on Arm |
| Shape | `VM.Standard.A1.Flex` (Ampere, Arm) | The only free shape strong enough for AI |
| OCPU / RAM | **2 OCPU / 12 GB** | The full Always Free A1 allowance, not a bit more |
| Boot volume | **100 GB** | Room for AI models (each 2–5 GB) while leaving ~100 GB of the 200 GB free storage for later |
| Network | New VCN with a public subnet, public IPv4 | So we can SSH in for the first time |
| Login | SSH key (no password) | Safest login method (see Lesson 00) |

> **One VM only.** All 2 OCPU / 12 GB go into this single server. If you ever create a second A1 instance, the two together must still stay within 2 OCPU / 12 GB.

---

## Part B — Create your SSH key on Windows

Windows 10 and 11 include OpenSSH, so nothing needs installing.

1. Press **Start**, type **PowerShell**, and open **Windows PowerShell** (normal user, not Administrator).
2. Check SSH exists:
   ```powershell
   ssh -V
   ```
   You should see something like `OpenSSH_for_Windows_9.x`.
3. Create the key pair:
   ```powershell
   ssh-keygen -t ed25519 -f $HOME\.ssh\oci_free_ai_lab -C "free-ai-lab"
   ```
   - `-t ed25519` → modern, secure key type
   - `-f ...` → where to save it, with a clear name
   - `-C ...` → a label so you recognise the key later
   - When asked for a **passphrase**, type one you'll remember. It protects the key if your laptop is stolen. (Nothing appears while typing; that's normal.)
4. This creates two files in `C:\Users\<you>\.ssh\`:
   - `oci_free_ai_lab` → **private key. Never share it. Never upload it. Never commit it.**
   - `oci_free_ai_lab.pub` → public key, the one Oracle gets.
5. Show the public key so you can copy it:
   ```powershell
   Get-Content $HOME\.ssh\oci_free_ai_lab.pub
   ```
   It's one line starting with `ssh-ed25519`. Copy the whole line.

---

## Part C — Option 1 (recommended): one command in Oracle Cloud Shell

**Cloud Shell** is a free Linux terminal inside the Oracle Console. It's already signed in to your account and has the `oci` command-line tool installed, so there's nothing to set up.

Our script [`scripts/create-free-vm.sh`](../scripts/create-free-vm.sh) does everything from Part A for you:

1. Checks you're in your **home region** (Always Free only exists there)
2. Checks you're still **inside the free limits** (A1 CPU/RAM and 200 GB storage) and refuses to continue if you're not
3. Creates the network: VCN → internet gateway → route → public subnet (only SSH port 22 is open)
4. Finds the newest **Ubuntu 24.04 Arm** image
5. Creates the VM with **2 OCPU / 12 GB / 100 GB** and your SSH public key
6. If Oracle is **out of capacity**, waits 60 seconds and tries again (up to 30 times)
7. Prints your public IP and the exact `ssh` command to connect

It's safe to run again: it reuses what already exists and stops if the VM is already there.

### Steps

1. Sign in at <https://cloud.oracle.com> and check the region (top right) is your **home region**.
2. Click the **Cloud Shell** icon `>_` at the top right (or **Developer tools → Cloud Shell**). Wait until you see a `$` prompt.
3. Paste this **one line**, but first replace the text inside the quotes with **your public key** from Part B, step 5:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/create-free-vm.sh -o create-free-vm.sh && SSH_PUBLIC_KEY="PASTE-YOUR-ssh-ed25519-LINE-HERE" bash create-free-vm.sh
   ```

   - `curl ... -o create-free-vm.sh` → downloads the script from this repo
   - `SSH_PUBLIC_KEY="..."` → hands it your **public** key (never the private one; the script refuses if you paste a private key)
   - `bash create-free-vm.sh` → runs it

4. Wait. Without capacity problems it takes about 2–4 minutes. At the end you'll see:

   ```
   ==> Done! Your Always Free VM is RUNNING
   Public IP: x.x.x.x
   ```

   Then jump to **Part D**.

> **Good habit:** never run a script from the internet without knowing what it does. Before running, you can read it in Cloud Shell with `less create-free-vm.sh` (press `q` to quit), or read it on GitHub.

> **Cloud Shell closes after about 20 minutes of no typing.** If that happens during capacity retries, just reopen it and run `SSH_PUBLIC_KEY="..." bash create-free-vm.sh` again.

---

## Part C — Option 2: create it by clicking in the Console

Use this if you prefer to see every setting yourself. The result is the same as Option 1.

1. Sign in at <https://cloud.oracle.com>. Make sure the region shown at the top right is your **home region**.
2. Open the menu (☰) → **Compute** → **Instances** → **Create instance**.
3. **Name:** `free-ai-lab`
4. **Placement:** leave the default availability domain.
5. **Image and shape** → **Edit**:
   - **Change image** → **Ubuntu** → **Canonical Ubuntu 24.04**. Select it, then confirm.
   - **Change shape** → **Virtual machine** → **Ampere** → `VM.Standard.A1.Flex`.
   - Set **OCPUs = 2** and **Memory = 12 GB**. Look for the **Always Free-eligible** label.
   - After choosing the Ampere shape, double-check the image is the **aarch64** Ubuntu build. The console normally switches it automatically.
6. **Networking:**
   - Choose **Create new virtual cloud network** and **Create new public subnet** (defaults are fine).
   - Make sure **Assign a public IPv4 address** is **on**.
7. **Add SSH keys:** choose **Paste public keys** and paste the `ssh-ed25519 ...` line from Part B.
8. **Boot volume:** tick **Specify a custom boot volume size** → **100** GB. Leave encryption at the default.
9. Click **Create**.

The status goes **PROVISIONING** → **RUNNING** in a minute or two. On the instance page, copy the **Public IP address**.

> **Do not commit the public IP to GitHub.** In notes we write `<SERVER_IP>` instead.

### If you see "Out of host capacity"

This is common and not your fault: Oracle's free Arm servers in your region are full right now.

- Try again after 30–60 minutes, or late at night / early morning Saudi time.
- If your region offers more than one availability domain, try another one in **Placement**.
- Keep 2 OCPU / 12 GB; don't go above the free limit to "get around" it (it won't help, and Always Free won't allow it).

Write down each attempt in `PROGRESS.md`. It's part of the real learning.

---

## Part D — First login from Windows

In PowerShell:

```powershell
ssh -i $HOME\.ssh\oci_free_ai_lab ubuntu@<SERVER_IP>
```

- `-i` → which private key to use
- `ubuntu` → the default username on Oracle's Ubuntu images
- First time only, it asks *"Are you sure you want to continue connecting?"* → type `yes`. This saves the server's fingerprint so you'd be warned if it ever changed.
- Enter your key passphrase.

You're in when the prompt looks like:

```
ubuntu@free-ai-lab:~$
```

Run these to check the server matches what we ordered:

```bash
uname -m      # should print aarch64  (Arm)
nproc         # should print 2        (CPUs)
free -h       # Mem total ~11Gi        (12 GB minus system reserve)
df -h /       # Size ~97G              (100 GB boot disk)
```

Type `exit` to leave the server.

### Optional shortcut: an SSH config entry

So you can type `ssh free-ai-lab` instead of the long command, create the file `C:\Users\<you>\.ssh\config` (no file extension) with:

```
Host free-ai-lab
    HostName <SERVER_IP>
    User ubuntu
    IdentityFile ~/.ssh/oci_free_ai_lab
```

Open it from PowerShell with `notepad $HOME\.ssh\config`. If Notepad adds `.txt`, rename the file to remove it.

---

## Part E — What we have NOT done yet (on purpose)

- No software installed yet
- No extra ports opened (only SSH, port 22, is open by Oracle's default rules)
- No updates or hardening yet; that's Lesson 02

---

## Checklist

- [ ] SSH key created on Windows, passphrase set
- [ ] Instance `free-ai-lab` RUNNING with 2 OCPU / 12 GB, Ubuntu 24.04 aarch64, 100 GB disk
- [ ] Logged in with `ssh` and verified with `uname -m`, `nproc`, `free -h`, `df -h /`
- [ ] Wrote today's notes in `PROGRESS.md` (no IPs, no keys)

## Check your understanding

1. Which of your two key files goes to Oracle, and which must never leave your laptop?
2. Why did we choose 100 GB and not the full 200 GB?
3. What does "Out of host capacity" mean, and what is the right response?

## Next

**Lesson 02 — Secure SSH access, updates and firewall.**
