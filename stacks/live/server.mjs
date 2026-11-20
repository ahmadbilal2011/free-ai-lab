// free-ai-lab — Lesson 09: Jarvis Live server (no npm packages, Node 22)
//
//   Browser ── password page ── this server ──┬── one-time Gemini Live tokens (the key stays here)
//                                             ├── /api/events : live stream of metrics, agent activity, alerts
//                                             ├── /api/tool   : Jarvis's tool calls → the agent in n8n
//                                             └── /api/event  : n8n pushes events in (private network only)
//
// Two brains, one set of agents:
//   • Your AI models: providers YOU add on the dashboard (Groq, Gemini, OpenRouter, NVIDIA, Mistral, Bifrost, any
//     OpenAI-compatible service), tried in your order with fallback — text and push-to-talk (/api/chat)
//   • Gemini Live (free tier): real-time voice calls with interruptions
// Both decide which agents to call.
// Jarvis Live has NO agents of its own. Agents live in n8n (Lesson 06): n8n publishes the list of agents
// (GET /webhook/jarvis-agents) and does the work (POST /webhook/jarvis-live-tool). Each upcoming lesson adds
// one agent there, and it appears here by itself.

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const env = (k, d) => process.env[k] ?? d;
const PORT = Number(env('PORT', '8080'));
const GEMINI_API_KEY = env('GEMINI_API_KEY', '');
const LIVE_MODEL = env('LIVE_MODEL', 'gemini-3.1-flash-live-preview');
const LIVE_VOICE = env('LIVE_VOICE', 'Kore');
const PASSWORD_HASH = env('LIVE_PASSWORD_HASH', '');                        // scrypt:<salt hex>:<hash hex>
const SESSION_SECRET = env('SESSION_SECRET', '');
const N8N_TOOL_URL = env('N8N_TOOL_URL', 'http://n8n:5678/webhook/jarvis-live-tool');
const N8N_AGENTS_URL = env('N8N_AGENTS_URL', 'http://n8n:5678/webhook/jarvis-agents');
const JARVIS_SECRET = env('N8N_TOOL_SECRET', '');                             // shared with n8n, both directions
const OWNER_NAME = env('OWNER_NAME', 'friend');
// ---------- AI providers you add on the dashboard (stored on the server only; keys never go back to the browser) ----------
const DATA_DIR = env('DATA_DIR', '/app/data');
const PROVIDERS_FILE = path.join(DATA_DIR, 'providers.json');
const readJson = (f, d) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return d; } };
let store = readJson(PROVIDERS_FILE, null);
if (!store) {                                  // first start: carry over the Bifrost key from older installs, if any
  const legacy = readJson(path.join(DATA_DIR, 'settings.json'), {}).models || [];
  store = { providers: [], order: [] };
  if (env('BIFROST_KEY', '')) {
    const models = legacy.length ? legacy : [env('CHAT_MODEL', 'groq/openai/gpt-oss-120b')];
    store.providers.push({ id: 'bifrost', name: 'Bifrost', baseUrl: env('BIFROST_URL', 'http://bifrost:8080/v1'), key: env('BIFROST_KEY', ''), models });
    store.order = models.map((m) => `bifrost::${m}`);
  }
}
function saveStore() { fs.mkdirSync(DATA_DIR, { recursive: true }); fs.writeFileSync(PROVIDERS_FILE, JSON.stringify(store, null, 2), { mode: 0o600 }); }
const findProvider = (id) => store.providers.find((p) => p.id === id);
function chain() {                              // [{ provider, model }] in your order; first model of the first provider if none picked
  const list = store.order.map((e) => { const [pid, ...m] = e.split('::'); return { provider: findProvider(pid), model: m.join('::') }; }).filter((x) => x.provider && x.model);
  if (list.length) return list;
  const p = store.providers.find((x) => x.models?.length);
  return p ? [{ provider: p, model: p.models[0] }] : [];
}
const publicProvider = (p) => ({ id: p.id, name: p.name, baseUrl: p.baseUrl, models: p.models || [], keyHint: p.key ? (p.key.length > 12 ? `…${p.key.slice(-4)}` : "saved") : '' });
function cleanBaseUrl(u) {
  let url; try { url = new URL(String(u).trim()); } catch { throw new Error('That address is not a valid URL'); }
  const internal = !url.hostname.includes('.') || url.hostname === 'localhost';   // e.g. http://bifrost:8080/v1 on the private network
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && internal)) throw new Error('Use an https:// address (http:// only for services inside the server, like http://bifrost:8080/v1)');
  return url.toString().replace(/\/+$/, '');
}
const HOST_PROC = fs.existsSync('/host/proc/stat') ? '/host/proc' : '/proc';
const SESSION_HOURS = 12;
const PUBLIC_DIR = path.join(path.dirname(new URL(import.meta.url).pathname), 'public');

