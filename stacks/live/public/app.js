// JARVIS // Live — dashboard + live voice.
//   • /api/events (Server-Sent Events): metrics, agent activity, alerts → panels update by themselves
//   • Voice: one-time token from our server → WebSocket straight to Gemini Live (16 kHz in, 24 kHz out)
//   • Tools: Gemini calls ask_agent / send_to_telegram → our server → agents (n8n or built-in)
//   • Avatar: Jarvis's digital twin — breathing and blinking (idle), ripple (thinking), mouth shapes from the live voice (speaking)
//   • Globe: your server and the agent ring; working agents fire arcs

import { Twin } from '/avatar.js';
import { Globe } from '/globe.js';

const WS_BASE = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained';
const $ = (id) => document.getElementById(id);
const state = { agents: [], byId: {}, tasks: [], active: new Map(), metrics: {}, hist: [], live: false, avatar: 'idle',
  brain: localStorage.getItem('jarvis.brain') || 'bifrost', history: [], speakReplies: localStorage.getItem('jarvis.speak') !== 'off', synthLevel: 0 };

// ---------------------------------------------------------------- helpers
const fmtTime = (ts) => new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
function log(cls, text, ts = Date.now()) {
  const el = $('log'), p = document.createElement('p'); p.className = cls;
  const t = document.createElement('span'); t.className = 't'; t.textContent = fmtTime(ts);
  p.append(t, document.createTextNode(text)); el.append(p);
  while (el.children.length > 200) el.firstChild.remove();
  el.scrollTop = el.scrollHeight; return p;
}
function flash(id) { const el = $(id); if (!el) return; el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash'); }
const b64FromBuffer = (buf) => { const b = new Uint8Array(buf); let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000)); return btoa(s); };
const bufferFromB64 = (b64) => { const s = atob(b64), o = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) o[i] = s.charCodeAt(i); return o.buffer; };
function fitCanvas(c) { const r = c.getBoundingClientRect(), d = devicePixelRatio || 1; if (c.width !== Math.round(r.width * d) || c.height !== Math.round(r.height * d)) { c.width = Math.round(r.width * d); c.height = Math.round(r.height * d); } return { ctx: c.getContext('2d'), w: c.width, h: c.height, d }; }
setInterval(() => { $('clock').textContent = new Date().toLocaleString([], { weekday: 'short', hour: '2-digit', minute: '2-digit', second: '2-digit' }); }, 1000);

// ---------------------------------------------------------------- avatar (digital twin) + globe
const avatar = $('avatar');
const twin = new Twin($('twin'));
const globe = new Globe($('globe'));
function setAvatar(s) { if (state.avatar === s) return; state.avatar = s; avatar.dataset.state = s; twin.setState(s); $('avatarState').textContent = s; }

