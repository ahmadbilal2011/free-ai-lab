// free-ai-lab — Lesson 09: Jarvis Live server (no npm packages, Node 22)
//
//   Phone/PC browser ── password page ── this server ──┬── one-time Gemini Live tokens (key stays here)
//                                                      ├── /api/events: live stream of metrics, agent activity, alerts
//                                                      ├── /api/tool: Jarvis's tool calls → agents (n8n, or built-in)
//                                                      └── /api/event: n8n pushes events in (private network only)
//
// The orchestrator is Gemini Live (free tier): it hears you, decides, and calls agents through tools.
// Agents are n8n workflows (one webhook, routed by agent name); the System Monitor agent is built in here.

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const env = (k, d) => process.env[k] ?? d;
const PORT = Number(env('PORT', '8080'));
const GEMINI_API_KEY = env('GEMINI_API_KEY', '');
const LIVE_MODEL = env('LIVE_MODEL', 'gemini-3.1-flash-live-preview');
const LIVE_VOICE = env('LIVE_VOICE', 'Kore');
const PASSWORD_HASH = env('LIVE_PASSWORD_HASH', '');           // scrypt:<salt hex>:<hash hex>
const SESSION_SECRET = env('SESSION_SECRET', '');
const N8N_TOOL_URL = env('N8N_TOOL_URL', 'http://n8n:5678/webhook/jarvis-live-tool');
const JARVIS_SECRET = env('N8N_TOOL_SECRET', '');                // shared with n8n, both directions
const OWNER_NAME = env('OWNER_NAME', 'friend');
const BIFROST_URL = env('BIFROST_URL', 'http://bifrost:8080/v1');     // Lesson 05: many free AI models behind one address
const BIFROST_KEY = env('BIFROST_KEY', '');                            // a Bifrost virtual key (e.g. "smart")
const AGENT_MODEL = env('AGENT_MODEL', 'groq/openai/gpt-oss-120b');
const HOST_PROC = fs.existsSync('/host/proc/stat') ? '/host/proc' : '/proc';
const SESSION_HOURS = 12;
const HERE = path.dirname(new URL(import.meta.url).pathname);
const PUBLIC_DIR = path.join(HERE, 'public');

for (const [k, v] of Object.entries({ GEMINI_API_KEY, PASSWORD_HASH, SESSION_SECRET, JARVIS_SECRET })) {
  if (!v) { console.error(`Missing ${k === 'JARVIS_SECRET' ? 'N8N_TOOL_SECRET' : k}`); process.exit(1); }
}

// ---------- the team: orchestrator + specialised agents ----------
// "where": built-in = handled here, n8n = a branch in the "Jarvis Live tools" workflow.
// "ai" = runs here on free models through Bifrost · "n8n" = a branch in the "Jarvis Live tools" workflow
const AGENTS = [
  { id: 'core',       name: 'Jarvis Core',     role: 'Orchestrator (Gemini Live)',                         color: '#38c8ff', where: 'built-in' },
  { id: 'system',     name: 'System Monitor',  role: 'server health and live metrics',                     color: '#3ddc97', where: 'built-in' },
  { id: 'research',   name: 'Web Scout',       role: 'searches the web, reads pages, answers with sources', color: '#ffc857', where: 'ai' },
  { id: 'writer',     name: 'Writer',          role: 'drafts emails, messages, posts and documents',       color: '#ff8fd8', where: 'ai' },
  { id: 'analyst',    name: 'Analyst',         role: 'analyses text, numbers and risks; summarises',       color: '#8c6cff', where: 'ai' },
  { id: 'planner',    name: 'Planner',         role: 'turns goals into prioritised plans and schedules',   color: '#5eead4', where: 'ai' },
  { id: 'telegram',   name: 'Messenger',       role: 'sends a message to the owner\'s Telegram',           color: '#7aa2ff', where: 'n8n' },
  { id: 'calendar',   name: 'Calendar',        role: 'meetings, priorities and reminders',                 color: '#b388ff', where: 'n8n' },
  { id: 'email',      name: 'Email',           role: 'reads and sends email',                              color: '#ff6bd6', where: 'n8n' },
  { id: 'sar',        name: 'SAR Desk',        role: 'SAR to PKR rates and customer requests',             color: '#2ee6c5', where: 'n8n' },
  { id: 'automation', name: 'Automations',     role: 'runs any other n8n workflow by name',                color: '#9fb4ff', where: 'n8n' },
];
const agentIds = AGENTS.filter((a) => a.id !== 'core').map((a) => a.id);