for (const [k, v] of Object.entries({ GEMINI_API_KEY, PASSWORD_HASH, SESSION_SECRET, N8N_TOOL_SECRET: JARVIS_SECRET })) {
  if (!v) { console.error(`Missing ${k}`); process.exit(1); }
}

// ---------- live event stream (Server-Sent Events) ----------
const clients = new Set();
const recent = [];
function broadcast(type, data, keep = true) {
  const ev = { type, ts: Date.now(), ...data };
  if (keep) { recent.push(ev); if (recent.length > 60) recent.shift(); }
  const line = `event: ${type}\ndata: ${JSON.stringify(ev)}\n\n`;
  for (const res of clients) res.write(line);
  return ev;
}
const agentEvent = (agent, status, task, detail = '') =>
  broadcast('agent', { agent, status, task: String(task).slice(0, 160), detail: String(detail).slice(0, 300) });

// ---------- agents: the list comes from n8n ----------
// n8n answers GET /webhook/jarvis-agents with { "agents": [ { "id", "name", "role", "color" }, … ] }
let agents = [];
let n8n = { ok: false, note: 'not checked yet' };
const slug = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 30);
async function refreshAgents() {
  let next = agents, status;
  try {
    const r = await fetch(N8N_AGENTS_URL, { headers: { 'X-Jarvis-Secret': JARVIS_SECRET }, signal: AbortSignal.timeout(8000) });
    if (r.status === 404) status = { ok: false, note: 'n8n is up, but the "Jarvis agents" workflow isn\'t published yet' };
    else if (r.status === 401 || r.status === 403) status = { ok: false, note: 'n8n refused the Jarvis secret' };
    else if (!r.ok) status = { ok: false, note: `n8n answered HTTP ${r.status}` };
    else {
      const j = await r.json().catch(() => ({}));
      const list = Array.isArray(j) ? j : Array.isArray(j.agents) ? j.agents : [];
      next = list.map((a) => ({
        id: slug(a.id || a.name), name: String(a.name || a.id).slice(0, 40), role: String(a.role || '').slice(0, 120),
        color: /^#[0-9a-f]{6}$/i.test(a.color || '') ? a.color : '#8c6cff',
      })).filter((a) => a.id).slice(0, 16);
      status = { ok: true, note: next.length ? `connected · ${next.length} agent${next.length > 1 ? 's' : ''}` : 'connected · no agents yet' };
    }
  } catch { status = { ok: false, note: 'n8n not reachable' }; }
  if (status.ok === false) next = [];
  const changed = JSON.stringify(next) !== JSON.stringify(agents) || status.note !== n8n.note;
  agents = next; n8n = status;
  if (changed) broadcast('agents', { agents, n8n }, false);
}
setInterval(refreshAgents, 60e3); refreshAgents();

// ---------- brain status: how many providers and models Jarvis can use ----------
let brain = {};
function brainStatus() {
  const c = chain();
  const next = c.length
    ? { ok: true, note: `${store.providers.length} provider${store.providers.length > 1 ? 's' : ''} · ${c.length} model${c.length > 1 ? 's' : ''} in line`, first: `${c[0].provider.name} · ${c[0].model}` }
    : { ok: false, note: store.providers.length ? 'pick models' : 'add a provider' };
  if (JSON.stringify(next) !== JSON.stringify(brain)) { brain = next; broadcast('brain', { brain }, false); }
}
brainStatus();

