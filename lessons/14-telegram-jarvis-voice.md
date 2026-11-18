# Lesson 14 — Jarvis on Telegram: text and voice in, text and voice out (built in n8n's web page)

**Replaces the polling version of Lessons 09–10** now that n8n is public (Lesson 08b) and AI goes through
Bifrost (Lesson 13). Telegram delivers each message to n8n instantly. The bot token is stored in an encrypted
n8n credential, never in a node.

## Credentials (n8n → Credentials)

| Name | Type | Contents |
|---|---|---|
| `Jarvis bot` | Telegram API | token from @BotFather |
| `AI smart` | OpenAI | API key = Bifrost virtual key `smart` · Base URL `http://bifrost:8080/v1` |
| `ElevenLabs` | Header Auth | Name `xi-api-key` · Value = the **secret** key (`sk_…`, not the Key ID) |
| `Gemini` | Google Gemini (PaLM) API | free AI Studio key (project without billing), used as the listening backup |

## The workflow

```
Telegram Trigger ─► Only me ─► Voice? ─ yes ─► Get a file ─► Listen (ElevenLabs) ─► Heard text ─┐
                                      │                      └ error ─► Get a file ─► Gemini ──┤
                                      └ no ──► Typed text ────────────────────────────────────┤
                                                                                              ▼
                     AI Agent (AI smart + Simple Memory per chat) ─► Send text ─► Spoken to? ─ yes ─► Speak ─► Send Audio
```

| Node | Key settings |
|---|---|
| Telegram Trigger | Updates: `message` |
| Only me (If) | `{{ $json.message.from.id }}` **Number → is equal to** your own Telegram ID. Never "is not empty": that lets anyone use your bot |
| Voice? (If) | `{{ $json.message.voice }}` Object → exists |
| Get a file (Telegram) | File ID `{{ $json.message.voice.file_id }}` · Download on |
| Listen (HTTP Request) | POST `https://api.elevenlabs.io/v1/speech-to-text` · Header Auth `ElevenLabs` · Form-Data: `file` = n8n Binary File from field `data`, `model_id` = `scribe_v2` · Settings → On Error: *Continue (using error output)* |
| Backup listen | error output → Get a file (same as above) → Google Gemini: Audio → Transcribe a recording, binary field `data` |
| Heard text / Typed text (Set) | `text` = `{{ $json.text }}` / `{{ $json.message.text }}` (backup: the transcript field of the Gemini node) |
| AI Agent | Prompt: Define below `{{ $json.text }}` · Chat model: OpenAI Chat Model, credential `AI smart`, model by ID `groq/openai/gpt-oss-120b` · Simple Memory, session `{{ $('Telegram Trigger').item.json.message.chat.id }}`, window 10 |
| Send a text message | Chat ID `{{ $('Telegram Trigger').item.json.message.chat.id }}` · Text `{{ $json.output }}` · Append n8n Attribution off |
| Spoken to? (If) | `{{ $('Telegram Trigger').item.json.message.voice }}` Object → exists |
| Speak (HTTP Request) | POST `https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL` (pre-made voice "Sarah") · Header Auth `ElevenLabs` · Query `output_format=mp3_44100_64` · JSON fields `text` = `{{ $('AI Agent').item.json.output.slice(0, 600) }}`, `model_id` = `eleven_v3` · Response Format: File → `data` |
| Send Audio (Telegram) | Binary File on, field `data` |

## Lessons learned while building it

- **"No binary field"**: in Form-Data, *Name* is the field ElevenLabs expects (`file`), *Input Data Field Name* is
  where n8n holds the download (`data`). They were swapped.
- **"Neither authorization header nor xi-api-key received"**: the HTTP node needs Generic Credential Type → Header Auth.
- **"API key ID used as API key"**: ElevenLabs shows the secret (`sk_…`) only once at creation; create a new key.
- **"No prompt specified"**: AI Agent must use *Define below* with `{{ $json.text }}`. The Telegram text is empty for voice notes.
- Free ElevenLabs plans: pre-made voices only via the API, and limited monthly credits, so replies are spoken
  only up to 600 characters.