const SYSTEM_INSTRUCTION = `You are Jarvis, ${OWNER_NAME}'s personal AI operating system, speaking live by voice.
Speak briefly and naturally, like a capable assistant on a call. Reply in the language ${OWNER_NAME} uses (Urdu or English; mixing is fine).
You orchestrate a team of agents. For anything needing real data or actions, call ask_agent with the right agent and a clear task;
for several independent parts, call several agents. Agents: ${AGENTS.filter((a) => a.id !== 'core').map((a) => `${a.id} = ${a.role}`).join('; ')}.
To send something to ${OWNER_NAME}'s phone, use send_to_telegram.
Never invent agent results. If an agent says it isn't built yet, say so in one short sentence.
Messages that start with [EVENT] come from the system, not from ${OWNER_NAME}: mention them briefly and naturally.
Never ask for passwords or API keys.`;

const TOOLS = [{
  functionDeclarations: [
    {
      name: 'ask_agent',
      description: 'Give a task to one specialised agent and get its result. Put everything the agent needs into the task (agents do not hear the conversation). Use context for longer text to work on.',
      parameters: {
        type: 'OBJECT',
        properties: {
          agent: { type: 'STRING', enum: agentIds, description: 'Which agent' },
          task: { type: 'STRING', description: 'What the agent should do, in plain words' },
          context: { type: 'STRING', description: 'Optional text for the agent to work on' },
        },
        required: ['agent', 'task'],
      },
    },
    {
      name: 'send_to_telegram',
      description: `Send a text message to ${OWNER_NAME}'s Telegram (notes, reminders, summaries).`,
      parameters: { type: 'OBJECT', properties: { text: { type: 'STRING' } }, required: ['text'] },
    },
  ],
}];

// ---------- live event stream (Server-Sent Events) ----------
const clients = new Set();
const recent = [];                                   // last events, replayed to new screens
function broadcast(type, data, keep = true) {
  const ev = { type, ts: Date.now(), ...data };
  if (keep) { recent.push(ev); if (recent.length > 60) recent.shift(); }
  const line = `event: ${type}\ndata: ${JSON.stringify(ev)}\n\n`;
  for (const res of clients) res.write(line);
  return ev;
}
const agentEvent = (agent, status, task, detail = '') =>
  broadcast('agent', { agent, status, task: String(task).slice(0, 160), detail: String(detail).slice(0, 300), id: crypto.randomBytes(4).toString('hex') });

// ---------- System Monitor: real host metrics ----------
const readFile = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };
let lastCpu = null, lastNet = null, metrics = {};
function sample() {
  const cpuLine = readFile(`${HOST_PROC}/stat`).split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
  const idle = (cpuLine[3] || 0) + (cpuLine[4] || 0), total = cpuLine.reduce((a, b) => a + b, 0);
  let cpu = 0;
  if (lastCpu && total > lastCpu.total) cpu = 100 * (1 - (idle - lastCpu.idle) / (total - lastCpu.total));
  lastCpu = { idle, total };

  const mi = Object.fromEntries(readFile(`${HOST_PROC}/meminfo`).split('\n').filter(Boolean).map((l) => {
    const [k, v] = l.split(':'); return [k, parseInt(v, 10)];
  }));
  const mem = mi.MemTotal ? 100 * (1 - mi.MemAvailable / mi.MemTotal) : 0;

  let rx = 0, tx = 0;
  const netFile = fs.existsSync(`${HOST_PROC}/1/net/dev`) ? `${HOST_PROC}/1/net/dev` : `${HOST_PROC}/net/dev`;
  for (const l of readFile(netFile).split('\n').slice(2)) {
    const [iface, rest] = l.split(':'); if (!rest || iface.trim() === 'lo') continue;
    const f = rest.trim().split(/\s+/).map(Number); rx += f[0]; tx += f[8];
  }
  const now = Date.now();
  let rxKbps = 0, txKbps = 0;
  if (lastNet) { const dt = (now - lastNet.t) / 1000; rxKbps = ((rx - lastNet.rx) * 8) / 1000 / dt; txKbps = ((tx - lastNet.tx) * 8) / 1000 / dt; }
  lastNet = { rx, tx, t: now };

  const load = parseFloat(readFile(`${HOST_PROC}/loadavg`).split(' ')[0]) || 0;
  const uptime = parseFloat(readFile(`${HOST_PROC}/uptime`).split(' ')[0]) || 0;
  metrics = { cpu: +cpu.toFixed(1), mem: +mem.toFixed(1), memTotalGb: +(mi.MemTotal / 1048576 || 0).toFixed(1),
    rxKbps: +Math.max(0, rxKbps).toFixed(1), txKbps: +Math.max(0, txKbps).toFixed(1), load, uptime };
  broadcast('metrics', metrics, false);
  watch(metrics);
}
// proactive: alert without being asked when something stays wrong
const watchState = { mem: 0, cpu: 0, last: 0 };
function watch(m) {
  watchState.mem = m.mem > 85 ? watchState.mem + 1 : 0;
  watchState.cpu = m.cpu > 90 ? watchState.cpu + 1 : 0;
  const now = Date.now();
  if (now - watchState.last < 30 * 60e3) return;                   // at most one alert per 30 min
  let text = '';
  if (watchState.mem >= 30) text = `Memory has been above 85% for a minute (now ${m.mem}%).`;
  else if (watchState.cpu >= 30) text = `CPU has been above 90% for a minute (now ${m.cpu}%).`;
  if (text) { watchState.last = now; agentEvent('system', 'alert', 'Health watch', text); broadcast('alert', { agent: 'system', text, speak: true }); }
}
setInterval(sample, 2000); sample();
function systemReport() {
  const h = Math.floor(metrics.uptime / 3600);
  return `CPU ${metrics.cpu}%, memory ${metrics.mem}% of ${metrics.memTotalGb} GB, network in ${metrics.rxKbps} kbit/s, out ${metrics.txKbps} kbit/s, load ${metrics.load}, up ${Math.floor(h / 24)} days ${h % 24} hours.`;
}

