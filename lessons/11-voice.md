# Lesson 11 — Voice in, voice out

**Goal:** send Jarvis a **voice note** on Telegram (English, Urdu or Arabic). Jarvis understands it, answers in text, and also **replies with a voice note**.

**Time:** about 30–40 minutes.

**Cost:** $0.

**Before you start:** Lesson 10 works: Jarvis answers your text messages on Telegram.

---

## Part A — What we're adding

Jarvis needs **ears** (speech → text) and a **voice** (text → speech):

```
You: 🎤 voice note ──► Telegram ◄── n8n downloads it
                                     │
                     ┌───────────────┴────────────────┐
                     ▼                                 │
          EARS: gateway 'listen'                       │
          (ElevenLabs Scribe → Groq backup)            │
                     │ text                            │
                     ▼                                 │
          BRAIN: AI Agent ('smart')  ──► 💬 text reply ┘
                     │ answer
                     ▼
          VOICE: voice service ──► 🔊 voice-note reply
          (ElevenLabs v3 → local Piper when credits run out)
```

## Part B — Choosing ears and a voice (the thinking behind it)

### A real test result first

We first planned Groq's free Whisper as the ears. **In real use it didn't understand Ahmad's speech well.** That's normal: speech models differ a lot by accent and language, and you only find out by testing with *your own* voice. So we switched to the provider with the best Urdu speech support, and kept Groq as a backup.

### Ears: ElevenLabs Scribe, with Groq as backup

| | ElevenLabs Scribe (`listen`) | Groq Whisper (`listen-backup`) |
|---|---|---|
| Understanding (accents, Urdu) | Best we found | Weaker in our test |
| Free allowance | Part of ElevenLabs' **10,000 credits/month** (≈ 30 min of listening if used only for this) | Generous daily free tier |
| Role | First choice | Automatic backup when credits run out |

### Voice: ElevenLabs v3, with local Piper as backup

| | ElevenLabs **Eleven v3** (`speak`) | **Piper** (local, open source) |
|---|---|---|
| Sound | Very natural | Clear but a little robotic |
| Urdu | ✅ (only the v3 model speaks Urdu) | ✅ medium quality |
| Free allowance | The same 10,000 credits/month (≈ 10 min of speech) | Unlimited |
| Where | Cloud (zero server load) | Our server, tiny |
| Role | First choice | Automatic backup |

**Why both?** 10,000 credits a month is enough for a taste of premium voice, not for daily heavy use. When the credits run out, Jarvis **quietly switches** to the backups and keeps working. They come back next month.

**ElevenLabs free-plan rules:** personal use only (no commercial use), and credit ElevenLabs if you publish the audio. Voice notes are sent to ElevenLabs (or Groq), so don't send very private things by voice.

### How the switching works

| Job | Who switches | How |
|---|---|---|
| Ears | **n8n** | If `listen` fails, the **Transcribe** node's error output runs **Transcribe (backup)** with `listen-backup`. You can see it in the workflow |
| Voice | **The voice service** | It asks the gateway's `speak` first; on "credits used up" (or any error) it uses Piper, and stops trying the cloud for an hour so no time is wasted |

The ElevenLabs key lives **only in the gateway's `.env`**, like your other keys. The voice service only holds the gateway key.

### The local voice service, briefly

