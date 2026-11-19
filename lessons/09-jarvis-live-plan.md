# Lesson 09 — Jarvis Live: talk in real time, like a phone call (PLANNED)

**Status:** ⬜ Planned. This page records the options and the chosen direction (2026-11-19). It will be built and tested later.

## The question

Telegram voice notes work like a walkie-talkie: record, send, wait. Can I **talk to Jarvis directly**, back and forth in real time, for free?

## Options compared

| Option | Free? | Connected to my Jarvis / n8n? | Notes |
|---|---|---|---|
| **Gemini Live in the Gemini app** | Yes (also in my Gemini Pro) | ❌ Google's assistant, not mine | Use it today for general conversation |
| **Telegram voice notes** (Lesson 07) | Yes | ✅ | Walkie-talkie style, already working |
| **Own "Jarvis Live" web page** with the **Gemini Live API** | Yes, free tier (rate-limited) | ✅ calls n8n workflows as tools | **Chosen** for later |
| **ElevenLabs Agents** | Only ~15 call minutes a month free | ✅ via webhooks | Too few minutes for daily use |

## Chosen direction: Jarvis Live

- A small web page on the server, published through Apache with HTTPS and a login, like n8n and Bifrost. Open it on the phone (add to home screen), tap, and talk.
- It streams the microphone to the **Gemini Live API** (real-time voice in and out, many languages including Urdu), using a free-tier model.
- Its **tools** are n8n webhooks: "what's the SAR rate?", "remind me…", "any new SAR requests?". Each tool is a small n8n workflow, so skills built for Telegram are reused.
- The Gemini key stays on the server. The page gets short-lived tokens only.

## Honest limits

- Live models are **preview** models; Google can change or remove them.
- The free tier limits concurrent sessions and tokens per minute. That's enough for one person, not for customers.
- Google may use free-tier conversations to improve its products: **no customer data** in Jarvis Live.

## Why later, not now

Jarvis Live is most useful once Jarvis has real skills to call. Build a few automations first (rate alert, new-request alert, morning summary), then give them a live voice.