// ---------- helpers ----------
const sign = (v) => crypto.createHmac('sha256', SESSION_SECRET).update(v).digest('hex');
function makeSession() { const v = `${Date.now() + SESSION_HOURS * 3600e3}.${crypto.randomBytes(12).toString('hex')}`; return `${v}.${sign(v)}`; }
function validSession(req) {
  const m = /(?:^|;\s*)jl=([^;]+)/.exec(req.headers.cookie || ''); if (!m) return false;
  const p = m[1].split('.'); if (p.length !== 3) return false;
  const good = Buffer.from(sign(`${p[0]}.${p[1]}`)), got = Buffer.from(p[2]);
  return good.length === got.length && crypto.timingSafeEqual(good, got) && Number(p[0]) > Date.now();
}
function checkPassword(pw) {
  const [algo, saltHex, hashHex] = PASSWORD_HASH.split(':');
  if (algo !== 'scrypt' || !saltHex || !hashHex) return false;
  const want = Buffer.from(hashHex, 'hex');
  return crypto.timingSafeEqual(want, crypto.scryptSync(String(pw), Buffer.from(saltHex, 'hex'), want.length));
}
const safeEq = (a, b) => { const x = Buffer.from(String(a)), y = Buffer.from(String(b)); return x.length === y.length && crypto.timingSafeEqual(x, y); };
async function readBody(req, limit = 64 * 1024, raw = false) {
  let size = 0; const chunks = [];
  for await (const c of req) { size += c.length; if (size > limit) throw Object.assign(new Error('too big'), { code: 413 }); chunks.push(c); }
  const b = Buffer.concat(chunks); return raw ? b : b.toString('utf8');
}
const HDR = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin' };
function send(res, code, body, headers = {}) {
  const isObj = typeof body === 'object' && !Buffer.isBuffer(body);
  res.writeHead(code, { 'Content-Type': isObj ? 'application/json' : 'text/html; charset=utf-8', ...HDR, ...headers });
  res.end(isObj ? JSON.stringify(body) : body);
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json' };
function serveFile(res, rel) {
  const p = path.normalize(path.join(PUBLIC_DIR, rel));
  if (!p.startsWith(PUBLIC_DIR) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) return send(res, 404, 'Not found');
  res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff' });
  fs.createReadStream(p).pipe(res);
}
const fails = new Map();
const tooMany = (ip) => (fails.get(ip)?.filter((t) => Date.now() - t < 10 * 60e3).length || 0) >= 10;

// ---------- Gemini one-time token ----------
async function createToken() {
  const now = Date.now();
  const r = await fetch(`https://generativelanguage.googleapis.com/v1alpha/auth_tokens?key=${encodeURIComponent(GEMINI_API_KEY)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uses: 1, expireTime: new Date(now + 30 * 60e3).toISOString(), newSessionExpireTime: new Date(now + 60e3).toISOString() }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || !data.name) throw new Error(`Google answered ${r.status}: ${JSON.stringify(data).slice(0, 300)}`);
  return data.name;
}

// ---------- agents ----------
async function callN8n(payload) {
  const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 30e3);
  try {
    const r = await fetch(N8N_TOOL_URL, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Jarvis-Secret': JARVIS_SECRET }, body: JSON.stringify(payload), signal: ctrl.signal });
    const text = await r.text();
    if (!r.ok) return { ok: false, error: `n8n answered HTTP ${r.status}. Is the "Jarvis Live tools" workflow published?` };
    try { return JSON.parse(text); } catch { return { ok: true, result: text.slice(0, 4000) }; }
  } catch (e) { return { ok: false, error: e.name === 'AbortError' ? 'n8n took too long' : `n8n not reachable: ${e.message}` }; }
  finally { clearTimeout(t); }
}
// ---------- AI agents (free models via Bifrost) ----------
async function llm(system, user, maxTokens = 900) {
  if (!BIFROST_KEY) throw new Error('AI agents need a Bifrost key: re-run 09-install-live.sh');
  const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 60e3);
  try {
    const r = await fetch(`${BIFROST_URL}/chat/completions`, {
      method: 'POST', signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${BIFROST_KEY}`, 'x-bf-vk': BIFROST_KEY },
      body: JSON.stringify({ model: AGENT_MODEL, max_tokens: maxTokens, temperature: 0.4,
        messages: [{ role: 'system', content: system }, { role: 'user', content: user }] }),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`Bifrost answered ${r.status}: ${JSON.stringify(j).slice(0, 200)}`);
    return (j.choices?.[0]?.message?.content || '').trim();
  } finally { clearTimeout(t); }
}
const strip = (html) => html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<noscript[\s\S]*?<\/noscript>/gi, ' ')
  .replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