| Setting | Why |
|---|---|
| **No host port** | Only n8n (inside Docker's `ai` network) can reach it, at `http://voice:5000` |
| `mem_limit: 768m` | It can never starve the rest of the lab |
| Idle most of the time | Piper only works when the cloud voice isn't available |
| Auto language | Piper picks the Urdu, Arabic or English voice from the letters in the reply |
| Healthcheck + autoheal | Restarted automatically if it ever freezes |

---

## Part C — Install (one command)

On the VM, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/11-install-voice.sh -o 11-install-voice.sh && bash 11-install-voice.sh
```

**Before running it**, create your ElevenLabs API key: **elevenlabs.io → your profile → API Keys → Create**. If it asks which permissions to give, allow **Text to Speech** and **Speech to Text**. Copy the key, but **don't paste it in any chat**.

It will:

1. Ask for your **ElevenLabs key** (hidden, confirms the length and last 4 characters) and save it in the gateway's `.env`
2. Re-run the model picker: **`listen`** = ElevenLabs Scribe, **`listen-backup`** = Groq Whisper, **`speak`** = ElevenLabs v3
3. **Build** the voice service on your server (first time: a few minutes)
4. Download the local **Piper** fallback voices (English, Arabic, Urdu)
5. Start the voice service
6. **Round-trip tests**: each voice speaks a sentence, then each ear transcribes it:

```
  voice (cloud, ElevenLabs):         cloud
  voice (local, Piper fallback):     local
  ears 'listen' heard:               Hello Ahmad, this is Jarvis. Voice is working.
  ears 'listen-backup' heard:        Hello Ahmad, this is Jarvis. Voice is working.
```

---

## Part D — Add voice to the "Jarvis chat" workflow (n8n UI)

### 0. A credential for the gateway's HTTP calls

On the VM: `grep LITELLM_MASTER_KEY ~/lab/gateway/.env`

In n8n: **Credentials → Create → Header Auth**:

| Field | Value |
|---|---|
| Name | `Authorization` |
| Value | `Bearer sk-…` (the word **Bearer**, a space, then your master key) |

Save it as **`Gateway key`**. (The `Lab gateway` credential from Lesson 09 is for AI nodes; HTTP nodes need this one.)

### The new shape of the workflow

```
… Confirm → Keep my messages → Voice note? ─true─► Get voice file → Transcribe ──success──────────┐
                                    │                                    └─error─► Transcribe (backup) ┤
                                    │                                                     Voice → text ┘─┐
                                    └─false────────────────────────────────────────────────────────────┴─► AI Agent → Send reply → Reply by voice? ─true─► Speak → Send voice
```

### 1. Update "Keep my messages" (accept voice notes too)

Replace the code with:

```js
// Only messages from ME: text or voice notes.
const MY_ID = 123456789;   // ← your Telegram user ID (same as Lesson 10)

const updates = $('Ask Telegram').first().json.result ?? [];
return updates
  .filter(u => u.message && u.message.from && u.message.from.id === MY_ID
            && (u.message.text || u.message.voice))
  .map(u => ({ json: {
    chatId: u.message.chat.id,
    text: u.message.text ?? '',
    isVoice: !!u.message.voice,
    voiceFileId: u.message.voice ? u.message.voice.file_id : '',
  } }));
```

### 2. If: "Voice note?"

Insert an **If** node between **Keep my messages** and **AI Agent**: condition **Boolean** → `{{ $json.isVoice }}` **is true**.

- Connect the **false** output straight to **AI Agent** (text messages work as before).

### 3. Telegram: "Get voice file" (true branch)

**Telegram → Get a file**: credential `Jarvis bot`, **File ID** `{{ $json.voiceFileId }}`, **Download** on. The audio arrives as binary data named `data`.

### 4. HTTP Request: "Transcribe" (ElevenLabs Scribe)

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `http://litellm:4000/v1/audio/transcriptions` |
| Authentication | Generic Credential Type → **Header Auth** → `Gateway key` |
| Send Body | on → **Form-Data** |
| → Parameter 1 | Type **n8n Binary File**, Name `file`, Input Data Field Name `data` |
| → Parameter 2 | Type **Form Data**, Name `model`, Value `listen` |
| Settings → On Error | **Continue (using error output)** |

The node now has **two** outputs: *Success* and *Error*. Success has `text`: what you said.

### 4b. HTTP Request: "Transcribe (backup)" (Groq)

Duplicate **Transcribe** (Ctrl+D), rename it **`Transcribe (backup)`**, and change only:

- **Parameter 2 Value:** `listen-backup`
- **Binary data:** this node must read the audio from **Get voice file**, so set the binary parameter's **Input Data Field Name** to `data` and connect it from **Transcribe**'s **Error** output. (n8n passes the original item along with the error, including its binary data.)
- **Settings → On Error:** *Stop Workflow* (if both ears fail, you'll see it in Executions)

Connect **Transcribe → Success** and **Transcribe (backup)** both to the next node.

> If n8n doesn't pass the audio along with the error in your version, connect **Transcribe (backup)** to **Get voice file** instead: add a second **Get voice file** node on the error branch.

### 5. Edit Fields (Set): "Voice → text"

Add **Edit Fields (Set)** with three fields:

| Name | Value (expression) |
|---|---|
| `text` | `{{ $json.text }}` |
| `chatId` | `{{ $('Keep my messages').item.json.chatId }}` |
| `isVoice` | `{{ true }}` (type Boolean) |

Connect it to **AI Agent**. Now the AI Agent has **two** inputs: text messages and transcribed voice notes.

### 6. Tell the AI when you spoke

In **AI Agent**, change the **Prompt** to:

```
{{ $json.text }}{{ $json.isVoice ? '\n\n(Voice note: answer in 2–4 short sentences that sound natural when spoken.)' : '' }}
```

Spoken answers should be short; long lists sound bad as audio.

### 7. If: "Reply by voice?" (after Send reply)

After **Send reply**, add **If**: **Boolean** → `{{ $('Keep my messages').item.json.isVoice }}` **is true**.

So: **text in → text out; voice in → text + voice out.**

### 8. HTTP Request: "Speak" (true branch)

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `http://voice:5000/speak` |
| Send Body | on → **JSON** → *Using Fields Below* → Name `text`, Value `{{ $('AI Agent').item.json.output }}` |
| Options → Response → Response Format | **File**, output field `data` |
| Settings → On Error | **Continue** (if a voice is missing, you still have the text reply) |

The voice service decides **who** speaks: ElevenLabs first, Piper when the credits are used up. In the execution data, the response header `x-voice-engine` shows `cloud` or `local`.

### 9. HTTP Request: "Send voice"

n8n's Telegram node can send audio files, but Telegram only shows a real **voice-note bubble** for the `sendVoice` method, so we call it directly:

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `https://api.telegram.org/bot<YOUR-TOKEN>/sendVoice` |
| Send Body | on → **Form-Data** |
| → Parameter 1 | Type **Form Data**, Name `chat_id`, Value `{{ $('Keep my messages').item.json.chatId }}` |
| → Parameter 2 | Type **n8n Binary File**, Name `voice`, Input Data Field Name `data` |
| Settings → On Error | **Continue** |

**Save.** The workflow stays **Active**.

---

## Part E — Try it

Send Jarvis voice notes:

| Say | Expect |
|---|---|
| "What can you help me with today?" | English text + English voice reply |
| "مجھے آج کے لیے تین کام بتاؤ" | Urdu text + Urdu voice reply |
| "ما هي عاصمة السعودية؟" | Arabic text + Arabic voice reply |

Text messages still get text-only replies.

Check the server load while you test:

```bash
docker stats --no-stream voice litellm n8n
```

The voice service should sit near **0% CPU** when idle.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| Install: `voice (cloud, ElevenLabs): FAILED 401` | The key is wrong or lacks the **Text to Speech** permission. Fix it in ElevenLabs, run the script again, paste the key |
| Install: `ears 'listen' heard: FAILED …` | ElevenLabs key lacks **Speech to Text** permission, or credits are used up. `listen-backup` (Groq) still works |
| ElevenLabs credits used up | Expected near the end of a busy month. Jarvis switches to Groq ears and Piper voice by itself. Check credits at elevenlabs.io → Subscription |
| Install: `Couldn't list Piper voices` | The server must reach `huggingface.co`. Try again later |
| Install: `No Piper voice found for UR` | Piper has no Urdu voice right now; Urdu replies will be text only |
| **Transcribe** returns 401 | The `Gateway key` value must be `Bearer ` + master key (with the space) |
| **Transcribe** returns 400 | Check the binary field is named `file` and the input field is `data` |
| **Get voice file**: no binary | Turn **Download** on |
| Voice reply missing, text arrives | Open the **Speak** execution. `422` means no voice for that language; `500` means check `docker logs voice` |
| Voice reply arrives as a file, not a bubble | You used `sendAudio`/`sendDocument`. Use the `sendVoice` URL |
| Wrong voice language | The voice is chosen from the reply's letters. Ask Jarvis to answer in the language you want |

---

## Checklist

- [ ] Created the ElevenLabs API key (Text to Speech + Speech to Text), pasted only into the script
- [ ] Ran `11-install-voice.sh`; both voices answered and the ears printed the sentence back
- [ ] **Transcribe** has an error branch to **Transcribe (backup)**
- [ ] Created the `Gateway key` (Header Auth) credential
- [ ] Workflow handles voice notes: Get voice file → Transcribe → AI → Speak → Send voice
- [ ] Voice notes in English and Urdu answered with text **and** voice
- [ ] Text messages still get text-only replies
- [ ] `docker stats` shows the voice service idle near 0% CPU
- [ ] Wrote today's notes in `PROGRESS.md`

## Check your understanding

1. Why did we switch the ears from Groq to ElevenLabs, and why keep Groq at all?
2. Why does the voice service have no host port, and how does n8n still reach it?
3. Why do we tell the AI when a message was a voice note?
4. Why use `sendVoice` instead of n8n's "send audio"?

## Next

**Lesson 12 — Agents and tools**: Jarvis starts *doing* things (with your approval before any action).
