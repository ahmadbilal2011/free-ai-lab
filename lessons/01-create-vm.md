# Lesson 01 — Create the Oracle VM safely

**Goal:** have one Ubuntu server running on Oracle Always Free, log into it as user `ubuntu`, first from Oracle Cloud Shell and then from your Windows laptop.

**Time:** about 15–30 minutes (longer if Oracle says "out of capacity").

**Cost:** $0. The account is Always Free (not upgraded to Pay As You Go), so Oracle cannot charge for resources outside the free limits; it simply refuses to create them.

---

## Part A — Understand what we're creating

| Setting | Our choice | Why |
|---|---|---|
| Image (OS) | Canonical Ubuntu 24.04 (aarch64 / Arm build) | Long-term-support Ubuntu, works on Arm |
| Shape | `VM.Standard.A1.Flex` (Ampere, Arm) | The only free shape strong enough for AI |
| OCPU / RAM | **2 OCPU / 12 GB** | The full Always Free A1 allowance, not a bit more |
| Boot volume | **100 GB** | Room for AI models (each 2–5 GB) while leaving ~100 GB of the 200 GB free storage for later |
| Network | New VCN with a public subnet, public IPv4 | So we can SSH in |
| Username | `ubuntu` | The default admin user on Oracle's Ubuntu images |
| Login | SSH key (no password) | Safest login method (see Lesson 00) |

> **One VM only.** All 2 OCPU / 12 GB go into this single server. If you ever create a second A1 instance, the two together must still stay within 2 OCPU / 12 GB.

### Where does the SSH key come from?

The script creates the key pair **inside your Oracle Cloud Shell**, so you don't need to prepare anything:

- `~/.ssh/free-ai-lab` → **private key** (the secret). Stays in your Cloud Shell; you download one copy to your laptop.
- `~/.ssh/free-ai-lab.pub` → **public key**. Put on the VM automatically.

The key type is **RSA 4096**: Oracle Cloud Shell runs in a strict security mode (FIPS) that doesn't allow the newer ED25519 type.

Your Cloud Shell storage is private to your Oracle account. Oracle's own Console works the same way with its "Generate a key pair for me" button. Treat the downloaded file like a house key: **never share it, never upload it, never commit it to GitHub.**

---

## Part B — Create the VM with one command (Cloud Shell)

**Cloud Shell** is a free Linux terminal inside the Oracle Console. It's already signed in to your account and has the `oci` command-line tool installed.

Our script [`scripts/create-free-vm.sh`](../scripts/create-free-vm.sh) does all of Part A:

1. Creates the SSH key pair (or reuses it if it already exists)
2. Checks you're in your **home region** (Always Free only exists there)
3. Checks you're still **inside the free limits** (A1 CPU/RAM and 200 GB storage) and refuses to continue if you're not
4. Creates the network: VCN → internet gateway → route → public subnet (only SSH port 22 is open)
5. Finds the newest **Ubuntu 24.04 Arm** image
6. Creates the VM with **2 OCPU / 12 GB / 100 GB**, user `ubuntu`
7. If Oracle is **out of capacity**, waits 60 seconds and tries again (up to 30 times)
8. Prints your public IP and the exact commands to connect

It's safe to run again: it reuses what already exists and stops if the VM is already there.

### Steps

1. Sign in at <https://cloud.oracle.com> and check the region (top right) is your **home region**.
2. Click the **Cloud Shell** icon `>_` at the top right (or **Developer tools → Cloud Shell**). Wait until you see a `$` prompt.
3. Copy and paste this **one line**, then press Enter:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/create-free-vm.sh -o create-free-vm.sh && bash create-free-vm.sh
   ```

   - `curl ... -o create-free-vm.sh` → downloads the script from this repo
   - `bash create-free-vm.sh` → runs it

4. Wait. Without capacity problems it takes about 2–4 minutes. At the end you'll see something like:

   ```
   ==> Done! Your Always Free VM is RUNNING
   Username:  ubuntu
   Public IP: x.x.x.x

   1) Connect right now from this Cloud Shell:
        ssh -i ~/.ssh/free-ai-lab ubuntu@x.x.x.x
   ```

> **Good habit:** never run a script from the internet without knowing what it does. You can read it first on GitHub, or in Cloud Shell with `less create-free-vm.sh` (press `q` to quit).

> **Cloud Shell closes after about 20 minutes of no typing.** If that happens during capacity retries, reopen it and run `bash create-free-vm.sh` again. It continues where it left off.

### If you see "out of capacity" many times

This is common and not your fault: Oracle's free Arm servers in your region are full right now.

- Let the script keep retrying, or run it again later. Late night / early morning Saudi time often works best.
- Don't raise OCPU/RAM above the free limit to "get around" it. It won't help, and Always Free won't allow it.

Write down each attempt in `PROGRESS.md`. It's part of the real learning.

> **Do not commit the public IP to GitHub.** In notes we write `<SERVER_IP>` instead.

---

## Part C — First login, from Cloud Shell

Copy the `ssh` line the script printed, for example:

```bash
ssh -i ~/.ssh/free-ai-lab ubuntu@<SERVER_IP>
```

- `-i` → which private key to use
- `ubuntu` → the username
- First time only, it asks *"Are you sure you want to continue connecting?"* → type `yes`. This saves the server's fingerprint so you'd be warned if it ever changed.

You're in when the prompt looks like:

```
ubuntu@free-ai-lab:~$
```

Check the server matches what we ordered:

```bash
uname -m      # should print aarch64  (Arm)
nproc         # should print 2        (CPUs)
free -h       # Mem total ~11Gi        (12 GB minus system reserve)
df -h /       # Size ~97G              (100 GB boot disk)
```

Type `exit` to leave the server and return to Cloud Shell.

> If `ssh` waits a long time and then says "Connection timed out", the VM may still be booting. Wait 1–2 minutes and try again.

---

## Part D — Log in from your Windows laptop

Cloud Shell is handy, but for daily work you'll want to connect from your own PC.

### 1. Download the private key from Cloud Shell

1. In Cloud Shell, click the **gear / settings icon** (top right of the Cloud Shell window) → **Download**.
2. Type the file path the script printed, for example `/home/<your-name>/.ssh/free-ai-lab`, and click **Download**.
3. Your browser saves a file named `free-ai-lab` (no extension) in your **Downloads** folder.

### 2. Move it to the right place and lock it down

Windows' SSH refuses keys that other users on the PC could read ("UNPROTECTED PRIVATE KEY FILE"). These commands move the key and make it readable only by you.

Open **Windows PowerShell** (Start → type PowerShell) and run these one by one:

```powershell
# make the .ssh folder if it doesn't exist
New-Item -ItemType Directory -Force $HOME\.ssh

