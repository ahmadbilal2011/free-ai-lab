#!/usr/bin/env python3
"""
free-ai-lab — Lesson 07: pick WORKING model names automatically.

Free providers rename and retire models often (we learned this the hard way:
every hard-coded name in our first config was gone). This script:

  1. asks each provider for its CURRENT model list
  2. ranks the chat models by our preferences (big + good for 'smart', small for 'fast')
  3. TESTS candidates with a tiny request until one really answers
  4. writes ~/lab/gateway/config.yaml with the names that work

Run on the VM (the install script runs it for you):
    python3 07-pick-models.py

Keys are read from ~/lab/gateway/.env and are never printed.
"""
import json, os, re, sys, urllib.request, urllib.error
from pathlib import Path

GATEWAY = Path.home() / "lab" / "gateway"
ENV_FILE = GATEWAY / ".env"
CONFIG = GATEWAY / "config.yaml"
MAX_TESTS = 6          # candidates tried per alias, to protect free daily limits

# Words that mean "not a chat model" (speech, safety filters, embeddings, ...)
NOT_CHAT = re.compile(r"whisper|tts|speech|audio|transcri|guard|safety|embed|rerank|retriev|"
                      r"reward|parse|ocr|clip|vision-only|playai|orpheus|compound|moderation|"
                      r"image|video|nemoretriever|kosmos|deplot|neva|fuyu|vila|cosmos", re.I)

# Preference order: earlier patterns win. Only models that exist TODAY are considered.
SMART_PREF = [r"gpt-oss-120b", r"llama-4-maverick", r"qwen3.*(235b|480b)", r"deepseek-(v3|r1|chat)",
              r"kimi-k2", r"llama-3\.3-nemotron-super", r"nemotron.*(super|ultra)", r"qwen3-?(32b|30b)",
              r"llama-4-scout", r"llama-3\.3-70b", r"mistral-large", r"gemma-?3-27b", r"70b", r"120b"]
FAST_PREF  = [r"gpt-oss-20b", r"llama-4-scout", r"qwen3-?(8b|14b)", r"8b-instant", r"llama-3\.1-8b",
              r"gemma-?3-(4b|12b)", r"mini", r"8b", r"9b", r"20b"]

PROVIDERS = {
    "groq":       {"base": "https://api.groq.com/openai/v1",       "env": "GROQ_API_KEY",       "prefix": "groq/"},
    "nvidia":     {"base": "https://integrate.api.nvidia.com/v1",  "env": "NVIDIA_API_KEY",     "prefix": "openai/"},
    "openrouter": {"base": "https://openrouter.ai/api/v1",         "env": "OPENROUTER_API_KEY", "prefix": "openrouter/"},
}

def load_env():
    env = {}
    for line in ENV_FILE.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env

def http(url, key, body=None, timeout=40):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                                          "User-Agent": "free-ai-lab"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try: return e.code, json.loads(e.read() or b"{}")
        except Exception: return e.code, {}
    except Exception as e:
        return 0, {"error": str(e)}

def list_models(name, cfg, key):
    code, data = http(cfg["base"] + "/models", key)
    if code != 200:
        print(f"  {name:<10} could not list models (HTTP {code})"); return []
    models = data.get("data", [])
    ids = []
    for m in models:
        mid = m.get("id", "")
        if not mid or NOT_CHAT.search(mid): continue
        if name == "openrouter":                      # free models only
            p = m.get("pricing", {})
            if not (mid.endswith(":free") or (str(p.get("prompt")) in ("0", "0.0") and str(p.get("completion")) in ("0", "0.0"))):
                continue
        if m.get("active") is False: continue          # Groq marks retired models inactive
        ids.append(mid)
    return sorted(set(ids))

def rank(ids, prefs):
    ranked = []
    for pat in prefs:
        ranked += [i for i in ids if re.search(pat, i, re.I) and i not in ranked]
    return ranked + [i for i in ids if i not in ranked]

def works(cfg, key, mid):
    code, data = http(cfg["base"] + "/chat/completions", key,
                      {"model": mid, "max_tokens": 5, "messages": [{"role": "user", "content": "Hi"}]})
    return code == 200 and "choices" in data

def pick(name, cfg, key, ids, prefs, avoid=None):
    for mid in rank(ids, prefs)[:MAX_TESTS]:
        if mid == avoid: continue
        ok = works(cfg, key, mid)
        print(f"  {name:<10} test {mid:<55} {'OK' if ok else 'no'}")
        if ok: return mid
    return None

