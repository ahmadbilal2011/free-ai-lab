# Lesson 05 — The AI switchboard: free AI keys, added in a web page, used by n8n

**Goal:** one place, a web page, where you add free AI providers and models. n8n connects to that one
place and can use every model in it, switching automatically when one is busy or out of free quota.

We use **Bifrost**, a small open-source AI gateway (one container, about 160 MB RAM) with its own web page.
**Status:** ✅ Installed and used by n8n (2026-11-18/19).

```
n8n ──► http://bifrost:8080/v1  (inside the server only)
              │  Bifrost picks a provider; if one fails or hits its limit, it tries the next
              ├─ Groq      ├─ Gemini (AI Studio, free)   ├─ OpenRouter (:free models)
              ├─ Mistral   ├─ Cohere                     ├─ NVIDIA / Cloudflare / SambaNova …
You ──► https://ai-<ip>.sslip.io  (Bifrost's web page, with its own login)
```

## Three ideas first

1. **An API key is a password.** It proves a request comes from your account. Never paste it into GitHub, chats
   (including AI chats), screenshots or emails. If one leaks, delete it on the provider's site and make a new one.
2. **"OpenAI-compatible".** Most providers accept the request format OpenAI made popular, so one switchboard talks
   to all of them; only the address and the key change. No OpenAI account is needed.
3. **Limits and HTTP 429.** Free tiers limit requests per minute and per day. Going over returns *429 Too Many
   Requests*. Nothing breaks: Bifrost switches to the next provider.

**Privacy rule:** personal or customer data only goes to providers that don't train on it. Free tiers (Gemini's
included) may use prompts to improve their products, so **SAR customer data never goes to free AI**.

> A **Gemini Pro / Claude Pro subscription is not an API key.** Gemini Pro includes monthly Google Cloud credits,
> but using them needs a billing account (a card), so this course uses the free AI Studio key instead.

## Safety

- The **web page** is public over HTTPS with Bifrost's own login, and fail2ban bans password guessers.
- The **AI endpoints** (`/v1`, …) are blocked from the internet. Only n8n inside the server can use them,
  so nobody can spend your free quotas.
- Until you create the admin login, the page opens **only through your private unlock link** (any network). After that, Bifrost's own login protects it and you can log in from anywhere.
- Keys are typed into Bifrost's web page and stored on the server. Never paste them in chats or on GitHub.

## Step 1: Install (on the VM, as `ubuntu`)

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/05-install-gateway.sh
bash 05-install-gateway.sh
```

It starts Bifrost, publishes its web page through Apache and prints a **setup token**. (On servers from an
older version of this course it also stops the old LiteLLM gateway; its folder is renamed, nothing deleted.)

## Step 2: Create your admin login

1. The installer ends with an **unlock link**: `https://ai-<your-ip-with-dashes>.sslip.io/?unlock=…`. Open it once in your
   browser, on your laptop or phone and on any network. That browser can enter for 24 hours. Keep the link private.
2. Paste the **setup token** when Bifrost asks (also printed by the installer).
3. **Workspace → Config → Security** → turn on **Password protect the dashboard**. Enter a username and a strong
   password (12+ characters with upper and lower case, a digit and a symbol). Keep **Enforce Virtual Keys on Inference** on.
4. Back on the server: `bash 05-install-gateway.sh --open`. The page then opens from anywhere, protected by your Bifrost
   login. It refuses if the password isn't on yet.

> **Lost the link, or it expired?** Run `bash 05-install-gateway.sh --unlock` for it again.
> **Re-running the installer** does the right thing by itself: if the admin login exists, the page is simply open with your
> login; if not, you get a fresh unlock link. (Older versions locked the page to one IP address. That broke with Cloud Shell
> and changing networks, so it was replaced.)

## Step 3: Add free providers (all in the web page: Models → Model Providers → Add New Provider)

| Provider | Free key at | Notes |
|---|---|---|
| Groq | console.groq.com/keys | fastest; good main model |
| Google Gemini | aistudio.google.com/apikey | use a project **without billing**; Flash / Flash-Lite |
| OpenRouter | openrouter.ai/keys | only models ending in `:free` |
| Mistral | console.mistral.ai | free plan |
| Cohere | dashboard.cohere.com | trial key, monthly cap |
| NVIDIA Build | build.nvidia.com | OpenAI-compatible: `https://integrate.api.nvidia.com/v1` |
| Cloudflare Workers AI | dash.cloudflare.com | OpenAI-compatible: `https://api.cloudflare.com/client/v4/accounts/<account-id>/ai/v1` |
| SambaNova | cloud.sambanova.ai | OpenAI-compatible: `https://api.sambanova.ai/v1` |

Providers that aren't in Bifrost's list are added as **custom / OpenAI-compatible** with the address above.
Never send customer data (SAR requests) to free models that may train on it.

## Step 4: Levels of work = virtual keys

In **Virtual Keys**, create one key per level and give each one several providers with weights. Bifrost uses
them in order of weight and falls back to the next when one fails:

- `quick`: small, fast models (summaries, labels, short replies)
- `smart`: big models (reasoning, writing)
- `code`: coding models

## Step 5: Connect n8n (once per level, after Lesson 06)

n8n → **Credentials → Create → OpenAI**:
- **API Key:** the virtual key (e.g. the `smart` one)
- **Base URL:** `http://bifrost:8080/v1`
- Name it `AI smart` (then `AI quick`, `AI code`)

In any AI node, choose the credential for the level you need. The model name is written as `provider/model`,
for example `groq/openai/gpt-oss-120b`. New models you add in Bifrost are usable right away, without changing n8n.

## Undo

```bash
bash 05-install-gateway.sh --off     # stops Bifrost, takes the page offline; data kept in ~/lab/gateway/data
```