// ---------------------------------------------------------------- system integrity
const RING = 264;
function setRing(id, pct) { const el = $(id); el.querySelector('.fg').style.strokeDashoffset = RING * (1 - Math.min(100, pct) / 100); el.querySelector('b').textContent = `${Math.round(pct)}%`; }
function showMetrics(m) {
  state.metrics = m; state.hist.push({ cpu: m.cpu, mem: m.mem }); if (state.hist.length > 90) state.hist.shift();
  setRing('ringCpu', m.cpu); setRing('ringMem', m.mem);
  const scale = (k) => Math.min(100, (Math.log10(1 + k) / Math.log10(1 + 20000)) * 100);   // log scale up to 20 Mbit/s
  $('barRx').style.width = scale(m.rxKbps) + '%'; $('barTx').style.width = scale(m.txKbps) + '%';
  $('valRx').textContent = m.rxKbps >= 1000 ? (m.rxKbps / 1000).toFixed(1) + ' Mb/s' : m.rxKbps.toFixed(0) + ' kb/s';
  $('valTx').textContent = m.txKbps >= 1000 ? (m.txKbps / 1000).toFixed(1) + ' Mb/s' : m.txKbps.toFixed(0) + ' kb/s';
  $('valLoad').textContent = m.load.toFixed(2);
  const h = Math.floor(m.uptime / 3600); $('valUp').textContent = `${Math.floor(h / 24)}d ${h % 24}h`;
  $('valRam').textContent = `${m.memTotalGb} GB`;
  drawSpark();
}
function drawSpark() {
  const { ctx, w, h, d } = fitCanvas($('spark')); ctx.clearRect(0, 0, w, h);
  for (const [k, col] of [['cpu', '#4cc9ff'], ['mem', '#9d7bff']]) {
    ctx.beginPath(); state.hist.forEach((p, i) => { const x = (i / 89) * w, y = h - (p[k] / 100) * (h - 4 * d) - 2 * d; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
    ctx.strokeStyle = col; ctx.lineWidth = 1.5 * d; ctx.shadowColor = col; ctx.shadowBlur = 6 * d; ctx.stroke();
  }
}

// ---------------------------------------------------------------- agents: roster, graph, timeline
const CORE = { id: 'core', name: 'Jarvis', role: 'Orchestrator (Gemini Live)', color: '#38c8ff' };
function setupAgents(list, link) {
  state.agents = [CORE, ...list]; state.byId = Object.fromEntries(state.agents.map((a) => [a.id, a]));
  for (const id of [...state.active.keys()]) if (!state.byId[id]) state.active.delete(id);
  globe.setAgents(list); globe.setActive(state.active); $('roster').innerHTML = '';
  if (link) { const el = $('n8nState'); el.textContent = link.ok ? `n8n ${link.note}` : link.note; el.className = link.ok ? 'ok' : 'bad'; }
  if (!list.length) {
    const li = document.createElement('li'); li.className = 'empty';
    li.innerHTML = '<b>No agents yet.</b> Jarvis can talk and answer questions now. Agents are added in n8n, one per upcoming lesson (calendar, email, memory, SAR desk…), and appear here by themselves.';
    $('roster').append(li);
  }
  for (const a of list) {
    const li = document.createElement('li'); li.id = `ag-${a.id}`; li.style.setProperty('--c', a.color);
    li.innerHTML = `<span class="dot"></span><b></b><em></em>`;
    li.querySelector('b').textContent = a.name; li.querySelector('em').textContent = a.role;
    $('roster').append(li);
  }
}
function agentActivity(ev) {
  const a = state.byId[ev.agent] || { id: ev.agent, name: ev.agent, color: '#8c6cff', unknown: true };
  const li = $(`ag-${a.id}`); const em = li?.querySelector('em');
  if (ev.status === 'start' && !a.unknown) {
    state.active.set(a.id, ev.task); state.tasks.push({ agent: a.id, task: ev.task, start: ev.ts, end: null });
    li?.classList.add('active'); li?.classList.remove('error'); if (em) em.textContent = ev.task;
    log('agent', `${a.name}: ${ev.task}`, ev.ts);
  } else if (ev.status === 'progress') {
    if (em) em.textContent = ev.task; log('agent', `${a.name}: ${ev.task}`, ev.ts);
  } else if (ev.status === 'done' || ev.status === 'error') {
    state.active.delete(a.id);
    const t = [...state.tasks].reverse().find((x) => x.agent === a.id && !x.end); if (t) { t.end = ev.ts; t.error = ev.status === 'error'; }
    li?.classList.remove('active'); if (ev.status === 'error') li?.classList.add('error');
    if (em) em.textContent = ev.status === 'error' ? `failed: ${ev.detail}` : (ev.detail || 'done');
    log(ev.status === 'error' ? 'err' : 'agent', `${a.name} ${ev.status === 'error' ? 'failed' : 'done'}${ev.detail ? ': ' + ev.detail : ''}`, ev.ts);
  } else if (ev.status === 'delegate') {
    state.tasks.push({ agent: a.id, task: ev.task, start: ev.ts, end: ev.ts + 900 });
    log('agent', ev.task, ev.ts);
  } else {
    state.tasks.push({ agent: a.id, task: ev.task, start: ev.ts, end: ev.ts + 1500 });
    log(ev.status === 'alert' ? 'alert' : 'sys', `${a.name}: ${ev.task}${ev.detail ? ' — ' + ev.detail : ''}`, ev.ts);
  }
  if (state.tasks.length > 300) state.tasks.splice(0, state.tasks.length - 300);
  $('opsSummary').textContent = state.active.size ? `${state.active.size} agent${state.active.size > 1 ? 's' : ''} working` : 'all agents idle';
  globe.setActive(state.active);
  if (ev.status === 'start') globe.ping(-35 + Math.random() * 95, -180 + Math.random() * 360, a.color);
  if (state.active.size) { setAvatar('thinking'); flash('pGraph'); }
  else if (state.avatar === 'thinking' && !audio.sources.size) setAvatar(state.live ? 'listening' : 'idle');
  drawGantt();
}
const SVGNS = 'http://www.w3.org/2000/svg';
function drawGantt() {
  const { ctx, w, h, d } = fitCanvas($('gantt')); ctx.clearRect(0, 0, w, h);
  const now = Date.now(), span = 3 * 60e3, left = 118 * d, rows = state.agents.length > 1 ? state.agents : [], rh = Math.min(26 * d, (h - 18 * d) / Math.max(1, rows.length));
  ctx.font = `${11 * d}px Segoe UI, sans-serif`; ctx.textBaseline = 'middle';
  for (let s = 0; s <= 180; s += 30) {                                 // grid every 30 s
    const x = left + ((span - s * 1000) / span) * (w - left);
    ctx.strokeStyle = 'rgba(76,201,255,.1)'; ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h - 14 * d); ctx.stroke();
    ctx.fillStyle = '#6f93ab'; ctx.fillText(s ? `-${s}s` : 'now', x - (s ? 14 : 26) * d, h - 7 * d);
  }
  rows.forEach((a, i) => {
    const y = i * rh + 4 * d;
    ctx.fillStyle = state.active.has(a.id) ? a.color : '#8fb3c9'; ctx.fillText(a.name, 6 * d, y + rh / 2);
    for (const t of state.tasks.filter((x) => x.agent === a.id)) {
      const end = t.end || now; if (end < now - span) continue;
      const x1 = left + Math.max(0, (t.start - (now - span)) / span) * (w - left), x2 = left + ((end - (now - span)) / span) * (w - left);
      ctx.fillStyle = t.error ? '#ff5c7a' : a.color; ctx.globalAlpha = t.end ? 0.55 : 0.95;
      ctx.shadowColor = a.color; ctx.shadowBlur = t.end ? 0 : 10 * d;
      ctx.fillRect(Math.min(x1, x2 - 8 * d), y + rh * 0.22, Math.max(8 * d, x2 - x1), rh * 0.56); ctx.globalAlpha = 1; ctx.shadowBlur = 0;
    }
  });
  if (!rows.length) { ctx.fillStyle = '#6a8aa3'; ctx.font = `${13 * d}px Segoe UI, sans-serif`; ctx.fillText('Agent tasks appear here once agents are added in n8n.', 12 * d, 22 * d); }
  ctx.strokeStyle = '#38c8ff'; ctx.beginPath(); ctx.moveTo(w - 1, 0); ctx.lineTo(w - 1, h - 14 * d); ctx.stroke();
}
setInterval(drawGantt, 1000);
addEventListener('resize', () => { drawGantt(); drawSpark(); });

// ---------------------------------------------------------------- live event stream
function connectEvents() {
  const es = new EventSource('/api/events');
  es.addEventListener('hello', (e) => {
    const d = JSON.parse(e.data); $('linkState').textContent = 'connected'; $('linkState').classList.add('on');
    setupAgents(d.agents, d.n8n); showBifrost(d.bifrost); if (d.metrics?.mem !== undefined) showMetrics(d.metrics);
    if (!$('log').children.length) { log('sys', `Connected. Brain: ${state.brain === 'bifrost' ? 'Bifrost (' + (d.bifrost?.note || '…') + ')' : 'Gemini Live (' + d.model + ')'}. ${d.n8n.ok ? 'n8n ' + d.n8n.note + '.' : d.n8n.note + '.'}`); for (const ev of d.recent) if (ev.type === 'agent' && Date.now() - ev.ts < 3 * 60e3) agentActivity(ev); }
  });
  es.addEventListener('agents', (e) => { const d = JSON.parse(e.data); setupAgents(d.agents, d.n8n); log('sys', `Agent list updated: n8n ${d.n8n.note}.`); });
  es.addEventListener('bifrost', (e) => { const d = JSON.parse(e.data); showBifrost(d.bifrost); log('sys', `Bifrost: ${d.bifrost.note}.`); });
  es.addEventListener('metrics', (e) => showMetrics(JSON.parse(e.data)));
  es.addEventListener('agent', (e) => agentActivity(JSON.parse(e.data)));
  es.addEventListener('alert', (e) => {
    const a = JSON.parse(e.data); log('alert', `${state.byId[a.agent]?.name || a.agent}: ${a.text}`, a.ts); flash('pLog');
    if (a.speak && session.ws?.readyState === WebSocket.OPEN) sendText(`[EVENT from ${a.agent}] ${a.text}`, true);
  });
  es.onerror = () => { $('linkState').textContent = 'reconnecting…'; $('linkState').classList.remove('on'); fetch('/api/events', { method: 'HEAD' }).then((r) => { if (r.status === 401) location.reload(); }).catch(() => {}); };
}
connectEvents();

// ---------------------------------------------------------------- audio: playback, analysers, waveforms
const audio = { play: null, outAnalyser: null, next: 0, sources: new Set(), micAnalyser: null, jaw: 0 };
function ensurePlayback() {
  if (audio.play) return;
  audio.play = new AudioContext();
  audio.outAnalyser = audio.play.createAnalyser(); audio.outAnalyser.fftSize = 1024;
  audio.outAnalyser.connect(audio.play.destination);
}
function playPcm24k(b64) {
  const pcm = new Int16Array(bufferFromB64(b64)); const buf = audio.play.createBuffer(1, pcm.length, 24000); const ch = buf.getChannelData(0);
  for (let i = 0; i < pcm.length; i++) ch[i] = pcm[i] / 0x8000;
  const src = audio.play.createBufferSource(); src.buffer = buf; src.connect(audio.outAnalyser);
  audio.next = Math.max(audio.next, audio.play.currentTime + 0.05); src.start(audio.next); audio.next += buf.duration;
  audio.sources.add(src); setAvatar('speaking');
  src.onended = () => { audio.sources.delete(src); if (!audio.sources.size && state.avatar === 'speaking') setAvatar(state.live ? 'listening' : 'idle'); };
}
function stopPlayback() { for (const s of audio.sources) { try { s.stop(); } catch {} } audio.sources.clear(); audio.next = 0; }
const td = new Uint8Array(1024);
function drawWave(canvas, analyser, color, idleAmp) {
  const { ctx, w, h, d } = fitCanvas(canvas); ctx.clearRect(0, 0, w, h);
  ctx.beginPath(); const mid = h / 2; let rms = 0;
  if (analyser) { analyser.getByteTimeDomainData(td); }
  const n = 96;
  for (let i = 0; i < n; i++) {
    let v;
    if (analyser) { const s = (td[Math.floor((i / n) * td.length)] - 128) / 128; rms += s * s; v = s; }
    else v = Math.sin(i / 6 + performance.now() / 600) * idleAmp;
    const x = (i / (n - 1)) * w, y = mid + v * (h * 0.42);
    i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
  }
  ctx.strokeStyle = color; ctx.lineWidth = 2 * d; ctx.shadowColor = color; ctx.shadowBlur = 10 * d; ctx.stroke();
  return Math.sqrt(rms / n);
}
const fd = new Uint8Array(512);
function brightness() {                       // share of high frequencies: "ee/s" sounds → wide mouth, "oo" → round
  if (!audio.outAnalyser) return 0.5;
  audio.outAnalyser.getByteFrequencyData(fd); let lo = 0, hi = 0;
  for (let i = 2; i < 40; i++) lo += fd[i]; for (let i = 40; i < 160; i++) hi += fd[i];
  return lo + hi ? Math.min(1, (hi / (lo + hi)) * 2.2) : 0.5;
}
function frame(t) {
  const speaking = audio.sources.size > 0, synth = speechSynthesis.speaking;
  const outRms = drawWave($('avWave'), speaking ? audio.outAnalyser : null, '#38c8ff', synth ? 0.35 * state.synthLevel + 0.05 : state.live ? 0.04 : 0.015);
  drawWave($('dockWave'), speaking ? audio.outAnalyser : audio.micAnalyser, speaking ? '#38c8ff' : '#8c6cff', 0.02);
  if (synth) state.synthLevel += ((0.35 + 0.45 * Math.abs(Math.sin(t / 95)) * (0.6 + 0.4 * Math.sin(t / 37))) - state.synthLevel) * 0.3;
  twin.update(t, speaking ? Math.min(1, outRms * 6) : synth ? state.synthLevel : 0, speaking ? brightness() : 0.4 + 0.3 * Math.sin(t / 140));
  globe.draw(t);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// ---------------------------------------------------------------- live session (voice + text)
const session = { ws: null, micCtx: null, micStream: null, worklet: null, youLine: null, jarvisLine: null, pendingText: null, ready: false };
async function handleToolCall(toolCall) {
  setAvatar('thinking');
  const calls = toolCall.functionCalls || [];
  const responses = await Promise.all(calls.map(async (fc) => {          // several agents run in parallel
    let result;
    try { const r = await fetch('/api/tool', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: fc.name, args: fc.args }) }); result = await r.json(); }
    catch (e) { result = { ok: false, error: String(e) }; }
    return { id: fc.id, name: fc.name, response: { output: result } };
  }));
  if (session.ws?.readyState === WebSocket.OPEN) session.ws.send(JSON.stringify({ toolResponse: { functionResponses: responses } }));
}
async function onMessage(ev) {
  const text = typeof ev.data === 'string' ? ev.data : await ev.data.text();
  let msg; try { msg = JSON.parse(text); } catch { return; }
  if (msg.setupComplete) { session.ready = true; log('sys', 'Voice link open. Talk naturally; you can interrupt.'); setAvatar('listening'); if (session.pendingText) { sendText(session.pendingText); session.pendingText = null; } return; }
  if (msg.toolCall) { handleToolCall(msg.toolCall); return; }
  if (msg.goAway) log('sys', 'Google will end this voice session soon; tap the mic again for a new one.');
  const sc = msg.serverContent; if (!sc) return;
  if (sc.interrupted) { stopPlayback(); setAvatar('listening'); }
  if (sc.inputTranscription?.text) { session.youLine = session.youLine || log('you', 'You: '); session.youLine.lastChild.textContent += sc.inputTranscription.text; setAvatar('thinking'); }
  if (sc.outputTranscription?.text) { session.jarvisLine = session.jarvisLine || log('jarvis', 'Jarvis: '); session.jarvisLine.lastChild.textContent += sc.outputTranscription.text; }
  for (const part of sc.modelTurn?.parts || []) {
    if (part.inlineData?.data && (part.inlineData.mimeType || '').startsWith('audio/pcm')) playPcm24k(part.inlineData.data);
    else if (part.text && !sc.outputTranscription) { session.jarvisLine = session.jarvisLine || log('jarvis', 'Jarvis: '); session.jarvisLine.lastChild.textContent += part.text; }
  }
  if (sc.turnComplete) { session.youLine = null; session.jarvisLine = null; if (!audio.sources.size) setAvatar('listening'); }
}
async function startLive() {
  $('talk').disabled = true; log('sys', 'Opening voice link…'); setAvatar('thinking');
  try {
    const r = await fetch('/api/token', { method: 'POST' });
    if (r.status === 401) { location.reload(); return; }
    const cfg = await r.json(); if (!r.ok) throw new Error(cfg.error || `server ${r.status}`);
    ensurePlayback(); await audio.play.resume();
    session.micStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    session.micCtx = new AudioContext(); await session.micCtx.audioWorklet.addModule('/pcm-worklet.js');
    const src = session.micCtx.createMediaStreamSource(session.micStream);
    audio.micAnalyser = session.micCtx.createAnalyser(); audio.micAnalyser.fftSize = 1024; src.connect(audio.micAnalyser);

    const ws = new WebSocket(`${WS_BASE}?access_token=${encodeURIComponent(cfg.token)}`); session.ws = ws; session.ready = false;
    ws.onopen = () => {
      ws.send(JSON.stringify({ setup: {
        model: `models/${cfg.model}`,
        generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: cfg.voice } } } },
        systemInstruction: { parts: [{ text: cfg.systemInstruction }] }, tools: cfg.tools,
        inputAudioTranscription: {}, outputAudioTranscription: {},
      } }));
      session.worklet = new AudioWorkletNode(session.micCtx, 'pcm-recorder');
      session.worklet.port.onmessage = (e) => { if (session.ready && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ realtimeInput: { audio: { data: b64FromBuffer(e.data), mimeType: 'audio/pcm;rate=16000' } } })); };
      src.connect(session.worklet);
    };
    ws.onmessage = onMessage;
    ws.onerror = () => log('err', 'Voice link error.');
    ws.onclose = (e) => { if (state.live) { log('sys', `Voice link closed${e.reason ? ': ' + e.reason : ''} (code ${e.code}).`); stopLive(false); } };
    state.live = true; $('talk').classList.add('on'); $('liveDot').textContent = 'live'; $('liveDot').classList.add('on');
    try { session.wake = await navigator.wakeLock?.request('screen'); } catch {}
  } catch (e) { log('err', `Couldn't start voice: ${e.message}`); stopLive(false); }
  finally { $('talk').disabled = false; }
}
function stopLive(close = true) {
  state.live = false; session.ready = false;
  if (close && session.ws) { try { session.ws.close(); } catch {} }
  session.ws = null; try { session.worklet?.disconnect(); } catch {}
  session.micStream?.getTracks().forEach((t) => t.stop()); session.micCtx?.close().catch(() => {});
  Object.assign(session, { micCtx: null, micStream: null, worklet: null }); audio.micAnalyser = null;
  stopPlayback(); session.wake?.release?.().catch(() => {});
  $('talk').classList.remove('on'); $('liveDot').textContent = 'standby'; $('liveDot').classList.remove('on'); setAvatar('idle');
  if (close) log('sys', 'Voice link closed.');
}
function sendText(text, system = false) {
  if (!session.ws || !session.ready) { session.pendingText = text; if (!state.live) startLive(); return; }
  session.ws.send(JSON.stringify({ realtimeInput: { text } }));
  if (!system) setAvatar('thinking');
}
// ---------------------------------------------------------------- Bifrost brain (text + push-to-talk)
function showBifrost(b) { if (!b) return; const el = $('bifrostState'); el.textContent = b.ok ? '● ' + b.note.replace('connected · ', '') : '● ' + b.note; el.className = b.ok ? 'ok' : 'bad'; el.title = b.ok ? `model ${b.model}` : b.note; }
function setBrain(b) {
  if (b === state.brain) return;
  if (state.live) stopLive();
  stopListening(); speechSynthesis.cancel();
  state.brain = b; try { localStorage.setItem('jarvis.brain', b); } catch {}
  document.querySelectorAll('.brain button').forEach((x) => x.setAttribute('aria-checked', String(x.dataset.brain === b)));
  log('sys', b === 'bifrost' ? 'Brain: Bifrost (your free models). Type, or tap the mic and speak.' : 'Brain: Gemini Live. Tap the mic for a real-time voice call.');
}
document.querySelectorAll('.brain button').forEach((x) => x.addEventListener('click', () => setBrain(x.dataset.brain)));
document.querySelectorAll('.brain button').forEach((x) => x.setAttribute('aria-checked', String(x.dataset.brain === state.brain)));
$('lang').value = localStorage.getItem('jarvis.lang') || 'en-US';
$('lang').addEventListener('change', () => { try { localStorage.setItem('jarvis.lang', $('lang').value); } catch {} });
const speakBtn = $('speakToggle'); speakBtn.setAttribute('aria-pressed', String(state.speakReplies));
speakBtn.addEventListener('click', () => { state.speakReplies = !state.speakReplies; speakBtn.setAttribute('aria-pressed', String(state.speakReplies)); if (!state.speakReplies) speechSynthesis.cancel(); try { localStorage.setItem('jarvis.speak', state.speakReplies ? 'on' : 'off'); } catch {} });

