# Lesson 07 — Jarvis on Telegram: text and voice in, text and voice out (built in n8n's web page)

**Before you start:** Lessons 05 (Bifrost) and 06 (n8n online) are done. Because n8n is online and its AI goes
through Bifrost, this is simple:
- Telegram delivers each message to n8n **instantly**, using n8n's built-in Telegram Trigger. No polling every 10 seconds.
- The bot token sits in an **encrypted n8n credential**, never inside a node.
- Every paid-by-credits step has a **free backup**, so Jarvis keeps working when ElevenLabs credits run out.

**Time:** about 1 hour, all in n8n's web page. **Cost:** $0.

**Status:** ✅ Tested on 2026-11-19: text and voice, the Gemini listening backup, and the only-me check. The Gemini speaking backup is written but not tested yet.

---

## Part A — Credentials (n8n → Credentials → Create)

| Name | Type | Contents |
|---|---|---|
| `Jarvis bot` | Telegram API | token from @BotFather (`/mybots` → your bot → API Token) |
| `AI smart` | OpenAI | API key = Bifrost virtual key `smart` · Base URL `http://bifrost:8080/v1` |
| `ElevenLabs` | Header Auth | Name `xi-api-key` · Value = the **secret** key (`sk_…`), with Speech to Text + Text to Speech access |
| `Gemini` | Google Gemini (PaLM) API | free AI Studio key (project **without billing**) |
| `Gemini key` | Header Auth | Name `x-goog-api-key` · Value = the same Gemini key (for the speaking backup) |

Never paste keys into chats or GitHub. They only go into these credentials.

## Part B — The workflow

```
Telegram Trigger ─► Only me ─► Voice? ─ true ─► Get a file ─► Listen (ElevenLabs) ── Success ──────────────┐
                                  │                               └─ Error ─► Download for Gemini ─►       │
                                  │                                   Gemini listen ─► Backup text ───────┤
                                  └─ false ─► Typed text ─────────────────────────────────────────────────┤
                                                                                                          ▼
          AI Agent (AI smart + Simple Memory per chat) ─► Send a text message ─► Spoken to? ─ true ─► Speak (ElevenLabs)
                                                                                                    ├─ Success ─► Send an audio file
                                                                                                    └─ Error ─► Gemini speak ─► Make WAV ─► Send Gemini voice
```

The AI Agent has **three** lines coming in: from Listen (**Success**), Backup text and Typed text.

## Part C — Every node

**Messages in**

