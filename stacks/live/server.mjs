// free-ai-lab — Lesson 09: Jarvis Live server (no dependencies, Node 22)
//
// Jobs:
//   1. Login page (one password, hashed with scrypt). Failed logins return 401 -> fail2ban bans guessers.
//   2. POST /api/token: create a short-lived, single-use Gemini Live token, so the real API key never
//      leaves the server. The browser then talks to Google directly (lowest delay).
//   3. POST /api/tool: when Gemini wants Jarvis to DO something, the page calls this, and we forward it
//      to an n8n webhook on the private network, with a shared secret.

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const env = (k, d) => process.env[k] ?? d;
const PORT = Number(env('PORT', '8080'));
const GEMINI_API_KEY = env('GEMINI_API_KEY', '');
const LIVE_MODEL = env('LIVE_MODEL', 'gemini-3.1-flash-live-preview');
const LIVE_VOICE = env('LIVE_VOICE', 'Kore');
const PASSWORD_HASH = env('LIVE_PASSWORD_HASH', '');      // scrypt:<salt hex>:<hash hex>
const SESSION_SECRET = env('SESSION_SECRET', '');
const N8N_TOOL_URL = env('N8N_TOOL_URL', 'http://n8n:5678/webhook/jarvis-live-tool');
const N8N_TOOL_SECRET = env('N8N_TOOL_SECRET', '');
const OWNER_NAME = env('OWNER_NAME', 'Ahmad');
const SESSION_HOURS = 12;
const PUBLIC_DIR = path.join(path.dirname(new URL(import.meta.url).pathname), 'public');

for (const [k, v] of Object.entries({ GEMINI_API_KEY, PASSWORD_HASH, SESSION_SECRET, N8N_TOOL_SECRET })) {
  if (!v) { console.error(`Missing ${k}`); process.exit(1); }
}

// ---------- what Jarvis is told, and which tools it may use ----------
const SYSTEM_INSTRUCTION = `You are Jarvis, ${OWNER_NAME}'s personal voice assistant.
Speak briefly and naturally, like a helpful person on a call. Reply in the language ${OWNER_NAME} speaks (Urdu or English; mixing is fine).
When ${OWNER_NAME} asks you to send, save or remember something, use the send_to_telegram tool.
For anything else that needs real data or actions, use run_skill. Never invent results of a tool.
Never ask for passwords or API keys.`;

const TOOLS = [{
  functionDeclarations: [
    {
      name: 'send_to_telegram',
      description: `Send a text message to ${OWNER_NAME}'s Telegram, e.g. a note, a reminder text, a summary of this call.`,
      parameters: { type: 'OBJECT', properties: { text: { type: 'STRING', description: 'The message to send' } }, required: ['text'] },
    },
    {
      name: 'run_skill',
      description: 'Ask the automation server (n8n) to do a skill. Known skills: "server_status". More skills are added over time; if the server says a skill is unknown, tell the user.',
      parameters: {
        type: 'OBJECT',
        properties: {
          skill: { type: 'STRING', description: 'Skill name, e.g. server_status' },
          details: { type: 'STRING', description: 'Any details the skill needs, in plain words' },
        },
        required: ['skill'],
      },
    },
  ],
}];

// ---------- helpers ----------
const sign = (v) => crypto.createHmac('sha256', SESSION_SECRET).update(v).digest('hex');
function makeSession() {
  const exp = Date.now() + SESSION_HOURS * 3600e3;
  const v = `${exp}.${crypto.randomBytes(12).toString('hex')}`;
  return `${v}.${sign(v)}`;
}
function validSession(req) {
  const m = /(?:^|;\s*)jl=([^;]+)/.exec(req.headers.cookie || '');
  if (!m) return false;
  const parts = m[1].split('.');
  if (parts.length !== 3) return false;
  const v = `${parts[0]}.${parts[1]}`;
  const good = Buffer.from(sign(v));
  const got = Buffer.from(parts[2]);
  return good.length === got.length && crypto.timingSafeEqual(good, got) && Number(parts[0]) > Date.now();
}
function checkPassword(pw) {
  const [algo, saltHex, hashHex] = PASSWORD_HASH.split(':');
  if (algo !== 'scrypt' || !saltHex || !hashHex) return false;
  const want = Buffer.from(hashHex, 'hex');
  const got = crypto.scryptSync(String(pw), Buffer.from(saltHex, 'hex'), want.length);
  return crypto.timingSafeEqual(want, got);
}
async function readBody(req, limit = 64 * 1024) {
  let size = 0; const chunks = [];
  for await (const c of req) { size += c.length; if (size > limit) throw new Error('too big'); chunks.push(c); }
  return Buffer.concat(chunks).toString('utf8');
}
function send(res, code, body, headers = {}) {
  const isObj = typeof body === 'object' && !Buffer.isBuffer(body);
  res.writeHead(code, {
    'Content-Type': isObj ? 'application/json' : 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'same-origin',
    ...headers,
  });
  res.end(isObj ? JSON.stringify(body) : body);
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };
function serveFile(res, rel) {
  const p = path.normalize(path.join(PUBLIC_DIR, rel));
  if (!p.startsWith(PUBLIC_DIR) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) return send(res, 404, 'Not found');
  res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff' });
  fs.createReadStream(p).pipe(res);
}

