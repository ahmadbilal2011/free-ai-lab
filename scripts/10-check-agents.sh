#!/usr/bin/env bash
# free-ai-lab - Lesson 10: check every link between Jarvis Live, n8n and the Reminders agent.
#   bash 10-check-agents.sh
# It only reads and tests (it asks the agent for your reminder list); it changes nothing.
set -uo pipefail
c_ok='\033[1;32m'; c_bad='\033[1;31m'; c_off='\033[0m'

if ! docker ps --format '{{.Names}}' | grep -qx jarvis-live; then
  echo -e "${c_bad}✗ Jarvis Live isn't running.${c_off} Run Lesson 10 Part A (bash 09-install-live.sh)."; exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx n8n; then
  echo -e "${c_bad}✗ n8n isn't running.${c_off} Check: docker ps -a ; docker logs --tail 30 n8n"; exit 1
fi

# Everything below runs inside the jarvis-live container, so it sees exactly what Jarvis sees.
docker exec -i jarvis-live node - <<'JS'
const G = '\x1b[1;32m', R = '\x1b[1;31m', Y = '\x1b[1;33m', O = '\x1b[0m';
const ok = (t) => console.log(`${G}✓${O} ${t}`), bad = (t, fix) => { console.log(`${R}✗ ${t}${O}\n    → ${fix}`); process.exitCode = 1; };
const warn = (t, fix) => console.log(`${Y}! ${t}${O}\n    → ${fix}`);
const env = process.env, H = { 'X-Jarvis-Secret': env.N8N_TOOL_SECRET || '' };
const get = async (url, opt = {}) => { try { const r = await fetch(url, { ...opt, signal: AbortSignal.timeout(20e3) }); return { status: r.status, text: await r.text() }; } catch (e) { return { status: 0, text: String(e.message) }; } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  console.log('1/5  Jarvis Live version');
  let h = JSON.parse((await get('http://127.0.0.1:8080/health')).text || '{}');
  if (h.version === '10') ok('Jarvis Live is up to date (Lesson 10)');
  else return bad('Jarvis Live is the old version, so it doesn\'t pass agents\' task formats or the time to the AI',
    'Run Part A: curl -fsSLO https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-live.sh && bash 09-install-live.sh');

  console.log('2/5  n8n agent list (GET /webhook/jarvis-agents)');
  const a = await get(env.N8N_AGENTS_URL, { headers: H });
  let list = [];
  try { const j = JSON.parse(a.text); list = Array.isArray(j) ? j : j.agents || []; } catch {}
  if (a.status === 404) return bad('n8n has no published "Jarvis agents" workflow',
    'n8n → open the NEW "Jarvis agents" (imported in Part B) → Publish. If publishing fails: the old one is still published, unpublish and archive it first');
  if (a.status === 403 || a.status === 401) return bad('n8n refused the Jarvis secret',
    'In the new workflow, both webhook nodes ("which agents?" and "do this task") need Credential = "Jarvis Live secret". Save, Publish again');
  if (a.status !== 200) return bad(`n8n answered HTTP ${a.status} ${a.text.slice(0, 120)}`, 'docker logs --tail 30 n8n');
  if (!list.some((x) => x.id === 'reminders')) return bad(`n8n answers, but the agent list is ${JSON.stringify(list)}: that's the OLD Lesson 09 workflow`,
    'Unpublish + archive the old "Jarvis agents"; publish the new one from Part B (its "Agent list" node lists Reminders)');
  ok(`n8n lists: ${list.map((x) => x.id).join(', ')}`);

  console.log('3/5  Reminders agent answers (asks for your list)');
  const t = await get(env.N8N_TOOL_URL, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify({ agent: 'reminders', task: '{"action":"list"}', owner: 'check' }) });
  let tj = {}; try { tj = JSON.parse(t.text); } catch {}
  if (t.status === 200 && tj.ok) ok(`agent replied: ${String(tj.result).split('\n')[0]}`);
  else if (/No agent called/.test(t.text)) return bad('The task goes to the OLD workflow ("No agent … set up yet")', 'Unpublish + archive the old "Jarvis agents", publish the new one');
  else return bad(`agent call failed: HTTP ${t.status} ${t.text.slice(0, 160)}`, 'n8n → Executions → open the failed "Jarvis agents" run and read the red node');

  console.log('4/5  Jarvis Live sees the agent');
  for (let i = 0; i < 14 && !(h.agents || []).includes('reminders'); i++) { await sleep(5000); h = JSON.parse((await get('http://127.0.0.1:8080/health')).text || '{}'); }
  if ((h.agents || []).includes('reminders')) ok('Reminders is in Jarvis\'s agent list');
  else return bad(`Jarvis Live still has no agents (${h.n8n})`, 'docker restart jarvis-live, then run this check again');

  console.log('5/5  Your AI models can call agents (tool calling)');
  let store = {}; try { store = JSON.parse(require('fs').readFileSync((env.DATA_DIR || '/app/data') + '/providers.json', 'utf8')); } catch {}
  const line = (store.order || []).slice(0, 4).map((e) => { const [pid, ...m] = e.split('::'); return { p: (store.providers || []).find((x) => x.id === pid), m: m.join('::') }; }).filter((x) => x.p);
  if (!line.length) return bad('No models in line', 'Dashboard → AI providers → add a provider and its models');
  const tool = [{ type: 'function', function: { name: 'ask_agent', description: 'Give a task to an agent', parameters: { type: 'object', properties: { agent: { type: 'string', enum: ['reminders'] }, task: { type: 'string' } }, required: ['agent', 'task'] } } }];
  let good = 0;
  for (const { p, m } of line) {
    const r = await get(`${p.baseUrl}/chat/completions`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${p.key}` },
      body: JSON.stringify({ model: m, max_tokens: 300, tools: tool, messages: [{ role: 'system', content: 'Use ask_agent for reminders. Task format: {"action":"list"}' }, { role: 'user', content: 'What reminders do I have?' }] }) });
    let call; try { call = JSON.parse(r.text).choices?.[0]?.message?.tool_calls?.[0]; } catch {}
    if (call) { ok(`${p.name} · ${m}: calls agents`); good++; }
    else if (r.status !== 200) warn(`${p.name} · ${m}: HTTP ${r.status} ${r.text.slice(0, 100)}`, 'busy or out of quota now; Jarvis moves to the next model');
    else warn(`${p.name} · ${m}: answers, but does NOT call agents`, 'move a model that calls agents to the top (AI providers → ↑)');
  }
  if (!good) return bad('None of your first models calls agents', 'AI providers: put e.g. Groq openai/gpt-oss-120b or Gemini flash at the top, then run this check again');
  console.log(`\n${G}All links work.${O} Reload the dashboard and say: "Remind me in 2 minutes to drink water".`);
})();
JS
