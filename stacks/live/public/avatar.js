// Jarvis's avatar: an original AI sentinel (not based on any film character).
// A faceted helm floating inside an orbit ring, a glowing visor for eyes, and a voice grille whose light bars
// move with Jarvis's voice.
// States: idle/listening (hover, slow orbit, visor eyes glance and blink), thinking (ripple, fast orbit,
// visor scan), speaking (grille bars follow loudness and pitch).

const BARS = 9;
const SVG = `
<svg viewBox="0 0 300 360" class="twin" role="img" aria-label="Jarvis, AI sentinel">
  <defs>
    <linearGradient id="sn-shell" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0d2140"/><stop offset=".55" stop-color="#070f22"/><stop offset="1" stop-color="#160c33"/>
    </linearGradient>
    <linearGradient id="sn-plate" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#12305a" stop-opacity=".95"/><stop offset="1" stop-color="#0a1430" stop-opacity=".95"/>
    </linearGradient>
    <linearGradient id="sn-visor" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#1e5bff" stop-opacity=".2"/><stop offset=".5" stop-color="#38c8ff" stop-opacity=".55"/><stop offset="1" stop-color="#8c6cff" stop-opacity=".2"/>
    </linearGradient>
    <radialGradient id="sn-core" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#e6f6ff"/><stop offset=".35" stop-color="#38c8ff"/><stop offset="1" stop-color="#38c8ff" stop-opacity="0"/></radialGradient>
    <pattern id="sn-scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="1" fill="rgba(56,200,255,.08)"/></pattern>
    <filter id="sn-glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="2.4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="sn-ripple" x="-10%" y="-10%" width="120%" height="120%">
      <feTurbulence id="sn-noise" type="fractalNoise" baseFrequency="0.01 0.08" numOctaves="2" seed="11"/>
      <feDisplacementMap in="SourceGraphic" scale="0" id="sn-disp" xChannelSelector="R" yChannelSelector="G"/>
    </filter>
  </defs>

  <g filter="url(#sn-glow)">
    <ellipse cx="150" cy="170" rx="128" ry="34" fill="none" stroke="#8c6cff" stroke-opacity=".35" stroke-width="1.2" stroke-dasharray="3 7"/>
  </g>

  <g id="sn-all" filter="url(#sn-ripple)">
    <g id="sn-float">
      <g filter="url(#sn-glow)">
        <path d="M62 330 L98 286 L202 286 L238 330 L214 344 L86 344 Z" fill="url(#sn-plate)" stroke="#38c8ff" stroke-width="1.4"/>
        <path d="M110 286 L124 262 L176 262 L190 286" fill="url(#sn-plate)" stroke="#1e5bff" stroke-width="1.2"/>
        <circle cx="150" cy="312" r="9" fill="url(#sn-core)" id="sn-coreDot"/>
        <path d="M98 300 L126 300 M174 300 L202 300" stroke="#8c6cff" stroke-width="1.4" stroke-linecap="round"/>
      </g>

      <g id="sn-head" filter="url(#sn-glow)">
        <path d="M150 52 L210 78 L226 140 L214 214 L182 252 L118 252 L86 214 L74 140 L90 78 Z" fill="url(#sn-shell)" stroke="#38c8ff" stroke-width="1.8"/>
        <path d="M150 52 L150 98 M90 78 L118 104 M210 78 L182 104 M118 104 L182 104 M74 140 L102 150 M226 140 L198 150"
              stroke="#1e5bff" stroke-opacity=".7" stroke-width="1" fill="none"/>
        <path d="M118 104 L102 150 L106 196 M182 104 L198 150 L194 196" stroke="#8c6cff" stroke-opacity=".45" stroke-width="1" fill="none"/>
        <circle cx="150" cy="80" r="4" fill="#38c8ff" opacity=".9"/>

        <path d="M92 132 L208 132 L200 162 L100 162 Z" fill="#02040a" stroke="#38c8ff" stroke-width="1.4"/>
        <path id="sn-visorGlow" d="M96 134 L204 134 L197 160 L103 160 Z" fill="url(#sn-visor)"/>
        <rect id="sn-eyeL" x="112" y="141" width="26" height="8" rx="4" fill="#bff0ff"/>
        <rect id="sn-eyeR" x="162" y="141" width="26" height="8" rx="4" fill="#bff0ff"/>
        <rect id="sn-scanBar" x="98" y="134" width="6" height="26" fill="#e6f6ff" opacity="0"/>

        <path d="M112 186 L188 186 L180 226 L120 226 Z" fill="#02040a" stroke="#1e5bff" stroke-width="1.2"/>
        <g id="sn-bars"></g>
      </g>
    </g>
  </g>

  <g filter="url(#sn-glow)">
    <path id="sn-ringArc" d="M22 170 A128 34 0 0 0 278 170" fill="none" stroke="#38c8ff" stroke-opacity=".55" stroke-width="1.6"/>
    <circle id="sn-sat" r="3.4" fill="#e6f6ff"/>
  </g>
  <rect width="300" height="360" fill="url(#sn-scan)" pointer-events="none"/>
</svg>`;