// small in-memory brake on password guessing (fail2ban does the real banning from Apache's log)
const fails = new Map();
const tooMany = (ip) => (fails.get(ip)?.filter((t) => Date.now() - t < 10 * 60e3).length || 0) >= 10;

// ---------- routes ----------
async function createToken() {
  const now = Date.now();
  const r = await fetch(`https://generativelanguage.googleapis.com/v1alpha/auth_tokens?key=${encodeURIComponent(GEMINI_API_KEY)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      uses: 1,                                                   // one call per token
      expireTime: new Date(now + 30 * 60e3).toISOString(),      // the call may last up to 30 min
      newSessionExpireTime: new Date(now + 60e3).toISOString(), // must be used within 1 minute
    }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || !data.name) throw new Error(`Google answered ${r.status}: ${JSON.stringify(data).slice(0, 300)}`);
  return data.name;
}

async function runTool(name, args) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 25e3);
  try {
    const r = await fetch(N8N_TOOL_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Jarvis-Secret': N8N_TOOL_SECRET },
      body: JSON.stringify({ tool: name, args: args || {} }),
      signal: ctrl.signal,
    });
    const text = await r.text();
    if (!r.ok) return { ok: false, error: `n8n answered HTTP ${r.status}. Is the "Jarvis Live tools" workflow published?` };
    try { return JSON.parse(text); } catch { return { ok: true, result: text.slice(0, 4000) }; }
  } catch (e) {
    return { ok: false, error: e.name === 'AbortError' ? 'n8n took too long' : `n8n not reachable: ${e.message}` };
  } finally { clearTimeout(t); }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress).split(',')[0].trim();
  try {
    if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true });

    if (req.method === 'POST' && url.pathname === '/login') {
      if (tooMany(ip)) return send(res, 429, { error: 'Too many attempts, wait 10 minutes' });
      const body = new URLSearchParams(await readBody(req));
      if (checkPassword(body.get('password') || '')) {
        fails.delete(ip);
        return send(res, 303, '', { Location: '/', 'Set-Cookie': `jl=${makeSession()}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${SESSION_HOURS * 3600}` });
      }
      fails.set(ip, [...(fails.get(ip) || []), Date.now()]);
      return send(res, 401, fs.readFileSync(path.join(PUBLIC_DIR, 'login.html'), 'utf8').replace('<!--ERR-->', '<p class="err">Wrong password.</p>'));
    }
    if (req.method === 'POST' && url.pathname === '/logout') {
      return send(res, 303, '', { Location: '/', 'Set-Cookie': 'jl=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0' });
    }

    const authed = validSession(req);
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      return serveFile(res, authed ? 'index.html' : 'login.html');
    }
    if (req.method === 'GET' && ['/app.js', '/pcm-worklet.js', '/style.css', '/manifest.json', '/icon.svg'].includes(url.pathname)) {
      if (!authed && url.pathname !== '/style.css' && url.pathname !== '/manifest.json' && url.pathname !== '/icon.svg') return send(res, 401, { error: 'login' });
      return serveFile(res, url.pathname.slice(1));
    }
    if (!authed) return send(res, 401, { error: 'login' });

    if (req.method === 'POST' && url.pathname === '/api/token') {
      const token = await createToken();
      return send(res, 200, { token, model: LIVE_MODEL, voice: LIVE_VOICE, systemInstruction: SYSTEM_INSTRUCTION, tools: TOOLS });
    }
    if (req.method === 'POST' && url.pathname === '/api/tool') {
      const { name, args } = JSON.parse(await readBody(req));
      if (!TOOLS[0].functionDeclarations.some((f) => f.name === name)) return send(res, 400, { ok: false, error: 'unknown tool' });
      console.log(`tool: ${name}`);
      return send(res, 200, await runTool(name, args));
    }
    return send(res, 404, { error: 'not found' });
  } catch (e) {
    console.error(e.message);
    return send(res, 500, { error: e.message.slice(0, 300) });
  }
});
server.listen(PORT, () => console.log(`Jarvis Live on :${PORT}, model ${LIVE_MODEL}`));
