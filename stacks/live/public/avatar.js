// Jarvis's digital twin: a holographic, vector-drawn likeness (black cap, beard, white striped shirt).
// States: idle / listening (breathing, eyes forward, natural blinks), thinking (digital ripple, eyes drift up),
// speaking (mouth shapes follow the live voice: loudness opens the jaw, pitch brightness widens or rounds the lips).

const SVG = `
<svg viewBox="0 0 300 360" class="twin" role="img" aria-label="Jarvis digital twin">
  <defs>
    <linearGradient id="tw-skin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#7fd8ff" stop-opacity=".30"/><stop offset="1" stop-color="#8c6cff" stop-opacity=".18"/>
    </linearGradient>
    <linearGradient id="tw-beard" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0b1a33" stop-opacity=".85"/><stop offset="1" stop-color="#140c2e" stop-opacity=".95"/>
    </linearGradient>
    <pattern id="tw-stripes" width="12" height="12" patternUnits="userSpaceOnUse">
      <rect width="12" height="12" fill="rgba(230,246,255,.14)"/><rect x="5" width="2.2" height="12" fill="rgba(230,246,255,.55)"/>
    </pattern>
    <pattern id="tw-scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="1" fill="rgba(56,200,255,.10)"/></pattern>
    <filter id="tw-glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="tw-ripple" x="-10%" y="-10%" width="120%" height="120%">
      <feTurbulence id="tw-noise" type="fractalNoise" baseFrequency="0.01 0.08" numOctaves="2" seed="7"/>
      <feDisplacementMap in="SourceGraphic" scale="0" id="tw-disp" xChannelSelector="R" yChannelSelector="G"/>
    </filter>
  </defs>

  <g id="tw-all" filter="url(#tw-ripple)">
    <g id="tw-body" filter="url(#tw-glow)">
      <path d="M22 360 C34 302 86 280 120 272 L180 272 C214 280 266 302 278 360 Z" fill="url(#tw-stripes)" stroke="#38c8ff" stroke-width="1.6"/>
      <path d="M120 272 L150 306 L180 272" fill="none" stroke="#e6f6ff" stroke-opacity=".7" stroke-width="1.6"/>
      <path d="M128 238 L128 276 Q150 292 172 276 L172 238 Z" fill="url(#tw-skin)" stroke="#38c8ff" stroke-width="1.2"/>
    </g>

    <g id="tw-head" filter="url(#tw-glow)">
      <ellipse cx="90" cy="172" rx="9" ry="18" fill="url(#tw-skin)" stroke="#38c8ff" stroke-width="1.2"/>
      <ellipse cx="210" cy="172" rx="9" ry="18" fill="url(#tw-skin)" stroke="#38c8ff" stroke-width="1.2"/>
      <path d="M93 138 C93 92 207 92 207 138 L205 190 C203 228 180 254 150 256 C120 254 97 228 95 190 Z" fill="url(#tw-skin)" stroke="#38c8ff" stroke-width="1.6"/>
      <path d="M95 130 C95 152 99 158 102 166 M205 130 C205 152 201 158 198 166" stroke="#0b1a33" stroke-width="7" fill="none" stroke-linecap="round"/>

      <!-- beard: cheeks + upper beard stay, chin moves with the jaw -->
      <path d="M96 176 C98 200 106 214 118 222 L182 222 C194 214 202 200 204 176 C200 196 190 206 178 208 Q150 200 122 208 C110 206 100 196 96 176 Z" fill="url(#tw-beard)" stroke="#5b8cff" stroke-width="1"/>
      <g id="tw-jaw">
        <path d="M110 216 C116 240 132 258 150 260 C168 258 184 240 190 216 Q172 230 150 230 Q128 230 110 216 Z" fill="url(#tw-beard)" stroke="#5b8cff" stroke-width="1"/>
        <path id="tw-lowlip" d="M136 224 Q150 232 164 224" fill="none" stroke="#ff9ad5" stroke-opacity=".8" stroke-width="2" stroke-linecap="round"/>
      </g>
      <ellipse id="tw-mouth" cx="150" cy="221" rx="13" ry="1.2" fill="#05020c" stroke="#ff9ad5" stroke-opacity=".6" stroke-width="1"/>
      <path d="M124 210 Q137 201 150 206 Q163 201 176 210 Q164 214 150 212 Q136 214 124 210 Z" fill="#0b1a33" stroke="#5b8cff" stroke-width="1"/>

      <path d="M150 158 Q146 182 140 192 Q150 198 160 192" fill="none" stroke="#7fd8ff" stroke-opacity=".75" stroke-width="1.4" stroke-linecap="round"/>
      <path id="tw-browL" d="M108 146 Q122 138 136 144" fill="none" stroke="#0b1a33" stroke-width="5" stroke-linecap="round"/>
      <path id="tw-browR" d="M164 144 Q178 138 192 146" fill="none" stroke="#0b1a33" stroke-width="5" stroke-linecap="round"/>
      <g id="tw-eyeL" class="tw-eye" transform-origin="122 160">
        <path d="M108 160 Q122 150 136 160 Q122 168 108 160 Z" fill="rgba(230,246,255,.85)" stroke="#38c8ff" stroke-width="1"/>
        <g class="tw-pupil"><circle cx="122" cy="159.5" r="5.2" fill="#1e5bff"/><circle cx="122" cy="159.5" r="2.4" fill="#02040a"/><circle cx="124" cy="157.6" r="1.1" fill="#fff"/></g>
      </g>
      <g id="tw-eyeR" class="tw-eye" transform-origin="178 160">
        <path d="M164 160 Q178 150 192 160 Q178 168 164 160 Z" fill="rgba(230,246,255,.85)" stroke="#38c8ff" stroke-width="1"/>
        <g class="tw-pupil"><circle cx="178" cy="159.5" r="5.2" fill="#1e5bff"/><circle cx="178" cy="159.5" r="2.4" fill="#02040a"/><circle cx="180" cy="157.6" r="1.1" fill="#fff"/></g>
      </g>

      <!-- black cap, worn forward -->
      <path d="M86 130 C86 62 214 62 214 130 Q150 116 86 130 Z" fill="#050a14" stroke="#38c8ff" stroke-width="1.6"/>
      <path d="M150 70 L150 122 M118 78 Q122 100 120 124 M182 78 Q178 100 180 124" stroke="#1e5bff" stroke-opacity=".5" stroke-width="1" fill="none"/>
      <circle cx="150" cy="69" r="3.5" fill="#050a14" stroke="#38c8ff" stroke-width="1"/>
      <path d="M80 130 Q150 110 220 130 Q214 146 150 152 Q86 146 80 130 Z" fill="#02060e" stroke="#8c6cff" stroke-width="1.6"/>
      <path d="M92 138 Q150 126 208 138" fill="none" stroke="#8c6cff" stroke-opacity=".45" stroke-width="1"/>
    </g>
  </g>
  <rect width="300" height="360" fill="url(#tw-scan)" pointer-events="none"/>
  <rect id="tw-sweep" x="0" y="0" width="300" height="18" fill="rgba(56,200,255,.10)" pointer-events="none"/>
</svg>`;

