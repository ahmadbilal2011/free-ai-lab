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
          (Groq Whisper, free cloud)                   │
                     │ text                            │
                     ▼                                 │
          BRAIN: AI Agent ('smart')  ──► 💬 text reply ┘
                     │ answer
                     ▼
          VOICE: local Piper service ──► 🔊 voice-note reply
```

## Part B — Choosing ears and a voice (the thinking behind it)

### Ears: Groq Whisper (cloud)

| Why | Detail |
|---|---|
| Free and fast | Groq's free tier includes `whisper-large-v3-turbo`, and it accepts Telegram's voice format (OGG) directly |
| Multilingual | Whisper understands English, Urdu, Arabic and many more |
| Zero server load | The heavy listening happens on Groq's hardware |
| Same gateway | It's added to LiteLLM as a new alias, **`listen`**, so the key stays in one place |
| Privacy | Groq doesn't train on your data, but the voice note does leave the server. Don't send very private things by voice |

The model picker from Lesson 07 now also finds Groq's current Whisper model and adds `listen` automatically.

### Voice: Piper (local, open source)

We looked for a free cloud voice first, but none fit:

| Option | Problem |
|---|---|
| Groq's text-to-speech | Only English and Saudi Arabic: **no Urdu** |
| Big-name cloud voices | Free tiers are small, need a card, or train on data in KSA |
| **Piper** ✅ | Open source, **made for small CPUs** (it even runs on a Raspberry Pi), has **English, Arabic and Urdu** voices, unlimited, private |

So the voice runs on our server, but it's tiny:

| Setting | Why |
|---|---|
| **No host port** | Only n8n (inside Docker's `ai` network) can reach it, at `http://voice:5000` |
| `mem_limit: 768m` | It can never starve the rest of the lab |
| Idle most of the time | It only works for a second or two per reply |
| Reply length capped | Very long answers are cut, to keep CPU use small |
| Auto language | It picks the Urdu, Arabic or English voice from the letters in the reply |
| Healthcheck + autoheal | Restarted automatically if it ever freezes |

**Honest expectation:** Piper sounds clear but a little robotic compared to premium voices, and the Urdu and Arabic voices are "medium" quality. Good enough for an assistant, and free forever.

---

## Part C — Install (one command)

On the VM, as `ubuntu`, **without** `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/11-install-voice.sh -o 11-install-voice.sh && bash 11-install-voice.sh
```

It will:

1. Re-run the model picker, which adds **`listen`** (Groq Whisper) to the gateway, and restart it
2. **Build** the small voice service on your server (first time: a few minutes)
3. Download Piper voices for **English, Arabic and Urdu**
4. Start the voice service
5. **Round-trip test:** Jarvis *speaks* a sentence, then `listen` *transcribes* it:

```
  Jarvis spoke: 20K of OGG/Opus audio
  'listen' heard:  Hello Ahmad, this is Jarvis. Voice is working.
```

If both lines look right, ears and voice both work.

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
… Confirm → Keep my messages → Voice note? ─true─► Get voice file → Transcribe → Voice → text ─┐
                                    └─false──────────────────────────────────────────────────┴─► AI Agent → Send reply → Reply by voice? ─true─► Speak → Send voice
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

### 4. HTTP Request: "Transcribe"

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `http://litellm:4000/v1/audio/transcriptions` |
| Authentication | Generic Credential Type → **Header Auth** → `Gateway key` |
| Send Body | on → **Form-Data** |
| → Parameter 1 | Type **n8n Binary File**, Name `file`, Input Data Field Name `data` |
| → Parameter 2 | Type **Form Data**, Name `model`, Value `listen` |

The output has `text`: what you said.

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
| Install: `'listen' heard: ERROR …` | Needs a Groq key in the gateway (Lesson 07). Check `grep -A3 "model_name: listen" ~/lab/gateway/config.yaml` |
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

- [ ] Ran `11-install-voice.sh`; the round trip printed the sentence back correctly
- [ ] Created the `Gateway key` (Header Auth) credential
- [ ] Workflow handles voice notes: Get voice file → Transcribe → AI → Speak → Send voice
- [ ] Voice notes in English and Urdu answered with text **and** voice
- [ ] Text messages still get text-only replies
- [ ] `docker stats` shows the voice service idle near 0% CPU
- [ ] Wrote today's notes in `PROGRESS.md`

## Check your understanding

1. Why do the ears run in the cloud but the voice runs on our server?
2. Why does the voice service have no host port, and how does n8n still reach it?
3. Why do we tell the AI when a message was a voice note?
4. Why use `sendVoice` instead of n8n's "send audio"?

## Next

**Lesson 12 — Agents and tools**: Jarvis starts *doing* things (with your approval before any action).