| Node | Settings |
|---|---|
| **Telegram Trigger** | Credential `Jarvis bot` · Updates: `message` |
| **Only me** (If) | `{{ $json.message.from.id }}` · **Number → is equal to** · your own Telegram ID (from `message.from.id` in the trigger's output). ⚠️ Never use "is not empty": every message has a sender ID, so anyone could use your bot and spend your free quotas |
| **Voice?** (If) | `{{ $json.message.voice }}` · **Object → exists** |
| **Typed text** (Edit Fields) | `text` (String) = `{{ $json.message.text }}` |

**Listening (voice notes)**

| Node | Settings |
|---|---|
| **Get a file** (Telegram) | File ID `{{ $json.message.voice.file_id }}` · Download **on** |
| **Listen** (HTTP Request) | POST `https://api.elevenlabs.io/v1/speech-to-text` · Authentication: Generic → Header Auth → `ElevenLabs` · Body **Form-Data**: `file` = *n8n Binary File*, Input Data Field Name `data`; `model_id` = `scribe_v2` · Settings → **On Error: Continue (using error output)** |
| **Download for Gemini** (Telegram), from Listen's **Error** output | File ID `{{ $('Telegram Trigger').item.json.message.voice.file_id }}` · Download **on**. After an error, n8n passes only the error forward, not the audio, so the file must be downloaded again |
| **Gemini listen** (Google Gemini) | Audio → Transcribe a Recording · credential `Gemini` · a **Flash / Flash-Lite** model · Input Type *Binary File(s)* · field `data` |
| **Backup text** (Edit Fields) | Name `text` (**Fixed**, not an expression) · Value `{{ $json.content.parts[0].text }}` |

**Thinking and answering**

| Node | Settings |
|---|---|
| **AI Agent** | Source for Prompt: **Define below** · Prompt `{{ $json.text }}` · System message: *You are Jarvis, Ahmad's personal assistant. Reply briefly. Answer in the language the message is written in (Urdu or English).* |
| ↳ **OpenAI Chat Model** | credential `AI smart` · Model **By ID** `groq/openai/gpt-oss-120b` |
| ↳ **Simple Memory** | Session ID: Define below `{{ $('Telegram Trigger').item.json.message.chat.id }}` · Context window 10 |
| **Send a text message** (Telegram) | Chat ID `{{ $('Telegram Trigger').item.json.message.chat.id }}` · Text `{{ $json.output }}` · Append n8n Attribution **off** |

**Speaking (only when you sent a voice note)**

| Node | Settings |
|---|---|
| **Spoken to?** (If) | `{{ $('Telegram Trigger').item.json.message.voice }}` · Object → exists |
| **Speak** (HTTP Request) | POST `https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL` (pre-made voice "Sarah"; free plans can't use library voices via the API) · Header Auth `ElevenLabs` · Query `output_format` = `mp3_44100_64` · JSON fields `text` = `{{ $('AI Agent').item.json.output.slice(0, 600) }}`, `model_id` = `eleven_v3` · Response Format **File** → `data` · Settings → **On Error: Continue (using error output)** |
| **Send an audio file** (Telegram), from Speak's **Success** | Chat ID as above · Binary File on · field `data` |

**Speaking backup (Gemini, free)**: from Speak's **Error** output

| Node | Settings |
|---|---|
| **Gemini speak** (HTTP Request) | POST `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-tts-preview:generateContent` · Header Auth `Gemini key` · JSON (expression) below · On Error: Continue (using error output), error output left empty |
| **Make WAV** (Code, run once for each item) | code below. Gemini returns raw audio (24 kHz, 16-bit, mono); this adds the WAV header Telegram needs |
| **Send Gemini voice** (Telegram → Send Document) | Chat ID as above · Binary File on · field `data` |

Gemini speak body:
```
{{ JSON.stringify({ contents: [{ parts: [{ text: $('AI Agent').item.json.output.slice(0, 600) }] }], generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: 'Kore' } } } } }) }}
```

Make WAV:
```js
const pcm = Buffer.from($json.candidates[0].content.parts[0].inlineData.data, 'base64');
const rate = 24000, h = Buffer.alloc(44);
h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8);
h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
const wav = Buffer.concat([h, pcm]);
return { json: {}, binary: { data: { data: wav.toString('base64'), mimeType: 'audio/wav', fileName: 'jarvis.wav' } } };
```

## Part D — Tests

| Test | Expected |
|---|---|
| Type a message | text reply only |
| Send a voice note | text reply + audio in Sarah's voice |
| Someone else messages the bot | no reply |
| ElevenLabs credential renamed to `xi-api-key-off`, then a voice note | Gemini hears it → text reply + WAV in Gemini's voice. **Rename it back afterwards** |
| "mera naam yaad rakho: Ahmad", then "mera naam kya hai?" | it remembers |

Then **Publish** the workflow.

## Part E — Errors met while building it (and the fix)

| Error | Cause → fix |
|---|---|
| `The item has no binary field 'scribe_v2'` | Form-Data boxes swapped: *Name* = `file` (what ElevenLabs expects), *Input Data Field Name* = `data` (where n8n holds the download) |
| `Neither authorization header nor xi-api-key received` | HTTP node needs Generic Credential Type → Header Auth → `ElevenLabs` |
| `API key ID used as API key` | The Key ID was pasted. ElevenLabs shows the secret (`sk_…`) only once at creation, so create a new key |
| `No prompt specified` (AI Agent) | Prompt must be *Define below* `{{ $json.text }}`. Also: the agent must only get Listen's **Success** line. Listen's error item going into the agent looks the same |
| `expects … a binary file 'data', but none was found` (Gemini listen) | Listen's Error output carries no audio. Add **Download for Gemini** before Gemini listen |
| `No prompt specified` after the Gemini backup | In Backup text the expression was in the **name** box. Name = `text` (Fixed), value = `{{ $json.content.parts[0].text }}` |
| `expects … binary file 'data'` (Send an audio file) | Speak failed (credential off / no credits). Speak → On Error: Continue (using error output) |
| Text messages broke | A "Get a file" node was placed **before** Voice?. Downloads belong only on the **true** branch |

## Limits to know

- **ElevenLabs free plan:** about 10 minutes of speech a month, pre-made voices only via the API. Replies are spoken up to 600 characters.
- **Gemini free tier:** small per-minute and per-day limits, and Google may use free-tier data to improve its products. **Never send SAR customer data to free AI.**
- When both voices fail, Jarvis still replies in text.

## Next

- **Lesson 08 — Backups**: protect everything built so far.
- **Lesson 09 — Jarvis Live**: talk in real time, like a call.
- Automations: SAR→PKR rate alert, new SAR request alert, morning summary.