function brief(mode = 'voice') {
  const base = `You are Jarvis, ${OWNER_NAME}'s personal AI operating system${mode === 'voice' ? ', speaking live by voice' : ''}.
${mode === 'voice' ? 'Speak briefly and naturally, like a capable assistant on a call.' : 'Answer briefly and clearly; your replies are shown on a dashboard and read aloud, so avoid tables and long lists. Today is ' + new Date().toLocaleString('en-GB', { timeZone: 'Asia/Riyadh', dateStyle: 'full', timeStyle: 'short' }) + '.'} Reply in the language ${OWNER_NAME} uses (Urdu or English; mixing is fine).
Messages that start with [EVENT] come from the system, not from ${OWNER_NAME}: mention them briefly.
Never ask for passwords or API keys. Never invent facts about ${OWNER_NAME}'s calendar, email, money or files.`;
  if (!agents.length) return `${base}
Right now you have NO agents connected: you can talk, explain and answer general questions, but you cannot take actions
or read personal data. If asked to do something like that, say in one sentence that this skill arrives when its agent
is added in n8n in an upcoming lesson.`;
  return `${base}
You orchestrate these agents (they live in n8n). For anything needing their data or actions, call ask_agent with the
right agent and a complete task; call several agents at once when a request has several parts. Never invent results.
Agents: ${agents.map((a) => `${a.id} = ${a.name}: ${a.role}`).join('; ')}.`;
}
function tools() {
  if (!agents.length) return [];
  return [{ functionDeclarations: [{
    name: 'ask_agent',
    description: 'Give a task to one agent and get its result. Put everything it needs into the task (agents do not hear the conversation).',
    parameters: { type: 'OBJECT', properties: {
      agent: { type: 'STRING', enum: agents.map((a) => a.id), description: 'Which agent' },
      task: { type: 'STRING', description: 'What the agent should do, in plain words' },
      context: { type: 'STRING', description: 'Optional longer text for the agent to work on' },
    }, required: ['agent', 'task'] },
  }] }];
}
async function runTool(name, args = {}) {
  const agent = agents.find((a) => a.id === args.agent);
  if (name !== 'ask_agent' || !agent) return { ok: false, error: 'That agent is not connected.' };
  const task = String(args.task || '').slice(0, 2000);
  agentEvent('core', 'delegate', `→ ${agent.name}: ${task}`);
  agentEvent(agent.id, 'start', task);
  let result;
  try {
    const r = await fetch(N8N_TOOL_URL, {
      method: 'POST', signal: AbortSignal.timeout(45e3),
      headers: { 'Content-Type': 'application/json', 'X-Jarvis-Secret': JARVIS_SECRET },
      body: JSON.stringify({ agent: agent.id, task, context: args.context ? String(args.context).slice(0, 12000) : '', owner: OWNER_NAME }),
    });
    const text = await r.text();
    if (!r.ok) result = { ok: false, error: `n8n answered HTTP ${r.status}` };
    else { try { result = JSON.parse(text); } catch { result = { ok: true, result: text.slice(0, 4000) }; } }
  } catch (e) { result = { ok: false, error: e.name === 'TimeoutError' ? 'the agent took too long' : 'n8n not reachable' }; }
  agentEvent(agent.id, result.ok === false ? 'error' : 'done', task, result.ok === false ? result.error : String(result.result ?? '').slice(0, 200));
  return result;
}

