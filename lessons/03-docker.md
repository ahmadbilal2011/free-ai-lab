# Lesson 03 — Install and understand Docker

**Goal:** install Docker on the VM, understand its core ideas, and run your first app with Docker Compose.

**Time:** about 20–30 minutes.

**Cost:** $0. Docker Engine is free and open source.

---

## Part A — Why Docker?

Without Docker, installing an app like Open WebUI means installing Python, the right library versions, a database, and so on, directly on the server. Two apps may need different versions of the same thing and break each other. Removing an app cleanly is hard.

With Docker, each app arrives as a **ready-made package** with everything it needs inside. It runs in its own box, can't break other apps, and can be removed in one command.

Every app in this lab (Ollama, Open WebUI, LiteLLM, n8n) will run in Docker.

## Part B — The 6 ideas you need

| Idea | What it is | Everyday comparison |
|---|---|---|
| **Image** | A read-only package: app + everything it needs | A recipe |
| **Container** | A running copy of an image | A meal cooked from the recipe |
| **Registry** | An online library of images (Docker Hub is the main one) | A recipe book shop |
| **Port mapping** | Connects a port on the server to a port inside the container | A door from the street into a specific room |
| **Volume** | A folder that lives *outside* the container, so data survives | A fridge: the meal is gone, the leftovers stay |
| **Docker Compose** | A file (`compose.yaml`) describing one or more containers and how to run them | A full menu written down, so anyone can cook it again |

Two key facts:

- **Containers are disposable.** Delete one and start a new one from the same image any time. That's how updates work.
- **Data must live in a volume.** Anything saved *only* inside a container is lost when the container is removed. Chats, AI models and tasks will all go in volumes.

### Ports and safety on our server

When you map a port, you choose **who can reach it**:

| You write | Who can reach it |
|---|---|
| `"8080:80"` | Anyone who can reach the server's IP (all network interfaces) |
| `"127.0.0.1:8080:80"` | **Only the server itself** |

On our VM, Oracle's cloud Security List still only allows SSH (22) from the internet, so nothing else is public either way. But a good habit is to **bind to `127.0.0.1` unless there's a reason not to**. In Lesson 05, Tailscale will let *your* devices in privately.

> Docker manages its own firewall (iptables) rules for container ports, separately from Oracle's INPUT rules we checked in Lesson 02. That's normal. We don't change them by hand.

### Arm reminder

Our VM is Arm (`aarch64`). Most popular images (nginx, Ollama, Open WebUI, LiteLLM, n8n) publish Arm versions, and Docker picks the right one automatically. If an image only exists for x86, it won't run here. We always check.

### The `docker` group: convenience with a warning

Normally Docker needs `sudo`. The script adds `ubuntu` to the `docker` group so you can type `docker` without `sudo`. Be aware: **anyone in the `docker` group effectively has full admin (root) power on the server.** That's fine here, because `ubuntu` is already the admin. Never add other users to this group casually.

---

## Part C — Install Docker (one command)