async function fetchText(url, ms = 9000) {
  const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(url, { signal: ctrl.signal, redirect: 'follow', headers: { 'User-Agent': 'Mozilla/5.0 (JarvisLive research agent)', 'Accept-Language': 'en' } });
    if (!r.ok) return '';
    return (await r.text()).slice(0, 600000);
  } catch { return ''; } finally { clearTimeout(t); }
}
async function webSearch(q) {
  const html = await fetchText(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(q)}`);
  const out = [];
  for (const m of html.matchAll(/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?class="result__snippet"[^>]*>([\s\S]*?)<\/a>/g)) {
    let url = m[1]; const u = /uddg=([^&]+)/.exec(url); if (u) url = decodeURIComponent(u[1]);
    if (/^https?:/.test(url) && !/duckduckgo\.com\/y\.js/.test(url)) out.push({ title: strip(m[2]), url, snippet: strip(m[3]) });
    if (out.length >= 5) break;
  }
  if (out.length) return out;
  const wj = await fetchText(`https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=4&srsearch=${encodeURIComponent(q)}`);
  try { return JSON.parse(wj).query.search.map((r) => ({ title: r.title, url: `https://en.wikipedia.org/wiki/${encodeURIComponent(r.title.replace(/ /g, '_'))}`, snippet: strip(r.snippet) })); } catch { return []; }
}
const ROLE = {
  writer: 'You are the Writer agent. Produce the requested text ready to use: clear, warm, professional, no filler. If the language is unclear, use the language of the task.',
  analyst: 'You are the Analyst agent. Analyse what you are given: key points, numbers, risks and recommendations, as short bullet points. Say plainly when information is missing.',
  planner: 'You are the Planner agent. Turn the goal into a short prioritised plan: the 3-7 steps that matter most, with rough timing. Be concrete.',
};
async function aiAgent(agent, task, args) {
  const today = new Date().toLocaleString('en-GB', { timeZone: 'Asia/Riyadh', dateStyle: 'full', timeStyle: 'short' });
  if (agent === 'research') {
    agentEvent(agent, 'progress', `Searching the web: ${task}`);
    const urlInTask = (task.match(/https?:\/\/\S+/) || [])[0];
    const results = urlInTask ? [{ title: urlInTask, url: urlInTask, snippet: '' }] : await webSearch(task);
    if (!results.length) return { ok: false, error: 'web search returned nothing (search sites may be blocking the server)' };
    agentEvent(agent, 'progress', `Reading ${Math.min(3, results.length)} sources`);
    const pages = await Promise.all(results.slice(0, 3).map(async (r) => ({ ...r, text: strip(await fetchText(r.url)).slice(0, 5000) })));
    agentEvent(agent, 'progress', 'Writing the answer');
    const ctx = pages.map((p, i) => `[${i + 1}] ${p.title} (${p.url})\n${p.snippet}\n${p.text}`).join('\n\n');
    const answer = await llm(`You are the Web Scout agent. Today is ${today}. Answer the question using ONLY the sources given. Be brief (max 8 sentences), cite sources as [1], [2]. If the sources don't answer it, say so.`, `Question: ${task}\n\nSources:\n${ctx}`);
    return { ok: true, result: answer, sources: pages.map((p, i) => `[${i + 1}] ${p.url}`) };
  }
  agentEvent(agent, 'progress', 'Thinking with a free model');
  const extra = args?.context ? `\n\nContext:\n${String(args.context).slice(0, 8000)}` : '';
  return { ok: true, result: await llm(`${ROLE[agent]} Today is ${today}. The owner is ${OWNER_NAME}.`, task + extra) };
}

