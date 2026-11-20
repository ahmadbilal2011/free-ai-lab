// Holographic globe for the Multi-Agent Operations panel.
// A dotted Earth (continents as simplified outlines → dots), your server's location, and an orbit ring of agents.
// Working agents fire an arc from the server into their node, with a travelling pulse.

// Simplified continent outlines as [longitude, latitude] — recognisable at dot resolution, no map files needed.
const LAND = [
  [[-168,66],[-160,70],[-140,70],[-125,70],[-110,73],[-95,72],[-80,73],[-70,67],[-62,60],[-55,52],[-66,45],[-70,42],[-76,38],[-81,31],[-80,25],[-82,27],[-84,30],[-90,30],[-97,27],[-97,22],[-92,18],[-88,21],[-87,16],[-83,10],[-79,9],[-77,8],[-82,8],[-86,12],[-92,14],[-98,16],[-105,20],[-110,24],[-112,30],[-117,32],[-121,36],[-124,41],[-124,48],[-131,55],[-140,60],[-150,60],[-155,58],[-165,60]],
  [[-77,8],[-72,12],[-62,11],[-52,5],[-50,0],[-44,-2],[-35,-5],[-35,-9],[-39,-14],[-41,-22],[-48,-26],[-53,-33],[-58,-38],[-62,-40],[-65,-45],[-68,-50],[-69,-53],[-74,-52],[-75,-46],[-73,-40],[-71,-30],[-71,-20],[-76,-14],[-81,-6],[-80,0],[-78,3]],
  [[-17,21],[-16,14],[-17,12],[-12,7],[-7,4],[0,5],[5,4],[9,4],[9,-1],[12,-5],[13,-12],[12,-17],[15,-27],[18,-34],[20,-35],[26,-34],[31,-29],[33,-25],[35,-20],[36,-15],[40,-10],[40,-5],[42,0],[48,5],[51,11],[44,11],[43,13],[39,16],[36,22],[35,28],[33,31],[29,31],[20,32],[15,32],[11,33],[10,37],[3,37],[-2,35],[-6,35],[-10,30],[-13,27]],
  [[-10,36],[-9,43],[-2,44],[-5,48],[2,51],[5,53],[8,54],[10,57],[5,59],[5,62],[14,68],[20,70],[30,70],[40,67],[44,68],[55,69],[70,73],[80,73],[100,77],[115,74],[130,71],[140,72],[160,70],[180,69],[180,65],[170,60],[163,58],[160,53],[156,57],[150,59],[142,59],[140,53],[135,48],[132,43],[129,40],[127,35],[126,38],[122,40],[119,39],[121,32],[122,30],[119,25],[113,22],[108,21],[106,17],[109,12],[105,9],[103,10],[100,13],[99,8],[103,1],[101,3],[98,8],[98,16],[94,17],[91,22],[87,21],[80,15],[78,8],[76,10],[73,17],[72,21],[67,24],[62,25],[57,26],[56,23],[59,22],[55,17],[52,16],[45,13],[43,13],[39,21],[35,28],[34,31],[35,36],[28,37],[26,40],[23,40],[20,40],[19,42],[14,45],[13,42],[16,40],[16,38],[12,38],[12,42],[10,44],[7,44],[3,43],[-1,37],[-6,36]],
  [[-5,50],[1,51],[2,53],[0,54],[-2,56],[-2,58],[-5,58],[-6,56],[-5,54],[-3,54],[-5,52]],
  [[-10,52],[-6,52],[-6,55],[-8,55],[-10,54]],
  [[-24,64],[-22,66],[-15,66],[-14,64],[-20,63]],
  [[-73,78],[-60,82],[-30,83],[-20,80],[-20,75],[-22,70],[-32,68],[-40,65],[-43,60],[-48,61],[-52,65],[-55,70],[-60,76]],
  [[114,-22],[114,-26],[115,-34],[118,-35],[124,-34],[130,-32],[135,-35],[138,-35],[140,-38],[146,-39],[150,-37],[153,-30],[153,-25],[146,-19],[142,-11],[141,-15],[136,-12],[130,-12],[126,-14],[122,-18]],
  [[95,5],[98,4],[104,-2],[106,-6],[101,-3]], [[109,2],[112,3],[116,7],[119,5],[118,1],[116,-4],[110,-3]], [[105,-6],[114,-7],[114,-8],[106,-7]],
  [[131,-1],[138,-2],[145,-4],[150,-10],[142,-9],[138,-8]], [[130,31],[132,34],[136,35],[140,36],[141,41],[142,45],[144,44],[141,38],[140,35],[135,33]],
  [[120,18],[122,18],[124,12],[126,7],[122,7],[120,14]], [[44,-25],[47,-25],[50,-15],[49,-12],[44,-16]],
  [[172,-34],[175,-37],[178,-38],[175,-42],[171,-46],[167,-46],[172,-41],[174,-41]], [[80,6],[82,7],[81,10],[79,9]],
];
function inPoly(lon, lat, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > lat) !== (yj > lat) && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function buildDots(step = 1.6) {
  const dots = [];
  for (let lat = -56; lat <= 83; lat += step) {
    const n = Math.max(6, Math.round((360 / step) * Math.cos((lat * Math.PI) / 180)));
    for (let k = 0; k < n; k++) {
      const lon = -180 + (k * 360) / n;
      if (LAND.some((p) => inPoly(lon, lat, p))) dots.push([lon, lat]);
    }
  }
  return dots;
}
const RAD = Math.PI / 180;