Log in to the VM, then paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/03-install-docker.sh -o 03-install-docker.sh && sudo bash 03-install-docker.sh
```

What the script does:

1. Removes old or unofficial Docker packages (Ubuntu's own `docker.io` can conflict)
2. Adds **Docker's official repository**, so you get current versions and security fixes
3. Installs Docker Engine, the CLI, containerd, Buildx and the **Compose** plugin
4. **Limits log size** to 3 × 10 MB per container. Without this, a chatty container's logs can slowly fill the disk
5. Adds `ubuntu` to the `docker` group
6. Tests with `hello-world` and checks containers can reach the internet

At the end you'll see a **Summary** with the Docker and Compose versions and `Architecture: aarch64`.

Then **log out and back in** (this activates the `docker` group):

```bash
exit
```

Log in again, and check:

```bash
docker ps
```

An empty table (just the headings `CONTAINER ID  IMAGE ...`) means it works, without `sudo`.

---

## Part D — Hands-on: your first containers

### 1. Run a single container

```bash
docker run -d --name web-test -p 127.0.0.1:8080:80 nginx:alpine
```

- `run` → create and start a container
- `-d` → "detached": run in the background
- `--name web-test` → give it a name
- `-p 127.0.0.1:8080:80` → server-only port 8080 → container port 80
- `nginx:alpine` → the image (`nginx` web server, `alpine` = small version)

Docker downloads (pulls) the image the first time. Now:

```bash
docker ps                       # it's running
curl -s localhost:8080 | head   # the nginx welcome page (HTML)
docker logs web-test            # what the container printed
```

Clean up:

```bash
docker stop web-test     # stop it
docker rm web-test       # delete the container (the image stays, for next time)
docker images            # list downloaded images
```

### 2. The same thing with Docker Compose (how we'll do everything from now on)

Typing long `docker run` commands is error-prone. A `compose.yaml` file writes it down once.

```bash
mkdir -p ~/lab/hello/html && cd ~/lab/hello
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/stacks/hello/compose.yaml -o compose.yaml
echo '<h1>Hello from my free AI lab!</h1>' > html/index.html
cat compose.yaml
```

Read the file. Every line has a comment explaining it:

```yaml
services:
  web:
    image: nginx:alpine
    container_name: hello-web
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped
```

Start it:

```bash
docker compose up -d
curl localhost:8080
```

You should see `<h1>Hello from my free AI lab!</h1>`, served from **your** `html` folder through the **volume**.

Prove that volumes keep data:

```bash
echo '<h1>Changed without touching the container</h1>' > html/index.html
curl localhost:8080            # shows the new text immediately

docker compose down            # removes the container completely
docker compose up -d           # a brand-new container
curl localhost:8080            # your page is still there: it lives in the volume
```

Finish:

```bash
docker compose down
cd ~
```

### Commands you'll use all the time

| Command | What it does |
|---|---|
| `docker ps` | Running containers (`docker ps -a` includes stopped ones) |
| `docker compose up -d` | Start the stack in the current folder |
| `docker compose down` | Stop and remove the stack's containers (volumes stay) |
| `docker compose logs -f` | Follow the logs (Ctrl+C to stop following) |
| `docker compose pull && docker compose up -d` | **Update** to the newest images |
| `docker stats` | Live CPU and RAM per container (Ctrl+C to exit) |
| `docker system df` | How much disk Docker uses |
| `docker image prune` | Delete unused old images to free disk |

---

## Our folder layout from now on

```
/home/ubuntu/lab/
├── hello/        ← this lesson's practice
├── ai/           ← Lesson 04: Ollama + Open WebUI
├── gateway/      ← Lesson 07: LiteLLM
└── jarvis/       ← Lesson 09+: n8n
```

Each folder holds one `compose.yaml`. The same files live in this repo under [`stacks/`](../stacks/), so the whole lab can be rebuilt from GitHub.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | You haven't logged out and back in since the install. Run `exit`, log in again. |
| `exec format error` | The image has no Arm build. Look for an `arm64` tag or a different image. |
| `port is already allocated` | Another container uses that port. `docker ps` to find it, then stop it or pick another port. |
| Script warned containers can't reach the internet | Send the full script output; we'll check the iptables rules together. |

---

## Checklist

- [ ] Ran `03-install-docker.sh`, Summary shows `Architecture: aarch64`
- [ ] Logged out and in; `docker ps` works without `sudo`
- [ ] Ran, tested and removed the `web-test` container
- [ ] Ran the `hello` stack with Compose and proved the volume keeps data
- [ ] Wrote today's notes in `PROGRESS.md`

## Check your understanding

1. What's the difference between an image and a container?
2. Why must app data live in a volume?
3. What's the difference between `"8080:80"` and `"127.0.0.1:8080:80"`?
4. Why is being in the `docker` group a big responsibility?

## Next

**Lesson 04 — Run my own AI: Ollama + Open WebUI.**