# move the key from Downloads into .ssh
Move-Item $HOME\Downloads\free-ai-lab $HOME\.ssh\free-ai-lab

# remove inherited permissions, then give read access only to you
icacls $HOME\.ssh\free-ai-lab /inheritance:r
icacls $HOME\.ssh\free-ai-lab /grant:r "$($env:USERNAME):(R)"
```

### 3. Connect

```powershell
ssh -i $HOME\.ssh\free-ai-lab ubuntu@<SERVER_IP>
```

Type `yes` the first time, then run the same four check commands from Part C.

### Optional: add a passphrase to your laptop copy

The script creates the key without a passphrase so beginners aren't blocked. To protect your laptop copy with a password (recommended):

```powershell
ssh-keygen -p -f $HOME\.ssh\free-ai-lab
```

### Optional shortcut: an SSH config entry

So you can type `ssh free-ai-lab` instead of the long command, run `notepad $HOME\.ssh\config` and add:

```
Host free-ai-lab
    HostName <SERVER_IP>
    User ubuntu
    IdentityFile ~/.ssh/free-ai-lab
```

Save it. If Notepad adds `.txt` to the name, rename the file to just `config`.

---

## Part E — Other ways (optional)

### Advanced: use a key you created on your own laptop

Some people prefer the private key to be created on their PC and never exist anywhere else. That's slightly more secure.

1. In PowerShell: `ssh-keygen -t ed25519 -f $HOME\.ssh\oci_free_ai_lab -C "free-ai-lab"`
2. Show and copy the public key: `Get-Content $HOME\.ssh\oci_free_ai_lab.pub`
3. In Cloud Shell, pass it to the script:
   ```bash
   SSH_PUBLIC_KEY="ssh-ed25519 AAAA...your-key... free-ai-lab" bash create-free-vm.sh
   ```
   The script refuses if you paste a *private* key by mistake.
4. Connect from Windows with `ssh -i $HOME\.ssh\oci_free_ai_lab ubuntu@<SERVER_IP>`.

### Clicking through the Console instead of the script

Menu (☰) → **Compute** → **Instances** → **Create instance**, then:

- **Name:** `free-ai-lab`
- **Image:** Ubuntu → Canonical Ubuntu 24.04 · **Shape:** Ampere → `VM.Standard.A1.Flex`, **2 OCPU / 12 GB** (look for "Always Free-eligible")
- **Networking:** create new VCN and public subnet, **Assign a public IPv4 address** on
- **SSH keys:** **Generate a key pair for me** → **Save private key** (this downloads the key to your laptop)
- **Boot volume:** custom size **100** GB → **Create**

Then continue with Part D, step 2, using the downloaded key file's name.

---

## Part F — What we have NOT done yet (on purpose)

- No software installed yet
- No extra ports opened (only SSH, port 22, is open by Oracle's default rules)
- No updates or hardening yet; that's Lesson 02

---

## Checklist

- [ ] Ran the one-line command in Cloud Shell
- [ ] Instance `free-ai-lab` RUNNING with 2 OCPU / 12 GB, Ubuntu 24.04 aarch64, 100 GB disk
- [ ] Logged in from Cloud Shell and verified with `uname -m`, `nproc`, `free -h`, `df -h /`
- [ ] Downloaded the key, locked its permissions, and logged in from Windows
- [ ] Wrote today's notes in `PROGRESS.md` (no IPs, no keys)

## Check your understanding

1. Which key file is on the VM, and which one must you never share?
2. Why did we run `icacls` on the key in Windows?
3. Why did we choose 100 GB and not the full 200 GB?
4. What does "Out of host capacity" mean, and what is the right response?

## Next

**Lesson 02 — Secure SSH access, updates and firewall.**