// ---------- Bifrost brain: chat with tool calls (OpenAI format) ----------
function openaiTools() {
  if (!agents.length) return undefined;
  return [{ type: 'function', function: {
    name: 'ask_agent',
    description: 'Give a task to one agent and get its result. Put everything it needs into the task.',
    parameters: { type: 'object', properties: {
      agent: { type: 'string', enum: agents.map((a) => a.id) },
      task: { type: 'string' }, context: { type: 'string' },
    }, required: ['agent', 'task'] },
  } }];
}
async function providerModels(p) {
  const r = await fetch(`${p.baseUrl}/models`, { headers: { Authorization: `Bearer ${p.key}` }, signal: AbortSignal.timeout(12e3) });
  if (!r.ok) throw new Error(`${p.name} answered HTTP ${r.status} for its model list. You can type model names yourself.`);
  const j = await r.json().catch(() => ({}));
  const raw = j.data || j.models || [];
  return [...new Set(raw.map((m) => String(m.id || m.name || m.model || '')).filter(Boolean))].sort();
}
async function modelCall(p, model, messages, extra = {}) {
  const body = { model, messages, temperature: 0.5, max_tokens: 700, ...extra };
  const t = openaiTools(); if (t && !extra.noTools) body.tools = t; delete body.noTools;
  const r = await fetch(`${p.baseUrl}/chat/completions`, {
    method: 'POST', signal: AbortSignal.timeout(60e3),
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${p.key}` },
    body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(`${p.name} · ${model}: HTTP ${r.status} ${JSON.stringify(j.error || j).slice(0, 160)}`), { status: r.status });
  return { msg: j.choices?.[0]?.message || {}, model: `${p.name} · ${j.model || model}` };
}
// your models, in your order, across providers: if one is busy, out of free quota or failing, the next one answers
async function callWithFallback(messages, tried) {
  const c = chain(); let lastErr;
  if (!c.length) throw new Error('No AI provider yet: open "AI providers" at the top and add one.');
  for (const { provider, model } of c) {
    try { const out = await modelCall(provider, model, messages); tried.push(`${provider.name} · ${model}`); return out; }
    catch (e) {
      tried.push(`${provider.name} · ${model} ✗`); lastErr = e;
      broadcast('agent', { agent: 'core', status: 'info', task: `${provider.name} · ${model} didn't answer${e.status ? ` (HTTP ${e.status})` : ''}, trying the next one`, detail: '' });
    }
  }
  throw new Error(`None of your ${c.length} model(s) answered. Last error: ${lastErr?.name === 'TimeoutError' ? 'took too long' : lastErr?.message}`);
}
async function chat(history) {
  const messages = [{ role: 'system', content: brief('text') },
    ...history.slice(-16).map((m) => ({ role: m.role === 'assistant' ? 'assistant' : 'user', content: String(m.content).slice(0, 4000) }))];
  const tried = [];
  for (let step = 0; step < 4; step++) {                           // up to 4 rounds of agent calls
    const { msg, model } = await callWithFallback(messages, tried);
    const calls = msg.tool_calls || [];
    if (!calls.length) return { reply: (msg.content || '').trim(), model, tried };
    messages.push({ role: 'assistant', content: msg.content || '', tool_calls: calls });
    const results = await Promise.all(calls.map(async (c) => {     // several agents in parallel
      let args = {}; try { args = JSON.parse(c.function?.arguments || '{}'); } catch {}
      return { role: 'tool', tool_call_id: c.id, content: JSON.stringify(await runTool(c.function?.name, args)).slice(0, 6000) };
    }));
    messages.push(...results);
  }
  return { reply: 'I asked the agents several times without finishing. Please try a simpler request.', model: tried[tried.length - 1] || '', tried };
}