def main():
    if not ENV_FILE.exists():
        sys.exit("~/lab/gateway/.env not found. Run 07-install-gateway.sh first.")
    env = load_env()
    chosen = {}
    for name, cfg in PROVIDERS.items():
        key = env.get(cfg["env"], "")
        if not key or key == "not-set":
            print(f"  {name:<10} skipped (no key)"); continue
        ids = list_models(name, cfg, key)
        print(f"  {name:<10} {len(ids)} chat models listed")
        smart = pick(name, cfg, key, ids, SMART_PREF)
        if smart: chosen[f"{name}_smart"] = cfg["prefix"] + smart
        if name == "groq":
            fast = pick(name, cfg, key, ids, FAST_PREF, avoid=smart)
            if fast: chosen["groq_fast"] = cfg["prefix"] + fast
            # speech-to-text for voice notes (Lesson 11): prefer the fast Whisper
            code, data = http(cfg["base"] + "/models", key)
            all_ids = [m.get("id", "") for m in data.get("data", [])] if code == 200 else []
            for w in ("whisper-large-v3-turbo", "whisper-large-v3"):
                if w in all_ids:
                    chosen["groq_listen"] = "groq/" + w
                    print(f"  {name:<10} speech-to-text: {w}")
                    break

    # ---------- build config ----------
    deployments, smart_chain = [], []
    def add(alias, model, env_var=None, base=None):
        p = {"model": model}
        if base: p["api_base"] = base
        if env_var: p["api_key"] = f"os.environ/{env_var}"
        deployments.append({"model_name": alias, "litellm_params": p})

    if "groq_smart" in chosen:       add("smart-groq", chosen["groq_smart"], "GROQ_API_KEY");             smart_chain.append("smart-groq")
    if "nvidia_smart" in chosen:     add("smart-nvidia", chosen["nvidia_smart"], "NVIDIA_API_KEY", PROVIDERS["nvidia"]["base"]); smart_chain.append("smart-nvidia")
    if "openrouter_smart" in chosen: add("smart-openrouter", chosen["openrouter_smart"], "OPENROUTER_API_KEY"); smart_chain.append("smart-openrouter")
    fast_first = "fast-groq" if "groq_fast" in chosen else None
    if fast_first: add("fast-groq", chosen["groq_fast"], "GROQ_API_KEY")
    add("private", "ollama_chat/llama3.2:3b", base="http://ollama:11434")
    if "groq_listen" in chosen:
        add("listen", chosen["groq_listen"], "GROQ_API_KEY")
        deployments[-1]["model_info"] = {"mode": "audio_transcription"}
    drill_target = chosen.get("groq_fast") or chosen.get("groq_smart") or "groq/llama-placeholder"
    deployments.append({"model_name": "drill", "litellm_params": {"model": drill_target, "api_key": "this-key-is-intentionally-invalid"}})

    # 'smart' and 'fast' are aliases that point at the first working choice, with ordered fallbacks
    chain = smart_chain + ["private"]
    fast_chain = ([fast_first] if fast_first else []) + smart_chain + ["private"]
    aliases = {"smart": chain[0], "fast": fast_chain[0]}

    lines = ["# GENERATED by 07-pick-models.py — models that answered a live test on this server.",
             "# Re-run the picker any time a provider renames models:  python3 07-pick-models.py",
             "# Keys are NOT here; they come from .env.", "", "model_list:"]
    for d in deployments:
        lines.append(f"  - model_name: {d['model_name']}")
        lines.append(f"    litellm_params:")
        for k, v in d["litellm_params"].items():
            lines.append(f"      {k}: {json.dumps(v) if k == 'api_key' and not v.startswith('os.environ') else v}")
        if d.get("model_info"):
            lines.append(f"    model_info:")
            for k, v in d["model_info"].items():
                lines.append(f"      {k}: {v}")
    # alias entries: a second deployment under the friendly name, same params as the first choice
    for alias, target in aliases.items():
        src = next(d for d in deployments if d["model_name"] == target)
        lines.append(f"  - model_name: {alias}")
        lines.append(f"    litellm_params:")
        for k, v in src["litellm_params"].items():
            lines.append(f"      {k}: {v}")
    fbs = [f"    - smart: {json.dumps(chain[1:])}" if len(chain) > 1 else None,
           f"    - fast: {json.dumps(fast_chain[1:])}" if len(fast_chain) > 1 else None]
    for i, m in enumerate(smart_chain):
        fbs.append(f"    - {m}: {json.dumps(smart_chain[i+1:] + ['private'])}")
    if fast_first: fbs.append(f"    - {fast_first}: {json.dumps(smart_chain + ['private'])}")
    fbs.append(f"    - drill: {json.dumps(smart_chain + ['private'])}")
    lines += ["", "router_settings:", "  fallbacks:"] + [f for f in fbs if f] + [
        "  num_retries: 1", "  timeout: 90", "  allowed_fails: 1", "  cooldown_time: 60",
        "", "litellm_settings:", "  drop_params: true",
        "", "general_settings:", "  master_key: os.environ/LITELLM_MASTER_KEY", ""]
    CONFIG.write_text("\n".join(lines))

    print("\n  Chosen (written to ~/lab/gateway/config.yaml):")
    print(f"    smart   -> {' -> '.join(chain)}")
    print(f"    fast    -> {' -> '.join(fast_chain)}")
    for k, v in chosen.items(): print(f"    {k:<17} = {v}")
    if "groq_listen" in chosen: print("    listen  -> speech-to-text for voice notes (Lesson 11)")
    if not smart_chain:
        print("\n  WARNING: no cloud model worked. Everything will use the local model.")
        sys.exit(2)

if __name__ == "__main__":
    main()