export class Twin {
  constructor(host) {
    host.innerHTML = SVG;
    const q = (s) => host.querySelector(s);
    const barsG = q('#sn-bars'); this.bars = [];
    for (let i = 0; i < BARS; i++) {
      const r = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      r.setAttribute('x', (124 + i * 6.6).toFixed(1)); r.setAttribute('width', '3.6'); r.setAttribute('rx', '1.8'); r.setAttribute('fill', i % 2 ? '#8c6cff' : '#38c8ff');
      barsG.append(r); this.bars.push({ el: r, v: 0.08, phase: i * 0.9 });
    }
    this.el = { float: q('#sn-float'), head: q('#sn-head'), eyeL: q('#sn-eyeL'), eyeR: q('#sn-eyeR'), scanBar: q('#sn-scanBar'),
      visor: q('#sn-visorGlow'), disp: q('#sn-disp'), noise: q('#sn-noise'), sat: q('#sn-sat'), ringArc: q('#sn-ringArc'), core: q('#sn-coreDot') };
    this.state = 'idle'; this.ripple = 0; this.spin = 0;
    this.gaze = { x: 0, tx: 0, next: 0 }; this.blink = { at: performance.now() + 2200, until: 0 };
    this.reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  }
  setState(s) { this.state = s; }
  update(now, level = 0, bright = 0.5) {
    const e = this.el, speaking = this.state === 'speaking', thinking = this.state === 'thinking', still = this.reduced;
    e.float.setAttribute('transform', `translate(0 ${(still ? 0 : Math.sin(now / 900) * 3).toFixed(2)})`);
    e.head.setAttribute('transform', `rotate(${speaking ? (Math.sin(now / 700) * 1.2).toFixed(2) : thinking ? -1.5 : 0} 150 160)`);

    // orbit: a light travels the ring, faster while thinking
    this.spin += still ? 0 : thinking ? 0.035 : speaking ? 0.018 : 0.008;
    const a = this.spin % (Math.PI * 2);
    e.sat.setAttribute('cx', (150 + Math.cos(a) * 128).toFixed(1)); e.sat.setAttribute('cy', (170 + Math.sin(a) * 34).toFixed(1));
    e.sat.setAttribute('opacity', Math.sin(a) > 0 ? '1' : '0.25');
    e.ringArc.setAttribute('stroke-opacity', thinking ? '.9' : '.55');

    // visor eyes: blink (dim) and glance; scan sweep while thinking
    if (now > this.blink.at) { this.blink.until = now + 140; this.blink.at = now + 2600 + Math.random() * 3600; }
    const lidH = now < this.blink.until ? 1.5 : 8;
    if (now > this.gaze.next) {
      this.gaze.tx = thinking ? 0 : this.state === 'listening' || speaking ? (Math.random() - 0.5) * 4 : (Math.random() - 0.5) * 16;
      this.gaze.next = now + 1300 + Math.random() * 2400;
    }
    this.gaze.x += (this.gaze.tx - this.gaze.x) * 0.15;
    for (const [eye, x0] of [[e.eyeL, 112], [e.eyeR, 162]]) {
      eye.setAttribute('x', (x0 + this.gaze.x).toFixed(2)); eye.setAttribute('height', lidH); eye.setAttribute('y', (145 - lidH / 2).toFixed(2));
      eye.setAttribute('fill', thinking ? '#c9b8ff' : '#bff0ff');
    }
    if (thinking && !still) { e.scanBar.setAttribute('x', (98 + ((now / 700) % 1) * 100).toFixed(1)); e.scanBar.setAttribute('opacity', '.55'); }
    else e.scanBar.setAttribute('opacity', '0');
    e.visor.setAttribute('opacity', (0.75 + (speaking ? level * 0.5 : 0) + (still ? 0 : Math.sin(now / 1200) * 0.1)).toFixed(2));

    // voice grille: loudness raises the bars; bright sounds spread energy to the outer bars
    for (let i = 0; i < BARS; i++) {
      const b = this.bars[i], centre = 1 - Math.abs(i - (BARS - 1) / 2) / ((BARS - 1) / 2);
      const shape = speaking ? level * (0.45 + 0.55 * (bright * (1 - centre) + (1 - bright) * centre)) * (0.75 + 0.25 * Math.sin(now / 60 + b.phase)) : 0;
      const idle = still ? 0.08 : 0.06 + 0.04 * Math.sin(now / 500 + b.phase);
      b.v += (Math.max(idle, shape) - b.v) * 0.4;
      const h = 3 + b.v * 34; b.el.setAttribute('height', h.toFixed(2)); b.el.setAttribute('y', (206 - h / 2).toFixed(2));
    }
    e.core.setAttribute('r', (8 + (speaking ? level * 5 : Math.sin(now / 700))).toFixed(2));

    this.ripple += ((thinking && !still ? 6 : 0) - this.ripple) * 0.08;
    e.disp.setAttribute('scale', this.ripple.toFixed(2));
    if (this.ripple > 0.1) e.noise.setAttribute('baseFrequency', `${(0.01 + 0.006 * Math.sin(now / 260)).toFixed(4)} ${(0.06 + 0.04 * Math.sin(now / 150)).toFixed(4)}`);
  }
}
