// Records the game (image + sound) to a video file the player can post:
// MP4 (H.264) when the browser can, otherwise WebM. The recording is a
// composite canvas: the 3D view plus a small watermark and the objective.
export class Recorder {
  constructor(glCanvas, audio) {
    this.gl = glCanvas;
    this.audio = audio;
    this.rec = null;
    this.started = 0;
    this.canvas = document.createElement('canvas');
    this.ctx = this.canvas.getContext('2d');
  }

  get active() { return !!this.rec; }
  get elapsed() { return this.rec ? (performance.now() - this.started) / 1000 : 0; }

  static mime() {
    const types = ['video/mp4;codecs=avc1.42E01E,mp4a.40.2', 'video/mp4', 'video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm'];
    return types.find((t) => window.MediaRecorder && MediaRecorder.isTypeSupported(t)) || '';
  }

  toggle(objective) {
    if (this.rec) { this.stop(); return false; }
    return this.start(objective);
  }

  start() {
    const mime = Recorder.mime();
    if (!mime) return false;
    const w = Math.min(1920, this.gl.width), h = Math.round(w * this.gl.height / this.gl.width);
    this.canvas.width = w & ~1;
    this.canvas.height = h & ~1;
    const stream = this.canvas.captureStream(30);
    if (this.audio.recordDest) for (const t of this.audio.recordDest.stream.getAudioTracks()) stream.addTrack(t);
    this.chunks = [];
    this.mime = mime;
    this.rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 8_000_000 });
    this.rec.ondataavailable = (e) => { if (e.data.size) this.chunks.push(e.data); };
    this.rec.onstop = () => this._save();
    this.rec.start(1000);
    this.started = performance.now();
    return true;
  }

  stop() {
    if (!this.rec) return;
    this.rec.stop();
    this.rec = null;
  }

  // Called right after the frame is rendered (the WebGL buffer is valid).
  capture(objective) {
    if (!this.rec) return;
    const c = this.ctx, W = this.canvas.width, H = this.canvas.height;
    c.drawImage(this.gl, 0, 0, W, H);
    c.font = `600 ${Math.round(H * 0.022)}px sans-serif`;
    c.fillStyle = 'rgba(255,255,255,0.75)';
    c.textAlign = 'right';
    c.fillText('COCKROACH', W - H * 0.03, H - H * 0.03);
    if (objective) {
      c.textAlign = 'left';
      c.fillStyle = 'rgba(246,195,67,0.9)';
      c.fillText('◆ ' + objective, H * 0.03, H * 0.05);
    }
  }

  _save() {
    const ext = this.mime.startsWith('video/mp4') ? 'mp4' : 'webm';
    const blob = new Blob(this.chunks, { type: this.mime.split(';')[0] });
    download(blob, `cockroach-${stamp()}.${ext}`);
  }

  static photo(glCanvas) {
    glCanvas.toBlob((b) => b && download(b, `cockroach-${stamp()}.png`), 'image/png');
  }
}

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function download(blob, name) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
}