export class Twin {
  constructor(host) {
    host.innerHTML = SVG;
    const q = (s) => host.querySelector(s);
    this.el = { body: q('#tw-body'), head: q('#tw-head'), jaw: q('#tw-jaw'), mouth: q('#tw-mouth'), lowlip: q('#tw-lowlip'),
      eyes: [q('#tw-eyeL'), q('#tw-eyeR')], pupils: [...host.querySelectorAll('.tw-pupil')], noise: q('#tw-noise'), disp: q('#tw-disp'),
      browL: q('#tw-browL'), browR: q('#tw-browR'), sweep: q('#tw-sweep') };
    this.state = 'idle'; this.open = 0; this.width = 1; this.ripple = 0;
    this.gaze = { x: 0, y: 0, tx: 0, ty: 0, next: 0 }; this.blink = { at: performance.now() + 2500, until: 0 };
    this.reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  }
  setState(s) { this.state = s; }
  // level: 0..1 loudness of Jarvis's voice; bright: 0..1 share of high frequencies (ee/s sounds → wide, oo → round)
  update(now, level = 0, bright = 0.5) {
    const e = this.el, speaking = this.state === 'speaking', thinking = this.state === 'thinking';
    const breathe = this.reduced ? 0 : Math.sin(now / 760);
    e.body.setAttribute('transform', `translate(0 ${breathe * 1.6})`);
    const nod = speaking ? Math.sin(now / 210) * level * 1.4 : 0;
    e.head.setAttribute('transform', `translate(0 ${breathe * 1.1 + nod}) rotate(${speaking ? Math.sin(now / 900) * 1.2 : thinking ? -1.5 : 0} 150 200)`);

    // mouth: open with loudness, wide or round with brightness
    const targetOpen = speaking ? Math.min(1, level * 1.15) : 0;
    this.open += (targetOpen - this.open) * 0.45;
    this.width += ((speaking ? 0.75 + bright * 0.55 : 1) - this.width) * 0.25;
    e.mouth.setAttribute('ry', (1.2 + this.open * 5.6).toFixed(2));
    e.mouth.setAttribute('rx', Math.max(9.5, 14 * this.width).toFixed(2));
    e.mouth.setAttribute('cy', (221 + this.open * 3).toFixed(2));
    e.jaw.setAttribute('transform', `translate(0 ${(this.open * 7).toFixed(2)})`);

    // eyes: natural blinks and small glances; look up-left while thinking
    if (now > this.blink.at) { this.blink.until = now + 130; this.blink.at = now + 2600 + Math.random() * 3800; }
    const lid = now < this.blink.until ? 0.12 : 1;
    for (const eye of e.eyes) eye.setAttribute('transform', `scale(1 ${lid})`);
    if (now > this.gaze.next) {
      const forward = this.state === 'listening' || speaking;
      this.gaze.tx = thinking ? -2.6 : forward ? (Math.random() - 0.5) * 1.6 : (Math.random() - 0.5) * 4.5;
      this.gaze.ty = thinking ? -2.2 : forward ? 0 : (Math.random() - 0.5) * 2;
      this.gaze.next = now + 1200 + Math.random() * 2600;
    }
    this.gaze.x += (this.gaze.tx - this.gaze.x) * 0.2; this.gaze.y += (this.gaze.ty - this.gaze.y) * 0.2;
    for (const p of e.pupils) p.setAttribute('transform', `translate(${this.gaze.x.toFixed(2)} ${this.gaze.y.toFixed(2)})`);
    const lift = thinking ? -3 : speaking ? -level * 2 : 0;
    e.browL.setAttribute('transform', `translate(0 ${lift})`); e.browR.setAttribute('transform', `translate(0 ${lift})`);

    // digital ripple while thinking
    this.ripple += ((thinking && !this.reduced ? 7 : 0) - this.ripple) * 0.08;
    e.disp.setAttribute('scale', this.ripple.toFixed(2));
    if (this.ripple > 0.1) e.noise.setAttribute('baseFrequency', `${(0.01 + 0.006 * Math.sin(now / 260)).toFixed(4)} ${(0.06 + 0.04 * Math.sin(now / 150)).toFixed(4)}`);
    e.sweep.setAttribute('y', this.reduced ? -20 : ((now / 14) % 400) - 20);
  }
}
