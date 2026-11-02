# Lesson 10 — Voice: talk to Jarvis, and hear it answer

**Goal:** send Jarvis a **voice note** on Telegram (Urdu, English or Arabic). It understands it, answers in text **and** sends a **voice note** back. Type, and it answers in text only.

**Time:** about 30 minutes: one installer on the server (the voice service), then the rest in the n8n UI.

**Cost:** $0. ElevenLabs free plan (10,000 credits a month), with free backups that switch in automatically.

**Before you start:** Lesson 09 works: Jarvis answers your typed messages on Telegram.

---

## Part A — Ears and a voice

```
 🎙️ your voice note ──► n8n ──► ears ("listen")  ──► text ──► brain ("smart") ──► answer
                                                                              │
 📱 Telegram ◄── text reply + 🔊 voice note ◄── voice ("speak") ◄──────────────┘
```

| Part | First choice | Automatic backup | Why |
|---|---|---|---|
| **Ears** (speech → text) | ElevenLabs **Scribe** | Groq **Whisper** | In the first version, Groq Whisper didn't understand my speech well; Scribe did |
| **Voice** (text → speech) | ElevenLabs **v3** | **Piper**, running on the server | Eleven v3 speaks Urdu well; Piper is free forever, a bit robotic |

**The rule:** type → text answer. Speak → text answer (showing what Jarvis heard) **plus** a voice note. Spoken answers are kept short (under ~60 words), because they cost credits and nobody wants a 3-minute voice note.

### The free plan, honestly

ElevenLabs' free plan gives **10,000 credits a month**, shared between ears and voice: roughly **30 minutes of listening or 10 minutes of speech**. It's for personal use. When credits run out, the backups take over by themselves (Groq for ears, Piper for voice) until next month. Free voice plans can only use ElevenLabs' **pre-made voices** through the API, not voices from its Voice Library.

**Privacy:** your voice notes go to ElevenLabs (or Groq). Neither uses them to train on API data by default, but they do leave the server. The Piper voice never leaves it.

## Part B — Your ElevenLabs key

1. Sign up at <https://elevenlabs.io> (free, no card).
2. **Developers → API Keys → Create API Key**. Name it `jarvis`. Under permissions, allow **Text to Speech** and **Speech to Text**.
3. Copy the **secret key**: it starts with **`sk_`** and is shown **only once**. (The *Key ID* shown in the list is not the key; I made that mistake in the first version.)

No key? Skip it: Jarvis then listens with Groq Whisper and speaks with Piper.

## Part C — Install the voice service (server, one command)

This is server setup (a new container), so it's done in the terminal. On the server, as `ubuntu`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/10-install-voice.sh -o 10-install-voice.sh && bash 10-install-voice.sh
```

1. Paste the `sk_…` key (hidden), or press Enter to skip.
2. The gateway gets two new aliases: **`listen`** (ears, with backup) and **`speak`** (voice).
3. The **voice service** is built: a tiny program with **no port at all**; only n8n can reach it, at `http://voice:5000`.
4. **Pick a voice** (pre-made only on the free plan): press Enter for George, or paste another ID from the list it shows.
5. Downloads the **Piper** backup voices (English, Arabic, Urdu).
6. **Round trip:** Jarvis speaks a sentence, then listens to its own recording. You want lines like:

```
  voice (cloud, ElevenLabs):     cloud
  voice (local, Piper backup):   local
  ears 'listen' heard:           Hello, this is Jarvis. My voice is working.
  ears 'listen-backup' heard:    Hello, this is Jarvis. My voice is working.
```

Sources: [`scripts/10-install-voice.sh`](../scripts/10-install-voice.sh), [`stacks/voice/`](../stacks/voice/)

## Part D — The voice version of the workflow (n8n UI)

The Telegram workflow gets new steps. Import the new version and move your settings over:

1. In n8n, open your current **Jarvis — Telegram chat** → **Settings** node → **copy** your `BOT_TOKEN` and `OWNER_ID` lines into a note for a minute. Then **Unpublish** it.
2. **Create workflow** → **⋯ → Import from URL…** →
   ```
   https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/stacks/jarvis/workflows/telegram-chat.json
   ```
