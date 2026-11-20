// Jarvis Live — browser side.
// 1. Ask our server for a one-time Gemini token.  2. Open a WebSocket straight to Google.
// 3. Stream the microphone (16 kHz PCM), play Jarvis's voice (24 kHz PCM), show both transcripts.
// 4. When Gemini calls a tool, ask our server (which asks n8n) and send the answer back.

const WS_BASE = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained';
const $ = (id) => document.getElementById(id);
const orb = $('talk'), orbLabel = $('orbLabel'), statusEl = $('status'), logEl = $('log');

let ws = null, micCtx = null, micStream = null, worklet = null;
let playCtx = null, nextPlay = 0, playing = new Set();
let live = false, wakeLock = null;
let youLine = null, jarvisLine = null;

const setStatus = (t) => { statusEl.textContent = t; };
function addLine(cls, text) {
  const p = document.createElement('p'); p.className = cls; p.textContent = text;
  logEl.appendChild(p); logEl.scrollTop = logEl.scrollHeight; return p;
}
function b64FromBuffer(buf) {
  const bytes = new Uint8Array(buf); let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
function bufferFromB64(b64) {
  const s = atob(b64); const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out.buffer;
}

// ---------- playback (Jarvis's voice) ----------
function playPcm24k(b64) {
  const pcm = new Int16Array(bufferFromB64(b64));
  const audio = playCtx.createBuffer(1, pcm.length, 24000);
  const ch = audio.getChannelData(0);
  for (let i = 0; i < pcm.length; i++) ch[i] = pcm[i] / 0x8000;
  const src = playCtx.createBufferSource();
  src.buffer = audio; src.connect(playCtx.destination);
  nextPlay = Math.max(nextPlay, playCtx.currentTime + 0.05);
  src.start(nextPlay); nextPlay += audio.duration;
  playing.add(src); orb.classList.add('speaking');
  src.onended = () => { playing.delete(src); if (!playing.size) orb.classList.remove('speaking'); };
}
function stopPlayback() {           // you interrupted Jarvis
  for (const s of playing) { try { s.stop(); } catch {} }
  playing.clear(); nextPlay = 0; orb.classList.remove('speaking');
}

// ---------- tools (Jarvis's hands, via n8n) ----------
async function handleToolCall(toolCall) {
  const responses = [];
  for (const fc of toolCall.functionCalls || []) {
    addLine('tool', `⚙ ${fc.name} …`);
    let result;
    try {
      const r = await fetch('/api/tool', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: fc.name, args: fc.args }) });
      result = await r.json();
    } catch (e) { result = { ok: false, error: String(e) }; }
    addLine('tool', `⚙ ${fc.name}: ${result.ok === false ? 'failed: ' + (result.error || '') : 'done'}`);
    responses.push({ id: fc.id, name: fc.name, response: { output: result } });
  }
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ toolResponse: { functionResponses: responses } }));
}

// ---------- messages from Gemini ----------
async function onMessage(ev) {
  const text = typeof ev.data === 'string' ? ev.data : await ev.data.text();
  let msg; try { msg = JSON.parse(text); } catch { return; }

  if (msg.setupComplete) { setStatus('Listening… talk now'); return; }
  if (msg.toolCall) { handleToolCall(msg.toolCall); return; }
  if (msg.goAway) { setStatus('This call is ending soon (Google limit). Tap to end, then tap again for a new call.'); }

  const sc = msg.serverContent;
  if (!sc) return;
  if (sc.interrupted) stopPlayback();
  if (sc.inputTranscription?.text) {
    youLine = youLine || addLine('you', 'You: ');
    youLine.textContent += sc.inputTranscription.text;
  }
  if (sc.outputTranscription?.text) {
    jarvisLine = jarvisLine || addLine('jarvis', 'Jarvis: ');
    jarvisLine.textContent += sc.outputTranscription.text;
  }
  for (const part of sc.modelTurn?.parts || []) {
    if (part.inlineData?.data && (part.inlineData.mimeType || '').startsWith('audio/pcm')) playPcm24k(part.inlineData.data);
  }
  if (sc.turnComplete) { youLine = null; jarvisLine = null; setStatus('Listening…'); }
}

// ---------- start / stop ----------
async function start() {
  orb.disabled = true; setStatus('Connecting…');
  try {
    const r = await fetch('/api/token', { method: 'POST' });
    if (r.status === 401) { location.reload(); return; }
    const cfg = await r.json();
    if (!r.ok) throw new Error(cfg.error || `server ${r.status}`);

    micStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    micCtx = new AudioContext();
    playCtx = playCtx || new AudioContext();
    await playCtx.resume();
    await micCtx.audioWorklet.addModule('/pcm-worklet.js');

    ws = new WebSocket(`${WS_BASE}?access_token=${encodeURIComponent(cfg.token)}`);
    ws.onopen = () => {
      ws.send(JSON.stringify({ setup: {
        model: `models/${cfg.model}`,
        generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: cfg.voice } } } },
        systemInstruction: { parts: [{ text: cfg.systemInstruction }] },
        tools: cfg.tools,
        inputAudioTranscription: {},
        outputAudioTranscription: {},
      } }));
      const src = micCtx.createMediaStreamSource(micStream);
      worklet = new AudioWorkletNode(micCtx, 'pcm-recorder');
      worklet.port.onmessage = (e) => {
        if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ realtimeInput: { audio: { data: b64FromBuffer(e.data), mimeType: 'audio/pcm;rate=16000' } } }));
      };
      src.connect(worklet);
    };
    ws.onmessage = onMessage;
    ws.onerror = () => setStatus('Connection error');
    ws.onclose = (e) => { if (live) { setStatus(`Call ended${e.reason ? ': ' + e.reason : ''} (code ${e.code})`); stop(false); } };

    live = true; orb.classList.add('on'); orbLabel.textContent = 'Tap to end';
    try { wakeLock = await navigator.wakeLock?.request('screen'); } catch {}
  } catch (e) {
    setStatus(`Couldn't start: ${e.message}`); stop(false);
  } finally { orb.disabled = false; }
}

function stop(closeSocket = true) {
  live = false;
  if (closeSocket && ws) { try { ws.close(); } catch {} }
  ws = null;
  try { worklet?.disconnect(); } catch {}
  micStream?.getTracks().forEach((t) => t.stop());
  micCtx?.close().catch(() => {});
  micCtx = null; micStream = null; worklet = null;
  stopPlayback();
  wakeLock?.release?.().catch(() => {}); wakeLock = null;
  orb.classList.remove('on'); orbLabel.textContent = 'Tap to talk';
  if (closeSocket) setStatus('Call ended');
}

orb.addEventListener('click', () => (live ? stop() : start()));
