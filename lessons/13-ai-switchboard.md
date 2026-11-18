# Lesson 13 — The AI switchboard: add free AI models in a web page, n8n uses them all

**Goal:** one place, a web page, where you add free AI providers and models. n8n connects to that one
place and can use every model in it, switching automatically when one is busy or out of free quota.

We use **Bifrost**, a small open-source AI gateway (one container, about 160 MB RAM) with its own web page.
It replaces the old LiteLLM gateway from Lesson 06, which needed config files.

```
n8n ──► http://bifrost:8080/v1  (inside the server only)
              │  Bifrost picks a provider; if one fails or hits its limit, it tries the next
              ├─ Groq      ├─ Gemini (AI Studio, free)   ├─ OpenRouter (:free models)
              ├─ Mistral   ├─ Cohere                     ├─ NVIDIA / Cloudflare / SambaNova …
You ──► https://ai-<ip>.sslip.io  (Bifrost's web page, with its own login)
```

## Safety

- The **web page** is public over HTTPS with Bifrost's own login, and fail2ban bans password guessers.
- The **AI endpoints** (`/v1`, …) are blocked from the internet. Only n8n inside the server can use them,
  so nobody can spend your free quotas.
- Until you create the admin login, the page is **locked to your own IP** (the one you SSH from).
- Keys are typed into Bifrost's web page and stored on the server. Never paste them in chats or on GitHub.

## Step 1: Install (on the VM, as `ubuntu`)

```bash
curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/install-gateway.sh
bash install-gateway.sh
```

It stops the old LiteLLM gateway (its folder is renamed, nothing deleted), starts Bifrost, publishes its page
and prints a **setup token**.

## Step 2: Create your admin login (from the same network you SSH from)

1. Open `https://ai-<your-ip-with-dashes>.sslip.io`
2. Paste the **setup token** when asked.
3. **Workspace → Config → Security** → turn on **Password protect the dashboard**. Enter a username and a strong
   password (12+ characters with upper and lower case, a digit and a symbol). Keep **Enforce Virtual Keys on Inference** on.
4. Back on the server: `bash install-gateway.sh --open` removes the IP lock. It refuses if the password isn't on yet.

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

## Step 5: Connect n8n (once per level)

n8n → **Credentials → Create → OpenAI**:
- **API Key:** the virtual key (e.g. the `smart` one)
- **Base URL:** `http://bifrost:8080/v1`
- Name it `AI smart` (then `AI quick`, `AI code`)

In any AI node, choose the credential for the level you need. The model name is written as `provider/model`,
for example `groq/openai/gpt-oss-120b`. New models you add in Bifrost are usable right away, without changing n8n.

## Undo

```bash
bash install-gateway.sh --off     # stops Bifrost, takes the page offline; data kept in ~/lab/gateway/data
```