// ---------- server health (shown on the dashboard; alerts by itself) ----------
const readFile = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };
let lastCpu = null, lastNet = null, metrics = {};
function sample() {
  const c = readFile(`${HOST_PROC}/stat`).split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
  const idle = (c[3] || 0) + (c[4] || 0), total = c.reduce((a, b) => a + b, 0);
  const cpu = lastCpu && total > lastCpu.total ? 100 * (1 - (idle - lastCpu.idle) / (total - lastCpu.total)) : 0;
  lastCpu = { idle, total };
  const mi = Object.fromEntries(readFile(`${HOST_PROC}/meminfo`).split('\n').filter(Boolean).map((l) => { const [k, v] = l.split(':'); return [k, parseInt(v, 10)]; }));
  const mem = mi.MemTotal ? 100 * (1 - mi.MemAvailable / mi.MemTotal) : 0;
  let rx = 0, tx = 0;
  const netFile = fs.existsSync(`${HOST_PROC}/1/net/dev`) ? `${HOST_PROC}/1/net/dev` : `${HOST_PROC}/net/dev`;
  for (const l of readFile(netFile).split('\n').slice(2)) {
    const [iface, rest] = l.split(':'); if (!rest || iface.trim() === 'lo') continue;
    const f = rest.trim().split(/\s+/).map(Number); rx += f[0]; tx += f[8];
  }
  const now = Date.now(); let rxKbps = 0, txKbps = 0;
  if (lastNet) { const dt = (now - lastNet.t) / 1000; rxKbps = ((rx - lastNet.rx) * 8) / 1000 / dt; txKbps = ((tx - lastNet.tx) * 8) / 1000 / dt; }
  lastNet = { rx, tx, t: now };
  metrics = { cpu: +cpu.toFixed(1), mem: +mem.toFixed(1), memTotalGb: +(mi.MemTotal / 1048576 || 0).toFixed(1),
    rxKbps: +Math.max(0, rxKbps).toFixed(1), txKbps: +Math.max(0, txKbps).toFixed(1),
    load: parseFloat(readFile(`${HOST_PROC}/loadavg`).split(' ')[0]) || 0, uptime: parseFloat(readFile(`${HOST_PROC}/uptime`).split(' ')[0]) || 0 };
  broadcast('metrics', metrics, false);
  watch(metrics);
}
const watchState = { mem: 0, cpu: 0, last: 0 };
function watch(m) {
  watchState.mem = m.mem > 85 ? watchState.mem + 1 : 0;
  watchState.cpu = m.cpu > 90 ? watchState.cpu + 1 : 0;
  if (Date.now() - watchState.last < 30 * 60e3) return;
  const text = watchState.mem >= 30 ? `Server memory has been above 85% for a minute (now ${m.mem}%).`
    : watchState.cpu >= 30 ? `Server CPU has been above 90% for a minute (now ${m.cpu}%).` : '';
  if (text) { watchState.last = Date.now(); broadcast('alert', { agent: 'core', text, speak: true }); }
}
setInterval(sample, 2000); sample();

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
async function readBody(req, limit = 64 * 1024) {
  let size = 0; const chunks = [];
  for await (const c of req) { size += c.length; if (size > limit) throw Object.assign(new Error('too big'), { code: 413 }); chunks.push(c); }
  return Buffer.concat(chunks).toString('utf8');
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

// ---------- HTTP ----------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress).split(',')[0].trim();
  try {
    if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true });

    // n8n → dashboard. Private network only (Apache blocks this path from the internet) + secret.
    if (req.method === 'POST' && url.pathname === '/api/event') {
      if (!safeEq(req.headers['x-jarvis-secret'] || '', JARVIS_SECRET)) return send(res, 403, { ok: false });
      const e = JSON.parse(await readBody(req));
      const agent = slug(e.agent) || 'core';
      if (e.refresh) await refreshAgents();                         // an n8n workflow can say "my agent list changed"
      if (e.type === 'alert' || e.speak) broadcast('alert', { agent, text: String(e.text || e.task || '').slice(0, 300), speak: !!e.speak });
      if (e.status) agentEvent(agent, String(e.status).slice(0, 12), e.task || e.text || '', e.detail || '');
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
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) return serveFile(res, authed ? 'index.html' : 'login.html');
    if (req.method === 'GET' && ['/login.css', '/manifest.json', '/icon.svg'].includes(url.pathname)) return serveFile(res, url.pathname.slice(1));
    if (!authed) return send(res, 401, { error: 'login' });
    if (req.method === 'GET' && ['/app.js', '/hud.css', '/pcm-worklet.js', '/avatar.js', '/globe.js'].includes(url.pathname)) return serveFile(res, url.pathname.slice(1));

    if (req.method === 'GET' && url.pathname === '/api/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      res.write(`event: hello\ndata: ${JSON.stringify({ agents, n8n, brain, recent, metrics, model: LIVE_MODEL, owner: OWNER_NAME })}\n\n`);
      clients.add(res);
      const ping = setInterval(() => res.write(': ping\n\n'), 15e3);
      req.on('close', () => { clearInterval(ping); clients.delete(res); });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/agents/refresh') { await refreshAgents(); brainStatus(); return send(res, 200, { agents, n8n, brain }); }
    // ----- AI providers & models (all managed on the dashboard) -----
    if (url.pathname === '/api/providers' && req.method === 'GET') {
      return send(res, 200, { providers: store.providers.map(publicProvider), order: store.order });
    }
    if (url.pathname === '/api/providers' && req.method === 'POST') {          // add or edit one provider
      const b = JSON.parse(await readBody(req));
      const name = String(b.name || '').trim().slice(0, 40);
      if (!name) return send(res, 400, { error: 'Give the provider a name' });
      let baseUrl; try { baseUrl = cleanBaseUrl(b.baseUrl); } catch (e) { return send(res, 400, { error: e.message }); }
      const models = Array.isArray(b.models) ? [...new Set(b.models.map((m) => String(m).trim()).filter((m) => m && m.length <= 160))].slice(0, 200) : undefined;
      let p = b.id ? findProvider(b.id) : null;
      if (b.id && !p) return send(res, 404, { error: 'Provider not found' });
      if (!p) {
        if (!b.key) return send(res, 400, { error: 'Paste the API key' });
        let id = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 30) || 'provider'; while (findProvider(id)) id += '-2';
        p = { id, name, baseUrl, key: String(b.key).trim(), models: models || [] }; store.providers.push(p);
      } else {
        Object.assign(p, { name, baseUrl }); if (b.key) p.key = String(b.key).trim(); if (models) p.models = models;
        store.order = store.order.filter((e) => !e.startsWith(`${p.id}::`) || p.models.includes(e.slice(p.id.length + 2)));
      }
      saveStore(); brainStatus();
      return send(res, 200, { provider: publicProvider(p) });
    }
    if (url.pathname.startsWith('/api/providers/') && req.method === 'DELETE') {
      const id = url.pathname.split('/')[3];
      store.providers = store.providers.filter((p) => p.id !== id); store.order = store.order.filter((e) => !e.startsWith(`${id}::`));
      saveStore(); brainStatus(); return send(res, 200, { ok: true });
    }
    if (url.pathname.match(/^\/api\/providers\/[\w-]+\/(fetch-models|test)$/) && req.method === 'POST') {
      const [, , , id, action] = url.pathname.split('/'); const p = findProvider(id);
      if (!p) return send(res, 404, { error: 'Provider not found' });
      if (action === 'fetch-models') {
        try { return send(res, 200, { models: await providerModels(p) }); } catch (e) { return send(res, 502, { error: e.message }); }
      }
      const { model } = JSON.parse(await readBody(req)); const m = String(model || p.models?.[0] || '');
      if (!m) return send(res, 400, { error: 'Pick or type a model first' });
      const t0 = Date.now();
      try {
        const out = await modelCall(p, m, [{ role: 'user', content: 'Reply with the single word: ready' }], { max_tokens: 20, noTools: true });
        return send(res, 200, { ok: true, reply: String(out.msg.content || '').slice(0, 80), ms: Date.now() - t0 });
      } catch (e) { return send(res, 200, { ok: false, error: e.name === 'TimeoutError' ? 'took too long' : e.message }); }
    }
    if (url.pathname === '/api/order' && req.method === 'POST') {             // the line-up Jarvis tries, across providers
      const { order } = JSON.parse(await readBody(req));
      if (!Array.isArray(order)) return send(res, 400, { error: 'order must be a list' });
      store.order = [...new Set(order.map(String))].filter((e) => { const [pid, ...m] = e.split('::'); return findProvider(pid) && m.join('::'); }).slice(0, 60);
      saveStore(); brainStatus(); return send(res, 200, { order: store.order });
    }
    if (req.method === 'POST' && url.pathname === '/api/chat') {
      const { history } = JSON.parse(await readBody(req, 128 * 1024));
      if (!Array.isArray(history) || !history.length) return send(res, 400, { error: 'empty' });
      await refreshAgents();
      try { return send(res, 200, await chat(history)); }
      catch (e) { return send(res, 502, { error: e.name === 'TimeoutError' ? 'The free model took too long. Try again.' : e.message.slice(0, 300) }); }
    }
    if (req.method === 'POST' && url.pathname === '/api/token') {
      await refreshAgents();
      const token = await createToken();
      return send(res, 200, { token, model: LIVE_MODEL, voice: LIVE_VOICE, systemInstruction: brief('voice'), tools: tools() });
    }
    if (req.method === 'POST' && url.pathname === '/api/tool') {
      const { name, args } = JSON.parse(await readBody(req));
      return send(res, 200, await runTool(name, args));
    }
    return send(res, 404, { error: 'not found' });
  } catch (e) {
    console.error(e.message);
    return send(res, e.code === 413 ? 413 : 500, { error: e.message.slice(0, 300) });
  }
});
server.listen(PORT, () => console.log(`Jarvis Live on :${PORT}, model ${LIVE_MODEL}, agents from ${N8N_AGENTS_URL}`));
