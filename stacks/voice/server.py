"""
free-ai-lab — Lesson 11: tiny text-to-speech service for Jarvis.

POST /speak  {"text": "...", "lang": "auto|en|ar|ur", "engine": "auto|cloud|local"}
             ->  OGG/Opus audio (Telegram voice-note format); header X-Voice-Engine says who spoke
GET  /health ->  {"ok": true, "cloud": true/false, "voices": {...}}

engine=auto (default): try the CLOUD voice first (ElevenLabs through our LiteLLM gateway,
model alias 'speak'); if that fails (free credits used up, network, ...), fall back to the
LOCAL Piper voice (open source, made for small CPUs). Jarvis never goes silent.
Only reachable inside Docker's "ai" network (n8n calls http://voice:5000).
"""
import io, json, os, re, subprocess, threading, time, urllib.error, urllib.request, wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from piper import PiperVoice

VOICE_DIR = os.environ.get("VOICE_DIR", "/voices")
MAX_CHARS = int(os.environ.get("MAX_CHARS", "1200"))     # keeps CPU use small
VOICE_FILES = {lang: os.environ.get(f"VOICE_{lang.upper()}", "") for lang in ("en", "ar", "ur")}

# Cloud voice through the gateway (keys stay in the gateway; we only hold the gateway key)
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://litellm:4000/v1")
GATEWAY_KEY = os.environ.get("GATEWAY_KEY", "")
CLOUD_MODEL = os.environ.get("CLOUD_MODEL", "speak")
CLOUD_VOICE = os.environ.get("CLOUD_VOICE", "alloy")      # any ElevenLabs voice ID also works
CLOUD_PAUSE = int(os.environ.get("CLOUD_PAUSE_SECONDS", "3600"))
_cloud_paused_until = 0.0

_loaded, _lock = {}, threading.Lock()
URDU_ONLY = re.compile("[ٹڈڑںھہۃیےۓکگپچژ]")
ARABIC_SCRIPT = re.compile("[؀-ۿ]")


def detect_lang(text: str) -> str:
    """Urdu and Arabic share a script; letters like ے ں ٹ ڈ ڑ ہ ی ک گ are (almost) only Urdu."""
    if URDU_ONLY.search(text):
        return "ur"
    if ARABIC_SCRIPT.search(text):
        return "ar"
    return "en"


def clean(text: str) -> str:
    """Remove markdown and links so the voice doesn't read symbols out loud."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)          # code blocks: skip
    text = re.sub(r"https?://\S+", " ", text)                    # links: skip
    text = re.sub(r"[*_`#>|~\[\]]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:MAX_CHARS]


def voice_for(lang: str):
    name = VOICE_FILES.get(lang, "")
    path = os.path.join(VOICE_DIR, name)
    if not name or not os.path.exists(path):
        return None
    with _lock:
        if lang not in _loaded:
            _loaded[lang] = PiperVoice.load(path)
        return _loaded[lang]


def to_ogg(audio: bytes) -> bytes:
    """Any audio (WAV, MP3, ...) -> OGG/Opus, the format Telegram shows as a voice note."""
    out = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-c:a", "libopus", "-b:a", "32k", "-f", "ogg", "pipe:1"],
        input=audio, capture_output=True, check=True)
    return out.stdout


def cloud_ogg(text: str) -> bytes:
    """Ask the gateway's 'speak' model (ElevenLabs) for MP3, convert to OGG."""
    global _cloud_paused_until
    body = json.dumps({"model": CLOUD_MODEL, "input": text, "voice": CLOUD_VOICE, "response_format": "mp3"}).encode()
    req = urllib.request.Request(f"{GATEWAY_URL}/audio/speech", data=body, headers={
        "Authorization": f"Bearer {GATEWAY_KEY}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return to_ogg(r.read())
    except urllib.error.HTTPError as e:
        if e.code in (401, 402, 403, 429):          # credits used up / key problem: stop trying for a while
            _cloud_paused_until = time.time() + CLOUD_PAUSE
        raise


def cloud_available() -> bool:
    return bool(GATEWAY_KEY) and time.time() >= _cloud_paused_until


def synthesize_ogg(text: str, lang: str) -> bytes:
    voice = voice_for(lang)
    if voice is None:
        raise LookupError(f"no voice installed for '{lang}'")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:
        if hasattr(voice, "synthesize_wav"):      # piper-tts >= 1.3
            voice.synthesize_wav(text, wav)
        else:                                     # older piper-tts
            voice.synthesize(text, wav)
    return to_ogg(buf.getvalue())


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json", engine=""):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        if engine:
            self.send_header("X-Voice-Engine", engine)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            voices = {k: bool(v and os.path.exists(os.path.join(VOICE_DIR, v))) for k, v in VOICE_FILES.items()}
            self._send(200, json.dumps({"ok": True, "cloud": cloud_available(), "voices": voices}).encode())
        else:
            self._send(404, b'{"error":"not found"}')

    def do_POST(self):
        if self.path != "/speak":
            return self._send(404, b'{"error":"not found"}')
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            text = clean(str(req.get("text", "")))
            if not text:
                return self._send(400, b'{"error":"empty text"}')
            lang = req.get("lang") or "auto"
            if lang == "auto":
                lang = detect_lang(text)
            engine = req.get("engine") or "auto"
            if engine in ("auto", "cloud") and cloud_available():
                try:
                    return self._send(200, cloud_ogg(text), "audio/ogg", "cloud")
                except Exception as e:
                    print(f"cloud voice failed ({type(e).__name__}); using local Piper", flush=True)
                    if engine == "cloud":
                        raise
            audio = synthesize_ogg(text, lang)
            self._send(200, audio, "audio/ogg", "local")
        except LookupError as e:
            self._send(422, json.dumps({"error": str(e)}).encode())
        except Exception as e:  # keep the service alive whatever happens
            self._send(500, json.dumps({"error": type(e).__name__}).encode())

    def log_message(self, fmt, *args):  # one short line per request, no text content (privacy)
        print(f"{self.address_string()} {self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)


if __name__ == "__main__":
    print("local voices:", VOICE_FILES, "| cloud voice:", "on" if GATEWAY_KEY else "off", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 5000), Handler).serve_forever()
