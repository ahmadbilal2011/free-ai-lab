"""
free-ai-lab — Lesson 11: tiny text-to-speech service for Jarvis.

POST /speak  {"text": "...", "lang": "auto|en|ar|ur"}  ->  OGG/Opus audio (Telegram voice-note format)
GET  /health                                           ->  {"ok": true, "voices": {...}}

Uses Piper (open source, made for small CPUs) with local voice files.
Only reachable inside Docker's "ai" network (n8n calls http://voice:5000).
"""
import io, json, os, re, subprocess, threading, wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from piper import PiperVoice

VOICE_DIR = os.environ.get("VOICE_DIR", "/voices")
MAX_CHARS = int(os.environ.get("MAX_CHARS", "1200"))     # keeps CPU use small
VOICE_FILES = {lang: os.environ.get(f"VOICE_{lang.upper()}", "") for lang in ("en", "ar", "ur")}

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
    # WAV -> OGG/Opus, the format Telegram shows as a voice note
    out = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-c:a", "libopus", "-b:a", "32k", "-f", "ogg", "pipe:1"],
        input=buf.getvalue(), capture_output=True, check=True)
    return out.stdout


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            voices = {k: bool(v and os.path.exists(os.path.join(VOICE_DIR, v))) for k, v in VOICE_FILES.items()}
            self._send(200, json.dumps({"ok": True, "voices": voices}).encode())
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
            audio = synthesize_ogg(text, lang)
            self._send(200, audio, "audio/ogg")
        except LookupError as e:
            self._send(422, json.dumps({"error": str(e)}).encode())
        except Exception as e:  # keep the service alive whatever happens
            self._send(500, json.dumps({"error": type(e).__name__}).encode())

    def log_message(self, fmt, *args):  # one short line per request, no text content (privacy)
        print(f"{self.address_string()} {self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)


if __name__ == "__main__":
    print("voices:", VOICE_FILES, flush=True)
    ThreadingHTTPServer(("0.0.0.0", 5000), Handler).serve_forever()