async function runTool(name, args = {}) {
  let agent, task;
  if (name === 'send_to_telegram') { agent = 'telegram'; task = 'Send to Telegram'; }
  else if (name === 'ask_agent' && agentIds.includes(args.agent)) { agent = args.agent; task = args.task || ''; }
  else return { ok: false, error: 'unknown tool or agent' };

  agentEvent('core', 'delegate', `→ ${AGENTS.find((a) => a.id === agent).name}: ${task}`);
  agentEvent(agent, 'start', task);
  let result;
  const where = AGENTS.find((a) => a.id === agent).where;
  try {
    if (agent === 'system') result = { ok: true, result: systemReport() };
    else if (where === 'ai') result = await aiAgent(agent, task, args);
    else result = await callN8n(name === 'send_to_telegram' ? { tool: name, agent, task, args } : { tool: name, agent, task, args });
  } catch (e) { result = { ok: false, error: e.name === 'AbortError' ? 'the AI model took too long' : e.message }; }
  agentEvent(agent, result.ok === false ? 'error' : 'done', task, result.ok === false ? result.error : String(result.result ?? '').slice(0, 200));
  return result;
}

// ---------- HTTP ----------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress).split(',')[0].trim();
  try {
    if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true });

    // n8n → dashboard events. Private network only (Apache blocks this path from the internet) + secret.
    if (req.method === 'POST' && url.pathname === '/api/event') {
      if (!safeEq(req.headers['x-jarvis-secret'] || '', JARVIS_SECRET)) return send(res, 403, { ok: false });
      const e = JSON.parse(await readBody(req));
      const agent = String(e.agent || 'core').slice(0, 30).replace(/[^a-z0-9_-]/gi, '');
      if (e.type === 'alert' || e.speak) broadcast('alert', { agent, text: String(e.text || e.task || '').slice(0, 300), speak: !!e.speak });
      if (e.status || e.task) agentEvent(agent, String(e.status || 'info').slice(0, 12), e.task || e.text || '', e.detail || '');
      return send(res, 200, { ok: true, screens: clients.size });
    }

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
    const openFiles = ['/login.css', '/manifest.json', '/icon.svg'];
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) return serveFile(res, authed ? 'index.html' : 'login.html');
    if (req.method === 'GET' && openFiles.includes(url.pathname)) return serveFile(res, url.pathname.slice(1));
    if (!authed) return send(res, 401, { error: 'login' });
    if (req.method === 'GET' && ['/app.js', '/hud.css', '/pcm-worklet.js', '/avatar.js', '/globe.js'].includes(url.pathname)) return serveFile(res, url.pathname.slice(1));

    if (req.method === 'GET' && url.pathname === '/api/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      res.write(`event: hello\ndata: ${JSON.stringify({ agents: AGENTS, recent, metrics, model: LIVE_MODEL, owner: OWNER_NAME })}\n\n`);
      clients.add(res);
      const ping = setInterval(() => res.write(': ping\n\n'), 15e3);
      req.on('close', () => { clearInterval(ping); clients.delete(res); });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/token') {
      const token = await createToken();
      agentEvent('core', 'online', `Live session opened (${LIVE_MODEL})`);
      return send(res, 200, { token, model: LIVE_MODEL, voice: LIVE_VOICE, systemInstruction: SYSTEM_INSTRUCTION, tools: TOOLS });
    }
    if (req.method === 'POST' && url.pathname === '/api/tool') {
      const { name, args } = JSON.parse(await readBody(req));
      return send(res, 200, await runTool(name, args));
    }
    if (req.method === 'POST' && url.pathname === '/api/log') {        // transcripts → other open screens
      const { who, text } = JSON.parse(await readBody(req));
      broadcast('say', { who: who === 'jarvis' ? 'jarvis' : 'you', text: String(text).slice(0, 500) });
      return send(res, 200, { ok: true });
    }
    return send(res, 404, { error: 'not found' });
  } catch (e) {
    console.error(e.message);
    return send(res, e.code === 413 ? 413 : 500, { error: e.message.slice(0, 300) });
  }
});
server.listen(PORT, () => console.log(`Jarvis Live on :${PORT}, model ${LIVE_MODEL}, metrics from ${HOST_PROC}`));