export class Globe {
  constructor(canvas, { home = { lat: 24.7, lon: 46.7, label: 'Your server · Riyadh' } } = {}) {
    this.c = canvas; this.ctx = canvas.getContext('2d');
    this.dots = buildDots(); this.home = home;
    this.rot = -home.lon + 20; this.tilt = 18;            // start with your server in view
    this.agents = []; this.active = new Map(); this.pings = []; this.reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  }
  setAgents(list) { this.agents = list.filter((a) => a.id !== 'core'); }
  setActive(map) { this.active = map; }
  ping(lat, lon, color = '#38c8ff') { this.pings.push({ lat, lon, color, t0: performance.now() }); }

  project(lon, lat, R, cx, cy) {
    const l = (lon + this.rot) * RAD, p = lat * RAD, t = this.tilt * RAD;
    const x = Math.cos(p) * Math.sin(l), y0 = Math.sin(p), z0 = Math.cos(p) * Math.cos(l);
    const y = y0 * Math.cos(t) - z0 * Math.sin(t), z = y0 * Math.sin(t) + z0 * Math.cos(t);
    return { x: cx + x * R, y: cy - y * R, z };
  }
  draw(now) {
    const c = this.c, d = devicePixelRatio || 1, r = c.getBoundingClientRect();
    if (!r.width) return;
    if (c.width !== Math.round(r.width * d) || c.height !== Math.round(r.height * d)) { c.width = Math.round(r.width * d); c.height = Math.round(r.height * d); }
    const ctx = this.ctx, W = c.width, H = c.height, cx = W / 2, cy = H * 0.5;
    const R = Math.min(W * 0.3, H * 0.36), busy = this.active.size > 0;
    if (!this.reduced) this.rot += busy ? 0.09 : 0.04;
    ctx.clearRect(0, 0, W, H);

    // atmosphere
    const g = ctx.createRadialGradient(cx, cy, R * 0.6, cx, cy, R * 1.35);
    g.addColorStop(0, 'rgba(30,91,255,0.20)'); g.addColorStop(0.75, 'rgba(140,108,255,0.10)'); g.addColorStop(1, 'rgba(140,108,255,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, R * 1.35, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = 'rgba(56,200,255,0.35)'; ctx.lineWidth = 1 * d; ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.stroke();

    // graticule (latitude lines)
    ctx.strokeStyle = 'rgba(56,200,255,0.08)';
    for (let lat = -60; lat <= 60; lat += 30) {
      ctx.beginPath(); let first = true;
      for (let lon = -180; lon <= 180; lon += 6) {
        const p = this.project(lon, lat, R, cx, cy);
        if (p.z < 0) { first = true; continue; }
        first ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y); first = false;
      }
      ctx.stroke();
    }
    // land dots
    for (const [lon, lat] of this.dots) {
      const p = this.project(lon, lat, R, cx, cy); if (p.z < 0.02) continue;
      ctx.fillStyle = `rgba(${Math.round(90 + 60 * p.z)},${Math.round(190 + 40 * p.z)},255,${0.25 + 0.65 * p.z})`;
      const s = (0.9 + p.z * 1.1) * d; ctx.fillRect(p.x - s / 2, p.y - s / 2, s, s);
    }
    // server location
    const hp = this.project(this.home.lon, this.home.lat, R, cx, cy), homeVisible = hp.z > 0;
    const pulse = (now / 1000) % 1.6 / 1.6;
    if (homeVisible) {
      ctx.strokeStyle = `rgba(255,200,87,${1 - pulse})`; ctx.lineWidth = 1.5 * d; ctx.beginPath(); ctx.arc(hp.x, hp.y, (4 + pulse * 16) * d, 0, Math.PI * 2); ctx.stroke();
      ctx.fillStyle = '#ffc857'; ctx.beginPath(); ctx.arc(hp.x, hp.y, 3 * d, 0, Math.PI * 2); ctx.fill();
      ctx.font = `${11 * d}px "Chakra Petch", system-ui, sans-serif`; ctx.fillStyle = 'rgba(255,200,87,.9)'; ctx.fillText(this.home.label, hp.x + 8 * d, hp.y - 8 * d);
    }
    // pings (events)
    this.pings = this.pings.filter((p) => now - p.t0 < 2400);
    for (const pg of this.pings) {
      const p = this.project(pg.lon, pg.lat, R, cx, cy); if (p.z < 0) continue; const k = (now - pg.t0) / 2400;
      ctx.strokeStyle = pg.color; ctx.globalAlpha = 1 - k; ctx.beginPath(); ctx.arc(p.x, p.y, (3 + k * 22) * d, 0, Math.PI * 2); ctx.stroke(); ctx.globalAlpha = 1;
    }
    // agent orbit ring (perspective ellipse) + nodes
    const rx = Math.min(W * (W < 520 * d ? 0.36 : 0.46), R * 1.75), ry = Math.min(H * 0.42, R * 1.12);
    ctx.strokeStyle = 'rgba(140,108,255,0.22)'; ctx.setLineDash([2 * d, 6 * d]); ctx.beginPath(); ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]);
    const n = this.agents.length;
    this.agents.forEach((a, i) => {
      const ang = -Math.PI / 2 + (i / n) * Math.PI * 2, x = cx + Math.cos(ang) * rx, y = cy + Math.sin(ang) * ry;
      const on = this.active.has(a.id);
      if (on) {                                                    // arc from server (or globe centre) to the agent
        const sx = homeVisible ? hp.x : cx, sy = homeVisible ? hp.y : cy, mx = (sx + x) / 2 + (cy - y) * 0.15, my = (sy + y) / 2 - (x - cx) * 0.1;
        ctx.strokeStyle = a.color; ctx.lineWidth = 1.6 * d; ctx.shadowColor = a.color; ctx.shadowBlur = 12 * d;
        ctx.beginPath(); ctx.moveTo(sx, sy); ctx.quadraticCurveTo(mx, my, x, y); ctx.stroke(); ctx.shadowBlur = 0;
        const t = (now / 900 + i * 0.37) % 1, bx = (1 - t) ** 2 * sx + 2 * (1 - t) * t * mx + t * t * x, by = (1 - t) ** 2 * sy + 2 * (1 - t) * t * my + t * t * y;
        ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(bx, by, 2.4 * d, 0, Math.PI * 2); ctx.fill();
      }
      ctx.fillStyle = 'rgba(2,4,10,.92)'; ctx.strokeStyle = a.color; ctx.lineWidth = (on ? 2.4 : 1.2) * d;
      if (on) { ctx.shadowColor = a.color; ctx.shadowBlur = 16 * d; }
      ctx.beginPath(); ctx.arc(x, y, (on ? 9 : 7) * d, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
      ctx.textAlign = 'center'; ctx.font = `${(on ? 12 : 11) * d}px "Chakra Petch", system-ui, sans-serif`;
      ctx.fillStyle = on ? '#e6f6ff' : 'rgba(180,210,230,.75)'; const below = y >= cy;
      ctx.fillText(a.name, x, y + (below ? 22 : -14) * d);
      if (on) { const task = this.active.get(a.id) || ''; ctx.font = `${10 * d}px system-ui, sans-serif`; ctx.fillStyle = 'rgba(180,210,230,.85)';
        ctx.fillText(task.length > 38 ? task.slice(0, 37) + '…' : task, x, y + (below ? 36 : -28) * d); }
      ctx.textAlign = 'start';
    });
  }
}