3. **Settings** node → paste your token and owner ID.
4. Pick your OpenAI-type credential (Base URL `http://litellm:4000/v1`) in **two** nodes: **Ask Jarvis's brain** and **Listen (speech to text)**.
5. **Save → Publish**.
6. **Delete the old workflow** (Overview → ⋯ → Delete), so only one copy polls Telegram. Close the note without saving.

### What's new in the workflow

| Node | Job |
|---|---|
| **One item per message** | Sorts each message: text, voice note, too long (over 2 minutes), or other |
| **Voice note?** | Voice notes take the top path; text goes straight on |
| **Find the voice file** / **Download the voice note** | Fetches the audio from Telegram |
| **Name it .ogg** | Telegram calls the file `.oga`; speech services expect `.ogg` (same format) |
| **Listen (speech to text)** | Gateway alias `listen`: Scribe first, Whisper as backup |
| **Use what I heard** | The transcript becomes a normal message, marked "came in by voice" |
| **Prepare each message** | As before, plus: spoken questions get a short, speakable answer |
| **Final reply** | Text to show (with 🎙️ *"what I heard"* for voice notes) and text to speak |
| **Spoken to? Answer by voice too** | Only voice notes get a voice answer |
| **Speak** / **Send voice note** | The voice service makes an OGG voice note; Telegram sends it. If speaking fails, you still have the text |

## Part E — Try it

On your phone, in your Jarvis chat:

1. Hold the microphone and say, in Urdu: *"Jarvis, aaj ka din kaisay guzaarna chahiye?"*
2. You get a text: 🎙️ *"what Jarvis heard"* + the answer, then a **voice note** with the answer.
3. Type a question: text answer only.
4. Try English and Arabic too.

**Check it heard you right.** If the 🎙️ line is often wrong for your voice or accent, tell me: we can try the other ears first.

## Useful actions

| Task | How |
|---|---|
| Change the voice | `bash 10-install-voice.sh` again → Enter keeps the key → new voice ID |
| Check credits left | elevenlabs.io → your profile → Usage |
| Voice service health | `docker exec voice python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:5000/health').read().decode())"` |
| See why the cloud voice failed | `docker logs --tail 20 voice` |

## If something goes wrong

| Problem | Fix |
|---|---|
| Installer: `That doesn't start with 'sk_'` | You copied the Key ID. Create a new key and copy the secret (`sk_…`) |
| `voice (cloud): FAILED` with `paid_plan_required` / library voice | Use a **pre-made** voice ID (the list in the installer) |
| `voice (cloud): FAILED 401` | Key wrong, or missing the **Text to Speech** permission. Create a new key with both permissions |
| Voice note → "Sorry, I couldn't understand" | Ears failed: check `docker ps` shows `litellm (healthy)`; in n8n, is a credential selected in **Listen**? Speak clearly, under 2 minutes |
| Text reply arrives, no voice note | The voice service failed: `docker ps` shows `voice (healthy)`? `docker logs --tail 20 voice` |
| The voice sounds robotic | That's Piper: ElevenLabs credits are used up (or the key is missing). It switches back by itself next month; the voice service retries ElevenLabs every hour |
| It answers twice | Two workflows are published: delete the old one |

## Checklist

- [ ] ElevenLabs account and `sk_…` key (or skipped on purpose)
- [ ] `10-install-voice.sh`: cloud and local voices work, ears heard the test sentence
- [ ] New workflow imported, token + owner ID in **Settings**, credential in **Ask Jarvis's brain** and **Listen**, published; old workflow deleted
- [ ] An Urdu voice note got the right 🎙️ transcript, an answer and a voice note back
- [ ] A typed message got a text answer only

## Check your understanding

1. Why does Jarvis answer a voice note by voice, but a typed message only in text?
2. What happens when the free ElevenLabs credits run out?
3. Why does the voice service have no port on the server?
4. Why does the workflow rename `.oga` to `.ogg`?

## Next

**Part 4 — Jarvis's hands:** Lesson 11 prepares your Windows laptop.