function speak(text) {
  if (!state.speakReplies || !('speechSynthesis' in window)) { setAvatar('idle'); return; }
  speechSynthesis.cancel();
  const urdu = /[\u0600-\u06FF]/.test(text);
  const u = new SpeechSynthesisUtterance(text.replace(/[*_#`>|]/g, ' ').replace(/\[(\d+)\]/g, ''));
  const voices = speechSynthesis.getVoices();
  const want = urdu ? ['ur', 'hi'] : [($('lang').value || 'en').slice(0, 2), 'en'];
  u.voice = want.map((l) => voices.find((v) => v.lang.toLowerCase().startsWith(l))).find(Boolean) || null;
  u.lang = u.voice?.lang || (urdu ? 'ur-PK' : 'en-US'); u.rate = 1.02;
  u.onstart = () => setAvatar('speaking'); u.onend = u.onerror = () => setAvatar('idle');
  speechSynthesis.speak(u);
}
let busy = false;
async function askBifrost(text) {
  if (busy) return; busy = true;
  state.history.push({ role: 'user', content: text });
  setAvatar('thinking'); const t0 = performance.now();
  try {
    const r = await fetch('/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ history: state.history }) });
    if (r.status === 401) { location.reload(); return; }
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || `server ${r.status}`);
    state.history.push({ role: 'assistant', content: j.reply });
    if (state.history.length > 30) state.history.splice(0, state.history.length - 30);
    log('jarvis', `Jarvis: ${j.reply}`).title = `${j.model} · ${Math.round(performance.now() - t0)} ms`;
    speak(j.reply);
  } catch (e) { state.history.pop(); log('err', `Bifrost: ${e.message}`); setAvatar('idle'); }
  finally { busy = false; }
}

// push-to-talk for the Bifrost brain: the browser turns speech into text (Chrome, Edge, Android, Safari)
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
let rec = null;
function stopListening() { if (rec) { try { rec.abort(); } catch {} rec = null; } $('talk').classList.remove('on'); $('liveDot').textContent = 'standby'; $('liveDot').classList.remove('on'); }
function listenOnce() {
  if (!SR) { log('err', "This browser can't turn speech into text. Use Chrome or Edge, type instead, or switch to Gemini Live."); return; }
  if (rec) { stopListening(); setAvatar('idle'); return; }
  speechSynthesis.cancel();
  rec = new SR(); rec.lang = $('lang').value; rec.interimResults = true; rec.maxAlternatives = 1;
  let line = null, finalText = '';
  rec.onresult = (e) => {
    let interim = ''; finalText = '';
    for (const r of e.results) (r.isFinal ? (finalText += r[0].transcript) : (interim += r[0].transcript));
    line = line || log('you', 'You: '); line.lastChild.textContent = 'You: ' + (finalText || interim);
  };
  rec.onerror = (e) => { if (e.error !== 'aborted') log('err', e.error === 'not-allowed' ? 'Microphone blocked: allow it in the browser’s site settings.' : `Speech recognition: ${e.error}`); };
  rec.onend = () => { const said = finalText.trim(); stopListening(); if (said) askBifrost(said); else setAvatar('idle'); };
  rec.start(); setAvatar('listening');
  $('talk').classList.add('on'); $('liveDot').textContent = 'listening'; $('liveDot').classList.add('on');
}

$('talk').addEventListener('click', () => {
  if (state.brain === 'bifrost') return listenOnce();
  return state.live ? stopLive() : startLive();
});
$('cmdForm').addEventListener('submit', (e) => {
  e.preventDefault(); const v = $('cmd').value.trim(); if (!v) return;
  log('you', `You (typed): ${v}`); $('cmd').value = '';
  if (state.brain === 'bifrost' && !state.live) askBifrost(v); else sendText(v);
});

// ---------------------------------------------------------------- resizable panels (drag the thin gutters)
const LAYOUT_KEY = 'jarvis.layout';
const layout = JSON.parse(localStorage.getItem(LAYOUT_KEY) || '{}');
for (const [id, size] of Object.entries(layout)) { const el = $(id); if (el) (el.parentElement.classList.contains('col') && el.classList.contains('panel') ? (el.style.height = size + 'px', el.style.flex = 'none') : (el.style.width = size + 'px')); }
document.querySelectorAll('.gutter').forEach((g) => {
  g.addEventListener('pointerdown', (e) => {
    const target = $(g.dataset.target), isCol = g.classList.contains('gx'), right = g.dataset.side === 'right';
    const start = isCol ? e.clientX : e.clientY, size0 = isCol ? target.offsetWidth : target.offsetHeight;
    g.setPointerCapture(e.pointerId);
    const move = (ev) => {
      const delta = (isCol ? ev.clientX : ev.clientY) - start; const s = Math.max(isCol ? 180 : 110, size0 + (right ? -delta : delta));
      if (isCol) target.style.width = s + 'px'; else { target.style.height = s + 'px'; target.style.flex = 'none'; }
      layout[target.id] = s; drawGantt();
    };
    const up = () => { g.removeEventListener('pointermove', move); g.removeEventListener('pointerup', up); try { localStorage.setItem(LAYOUT_KEY, JSON.stringify(layout)); } catch {} };
    g.addEventListener('pointermove', move); g.addEventListener('pointerup', up);
  });
});

$('refreshAgents').addEventListener('click', async () => {
  const r = await fetch('/api/agents/refresh', { method: 'POST' }); if (!r.ok) return;
  const d = await r.json(); setupAgents(d.agents, d.n8n); showBifrost(d.bifrost); log('sys', `Asked n8n for agents: ${d.n8n.ok ? 'n8n ' : ''}${d.n8n.note}.`);
});
