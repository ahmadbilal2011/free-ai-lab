// Microphone -> 16 kHz, 16-bit PCM chunks (~100 ms) for the Gemini Live API.
class PcmRecorder extends AudioWorkletProcessor {
  constructor() { super(); this.ratio = sampleRate / 16000; this.pos = 0; this.buf = []; }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (ch) {
      // simple downsampling: pick samples at 16 kHz spacing
      for (; this.pos < ch.length; this.pos += this.ratio) this.buf.push(ch[Math.floor(this.pos)]);
      this.pos -= ch.length;
      if (this.buf.length >= 1600) {                       // 100 ms at 16 kHz
        const out = new Int16Array(this.buf.length);
        for (let i = 0; i < this.buf.length; i++) { const s = Math.max(-1, Math.min(1, this.buf[i])); out[i] = s < 0 ? s * 0x8000 : s * 0x7fff; }
        this.port.postMessage(out.buffer, [out.buffer]);
        this.buf = [];
      }
    }
    return true;
  }
}
registerProcessor('pcm-recorder', PcmRecorder);
